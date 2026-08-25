#!/usr/bin/env python3
"""Extract candidate write targets from a shell command string (row H7b).

WHY A MODULE AND NOT A HEREDOC
------------------------------
The first cut of scripts/bash-write-guard-hook.sh embedded this as
``TARGETS=$(... python3 <<'PY' ... PY)``. Bash parses quotes *inside* a heredoc
that sits inside a command substitution, and this code is nothing but quotes and
regex — the hook failed to parse at all, silently allowing every write it was
written to stop. A guard that cannot be loaded is a guard that allows, which is
the exact failure this row exists to remove, so the parser lives in its own file
where the shell never reads it.

TWO MODES
  extract   CMD_TEXT + CWD_PATH in the environment -> absolute write targets
  --group   newline-separated paths on stdin       -> one representative per group

GROUPING — exact, not a sample
------------------------------
All three pipeline guards decide from the path alone: a glob allowlist, an
extension test, and a walk up to the .git boundary. Two files that share a
directory AND an extension are therefore guaranteed identical verdicts from all
three. Collapsing them to one representative is an identity, not an
approximation — which is what lets the callers' caps be honest about coverage.

COVERAGE BOUND
--------------
Six forms: redirection > and >> (also how a heredoc writes), sed -i, tee, cp, mv.
This is a string parser; it cannot see a write done by an interpreter, behind
eval, through xargs, or via a runtime-assembled path. Those are caught by
scripts/bash-write-detect-hook.sh, which watches the filesystem instead.

Covers: SC-1437 SC-1439
"""

from __future__ import annotations

import os
import re
import sys

# A shell word: double-quoted, single-quoted, or bare. The bare form deliberately
# stops at the metacharacters that end a word, so `>f;ls` yields "f" and not "f;ls".
QUOTED = r"""(?:"([^"]+)"|'([^']+)'|([^\s;|&<>()]+))"""

# Paths that are writes in form only. /dev/null is the single most common redirect
# target in this repo's own scripts.
NON_FILES = ("/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty", "/dev/fd")


def _pick(match: re.Match, base: int) -> str | None:
    for g in (base, base + 1, base + 2):
        if match.group(g):
            return match.group(g)
    return None


def strip_heredoc_bodies(cmd: str) -> str:
    """Remove heredoc BODIES, keeping the opening line.

    A body is arbitrary text; a line inside it that happens to read ``> foo.cs``
    is not a redirection this command performs. The opening line stays, so
    ``cat > src/App.cs <<'EOF'`` is still seen as a redirection to src/App.cs —
    which is the whole reason heredoc counts as one of the six covered forms.
    """
    lines = cmd.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = re.search(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        i += 1
        if m:
            term = m.group(2)
            while i < len(lines) and lines[i].strip() != term:
                i += 1
            i += 1  # drop the terminator line too
    return "\n".join(out)


def extract(cmd: str) -> list[str]:
    """Return raw (possibly relative) write targets, in order of appearance."""
    text = strip_heredoc_bodies(cmd)
    targets: list[str] = []

    # (a) redirection. The negative lookbehind keeps file-descriptor work out:
    #     2>&1, 1>&2 and &> are not writes to a file called "1".
    for m in re.finditer(r"(?<![0-9&])>{1,2}\s*" + QUOTED, text):
        t = _pick(m, 1)
        if t and not t.startswith("&"):
            targets.append(t)

    segments = re.split(r"[;&|\n]+", text)

    # (b) sed -i / --in-place. GNU takes the file straight after the flag; BSD and
    #     macOS take a backup-suffix argument first (`sed -i '' 's/x/y/' f`).
    #     Rather than model two dialects, take every non-option word in the
    #     segment: the script word (`s/x/y/`) survives here but is dropped
    #     downstream, because it has no source-code extension and so every guard
    #     allows it.
    for seg in segments:
        if not re.search(r"\bsed\b", seg):
            continue
        if not re.search(r"\s-i\b|\s--in-place\b|\s-[a-hj-zA-Z]*i[a-zA-Z]*\b", seg):
            continue
        for m in re.finditer(QUOTED, seg):
            t = _pick(m, 1)
            if t and not t.startswith("-") and t != "sed":
                targets.append(t)

    # (c) tee [-a] FILE...
    for m in re.finditer(r"\btee\b((?:\s+-\w+)*)((?:\s+" + QUOTED + r")+)", text):
        for m2 in re.finditer(QUOTED, m.group(2)):
            t = _pick(m2, 1)
            if t and not t.startswith("-"):
                targets.append(t)

    # (d) cp / mv — the destination is the last operand of the segment.
    for seg in segments:
        if not re.match(r"\s*(sudo\s+)?(cp|mv)\b", seg):
            continue
        ops = [_pick(m, 1) for m in re.finditer(QUOTED, seg)]
        ops = [o for o in ops if o and not o.startswith("-")]
        if len(ops) >= 3:  # ["cp", src, ..., dst]
            targets.append(ops[-1])

    return targets


def absolutize(targets: list[str], cwd: str) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for t in targets:
        t = t.strip()
        if not t:
            continue
        # A path assembled at runtime. This is the declared bound, not an
        # oversight: guessing what $DIR expands to would invent a finding.
        if t.startswith("$") or t.startswith("`") or "$(" in t:
            continue
        if t in NON_FILES or t.startswith("/dev/fd/"):
            continue
        p = t if os.path.isabs(t) else os.path.normpath(os.path.join(cwd, t))
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def representatives(paths: list[str]) -> list[str]:
    groups: dict[tuple[str, str], str] = {}
    order: list[tuple[str, str]] = []
    for p in paths:
        key = (os.path.dirname(p), os.path.splitext(p)[1].lower())
        if key not in groups:
            groups[key] = p
            order.append(key)
    return [groups[k] for k in order]


def main(argv: list[str]) -> int:
    if "--group" in argv:
        paths = [ln.strip() for ln in sys.stdin.read().split("\n") if ln.strip()]
        for r in representatives(paths):
            print(r)
        return 0

    cmd = os.environ.get("CMD_TEXT", "")
    cwd = os.environ.get("CWD_PATH", "") or os.getcwd()
    if not cmd:
        return 0
    paths = absolutize(extract(cmd), cwd)
    if not paths:
        return 0
    # Line 1 is the total target count (so a caller can report it); the rest are
    # the representatives it should actually check.
    print(len(paths))
    for r in representatives(paths):
        print(r)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
