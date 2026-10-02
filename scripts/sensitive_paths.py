#!/usr/bin/env python3
"""Find a credential path in a PreToolUse payload (spec 083, R10, F039).

Reads the payload JSON on stdin and prints one line:

    none                nothing sensitive named
    hit <path>          the first sensitive path (a path, never a whole command)
    unparseable         the payload is not a JSON object

WHAT IS SENSITIVE. A path is sensitive when one of its segments is `.ssh`, `.aws`, `.azure`, `.kube`
or `.gnupg`; when it ends in `.docker/config.json` or runs through `.config/gh`; or when its basename
is `.git-credentials`, `.netrc`, `.npmrc`, `.env` or `.env.<suffix>`. `.env.example`, `.env.sample`
and `.env.template` are templates with empty placeholders (.claude/docs/security.md) and pass — the
developer's choice, spec 083 O1. A glob counts when its basename could match one of those names.

WHERE IT LOOKS. file_path (Read, Edit, Write, MultiEdit), notebook_path (NotebookEdit), path and glob
(Grep), path and pattern (Glob), and every word of a Bash command, split the way the shell splits
it and again on `=` and `:` so `--file=~/.ssh/id_rsa` and `<~/.netrc` are seen. A commit message is
one word, and "fix .env loading" is not a path whose basename is `.env`.

THE BOUND. Only named paths. `grep -r foo .` reads .env without naming it; a path built at runtime
(`cat "$HOME/$(echo .ssh)/id_rsa"`) is assembled after this runs.
"""
from __future__ import annotations

import fnmatch
import json
import re
import shlex
import sys

SEGMENTS = {".ssh", ".aws", ".azure", ".kube", ".gnupg"}
BASENAMES = {".git-credentials", ".netrc", ".npmrc", ".env", ".envrc", ".pgpass", ".pypirc"}
ENV_TEMPLATES = {".env.example", ".env.sample", ".env.template"}
# Concrete names a glob is tried against: if the glob could match one, it reaches a secret.
PROBES = sorted(BASENAMES | {".env.local", ".env.production", ".env.development"})


def _alternatives(segment: str) -> list[str]:
    """One level of brace expansion: `{.ssh,x}` is `.ssh` or `x` to the shell."""
    m = re.search(r"\{([^{}]*,[^{}]*)\}", segment)
    if not m:
        return [segment]
    return [segment[:m.start()] + alt + segment[m.end():] for alt in m.group(1).split(",")]


def _segment_hit(s: str) -> bool:
    for alt in _alternatives(s):
        if alt in SEGMENTS:
            return True
        # A glob segment reaches a dot directory only when it starts with a dot (the shell's rule).
        if alt.startswith(".") and any(c in alt for c in "*?[") \
                and any(fnmatch.fnmatchcase(name, alt) for name in SEGMENTS):
            return True
    return False


def sensitive(p: str, shell: bool = False) -> bool:
    # Case-folded: macOS's default filesystem opens ~/.SSH/id_rsa. A Windows path's backslashes are
    # separators, but in a shell word a backslash is an escape (`grep "\.env"` searches for text).
    p = p.strip().lower()
    if not shell:
        p = p.replace("\\", "/")
    if not p:
        return False
    parts = [s for s in p.split("/") if s]
    if not parts:
        return False
    if any(_segment_hit(s) for s in parts):
        return True
    joined = "/" + "/".join(parts)
    if joined.endswith("/.docker/config.json") or "/.config/gh/" in joined + "/" \
            or "/.config/gcloud/" in joined + "/":
        return True
    base = parts[-1]
    if base in ENV_TEMPLATES:
        return False
    if base in BASENAMES or base.startswith(".env."):
        return True
    # A glob reaches a dotfile only when it starts with a dot itself — the shell's rule, and the one
    # that keeps `ls *` and a `**` in prose from reading as `.env`.
    if base.startswith(".") and any(c in base for c in "*?["):
        return any(fnmatch.fnmatchcase(name, base) for name in PROBES)
    return False


def _sibling():
    """destructive_command.py: one tokeniser and one definition of what the shell executes."""
    import importlib.util
    import os
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "destructive_command.py")
    spec = importlib.util.spec_from_file_location("destructive_command", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _split_word(w: str) -> list[str]:
    out = [w]
    for sep in ("=", ":"):
        if sep in w:
            out.extend(w.split(sep))
    return out


# Spec 090 R8(a) (F085): `sed 's/.env//' f.txt` was denied, because the script split on `/` ends in
# `.env`. A sed script is a pattern language, so a script that is ONE substitution or transliteration,
# with an optional numeric address and no `w` or `e` flag, cannot open a file and is not a path. Any
# other script stays a candidate: `r .env`, `R`, `w`, `W`, `e` and `s///w .env` read, write or run
# (spec 090 threat model, #3). A file operand (`sed … .env`) and `-f <file>` are paths as before.
_SED_PURE = re.compile(
    r"""^\s*(?:(?:\d+|\$)(?:\s*,\s*(?:\d+|\$))?\s*)?
        (?:s(?P<d>[^\w\s\\])(?:\\.|(?!(?P=d)).)*(?P=d)(?:\\.|(?!(?P=d)).)*(?P=d)[gpiImM0-9]*
          |y(?P<e>[^\w\s\\])(?:\\.|(?!(?P=e)).)*(?P=e)(?:\\.|(?!(?P=e)).)*(?P=e))
        \s*$""", re.S | re.X)


def sed_scripts(args: list[str]) -> list[tuple[str, str]]:
    """(token, script) for every script on a sed command line. One parser for both uses below
    (/simplify, spec 090): -e S, --expression=S, an attached -eS, and with none of those the first
    operand. -f FILE, --file=FILE, -l N and BSD's `-i ''` take their values; a script read from a file
    makes every operand a path."""
    scripts, explicit, operands, i = [], False, [], 0
    while i < len(args):
        a = args[i]
        if a == "--":
            operands.extend(args[i + 1:])
            break
        if a in ("-e", "--expression") or re.match(r"^-[nEsruz]*e$", a):
            if i + 1 < len(args):
                scripts.append((args[i + 1], args[i + 1]))
            explicit, i = True, i + 2
        elif a.startswith("--expression="):
            scripts.append((a, a.split("=", 1)[1]))
            explicit, i = True, i + 1
        elif re.match(r"^-[nEsruz]*e.", a):
            scripts.append((a, a[a.index("e") + 1:]))
            explicit, i = True, i + 1
        elif a == "--file" or re.match(r"^-[nEsruz]*f$", a):
            explicit, i = True, i + 2
        elif a.startswith("--file=") or re.match(r"^-[nEsruz]*f.", a):
            explicit, i = True, i + 1
        elif a in ("-l", "--line-length") or (a == "-i" and i + 1 < len(args) and args[i + 1] == ""):
            i += 2
        elif a.startswith("-") and len(a) > 1:
            i += 1
        else:
            operands.append(a)
            i += 1
    if not explicit and operands:
        scripts.append((operands[0], operands[0]))
    return scripts


def sed_data_tokens(args: list[str]) -> list[str]:
    """The tokens holding a pure s/// or y/// script: a pattern, not a path."""
    return [tok for tok, body in sed_scripts(args) if _SED_PURE.match(body)]


def sed_script_words(args: list[str]) -> list[str]:
    """The words inside every sed script that is NOT pure: `r .env` is one shell word, and its file
    name only shows once the script is split (spec 090 threat model, #3)."""
    out = []
    for _, body in sed_scripts(args):
        if _SED_PURE.match(body):
            continue
        out.extend(w for w in re.split(r"[\s;{}]+", body) if w)
        # GNU sed takes `rFILE`, `1r.env`, `/re/r.env` and the `s///wFILE` flag with no space, and
        # the file name runs to the end of the line. Every r/R/w/W is tried as a file command,
        # wherever it stands: over-reading a non-pure script costs a deny, never a leak
        # (adversarial review #4).
        for m in re.finditer(r"(?=[rRwW]\s*([^;\n}]+))", body):
            out.append(m.group(1).strip())
    return out


def shell_words(cmd: str, depth: int = 0) -> list[str]:
    """Every word the shell would execute, executed bodies included.

    Top-level words, plus the program of `sh -c '…'` / `eval '…'`, the body of `$(…)` and backticks,
    a here-string or heredoc fed to a shell, and text piped into one. A heredoc fed to `cat` and the
    message of `git commit -m` are data and are not split further, so prose naming .env is not a read.
    """
    try:
        d = _sibling()
    except Exception:
        # Without the sibling the whole command is split plainly: stricter, never looser.
        return [p for w in cmd.split() for p in _split_word(w)]
    cmd, docs = d.heredocs(d.normalise(cmd))
    lines = cmd.split("\n")
    bodies = {}
    for idx, body in docs:
        bodies.setdefault(idx, []).append(body)
    out = []
    for idx, line in enumerate(lines):
        for pipe in d.pipelines(d.tokens(line)):
            for n, seg in enumerate(pipe):
                words, here = d.strip_redirects(seg)
                # Resolve the command word the way the classifier does, then read what it executes.
                k = 0
                while k < len(words) and (d.ASSIGN.match(words[k]) or d.word(words[k]) in d.KEYWORDS
                                          or d.word(words[k]) in d.WRAPPERS or d.word(words[k]) in d.ESCALATE):
                    k += 1
                toks = [w for w in seg if not d.is_sep(w)]
                if k < len(words) and d.word(words[k]) == "sed":
                    for t in sed_data_tokens(words[k + 1:]):
                        if t in toks:
                            toks.remove(t)
                    toks.extend(sed_script_words(words[k + 1:]))
                out.extend(p for w in toks for p in _split_word(w))
                if depth >= d.MAX_DEPTH or k >= len(words):
                    continue
                w, args = d.word(words[k]), words[k + 1:]
                if w in d.SHELLS or w == "eval":
                    body = " ".join(args) if w == "eval" else d.shell_body(args)
                    upstream = " ".join(t for s in pipe[:n] for t in d.strip_redirects(s)[0][1:])
                    for text in (body, upstream, *here, *bodies.get(idx, [])):
                        if text:
                            out.extend(shell_words(text, depth + 1))
    if depth < d.MAX_DEPTH:
        for m in d.SUBST.finditer(cmd):
            body = m.group(1) if m.group(1) is not None else m.group(2)
            out.extend(shell_words(body, depth + 1))
    return out


def candidates(payload: dict) -> list[tuple[str, bool]]:
    """(text, is a shell word)."""
    tool = payload.get("tool_name") or ""
    ti = payload.get("tool_input")
    if not isinstance(ti, dict):
        return []
    out = []
    for key in ("file_path", "notebook_path", "path"):
        v = ti.get(key)
        if isinstance(v, str):
            out.append((v, False))
    if tool == "Glob" and isinstance(ti.get("pattern"), str):
        out.append((ti["pattern"], False))
    if isinstance(ti.get("glob"), str):
        out.append((ti["glob"], False))
    if isinstance(ti.get("command"), str):
        out.extend((w, True) for w in shell_words(ti["command"]))
    return out


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
    except Exception:
        print("unparseable")
        return 0
    if not isinstance(payload, dict):
        print("unparseable")
        return 0
    for c, shell in candidates(payload):
        if sensitive(c, shell):
            # One line, whatever the path holds.
            print("hit " + c.replace("\n", " ").replace("\r", " ")[:300])
            return 0
    print("none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
