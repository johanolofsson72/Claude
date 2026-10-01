#!/usr/bin/env python3
"""Classify a shell command against the destructive deny list (spec 083, R9, F038).

Called by scripts/destructive-command-guard-hook.sh with the command in $CMD_TEXT. Prints one line:

    none              nothing on the list
    <form>            the first destructive form found: rm-recursive-force, sudo, git-push-force,
                      git-reset-hard, git-clean-force, find-delete

WHY A TOKENISER. `permissions.deny` in .claude/settings.json matches by prefix: `Bash(rm -rf *)` does
not match `rm -r -f x`, `/bin/rm -rf x`, `command rm -rf x` or `git -C . push -f`, and under
bypassPermissions + `allow: Bash` every one of those ran (H1 adversarial #3). This reads the command
the way a shell would split it: quotes honoured, operators and keywords separating commands, the
command word resolved through the wrappers that only run another command, case folded (macOS
filesystems find /bin/RM).

WHAT IT DOES NOT DO (the declared bound). It recognises spellings; it does not evaluate. A variable
(`$RM -rf x`), an alias, a function, brace expansion (`{rm,-rf,x}`), a script that deletes,
`eval "$cmd"`, `python -c "shutil.rmtree(...)"` and `git -c alias.x='!rm -rf .' x` all pass. So does
every destructive command the deny list never named (dd, mkfs, git branch -D, git push --delete). A
literal `sh -c '...'`, `eval '...'`, `$(...)`, backtick body, here-string or heredoc fed to a shell, and
text piped into a shell are read, one level down per nesting, up to MAX_DEPTH.

Text that is an argument to a command which does not run it is data: `git commit -m "rm -rf x"` and
`echo rm -rf x` are not deletions. A quoted `$(...)` is read anyway — after shlex the quoting is gone,
so `echo '$(rm -rf x)'` is a false deny, the cheaper error.
"""
from __future__ import annotations

import os
import re
import shlex
import sys

MAX_DEPTH = 3
SEPARATORS = set(";&|()\n")
REDIRECT = re.compile(r"^[0-9]*(<|>|>>|<<|<<<|<>|>&|<&|&>|&>>|>\|)$")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh", "busybox-sh"}
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "}", "time", "fi", "done"}
ESCALATE = {"sudo", "doas", "su", "pkexec"}
# Wrappers that run the rest of their arguments as a command, with the options that take a value.
WRAPPERS = {
    "command": set(),
    "exec": {"-a"},
    "nohup": set(),
    "time": set(),
    "nice": {"-n"},
    "env": {"-u", "-C", "-S"},
    "xargs": {"-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a", "--max-args", "--max-procs",
              "--delimiter", "--arg-file", "--replace"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "builtin": set(),
    "stdbuf": {"-i", "-o", "-e"},
    "setsid": set(),
    "ionice": {"-c", "-n", "-p"},
    "caffeinate": {"-t", "-w"},
    "busybox": set(),
    "chronic": set(),
    "unbuffer": set(),
}
SUBST = re.compile(r"\$\(((?:[^()]|\([^()]*\))*)\)|`([^`]*)`")
ANSI_C = re.compile(r"\$'((?:[^'\\]|\\.)*)'")


def normalise(cmd: str) -> str:
    # A backslash-newline is removed by the shell before it splits words: `rm -r \<nl>-f x` is one
    # command. $'…' (ANSI-C quoting) is read as a plain single-quoted word; its escapes are not decoded.
    cmd = cmd.replace("\\\r\n", "").replace("\\\n", "")
    return ANSI_C.sub(lambda m: "'" + m.group(1).replace("'", "") + "'", cmd)


def tokens(cmd: str) -> list[str]:
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""            # shlex would end the line at a `#` inside a word (`a#b`)
    try:
        toks = list(lex)
    except ValueError:
        # An unclosed quote. The shell would refuse it, or read on to a later line; a plain split
        # with the quote characters removed still lets each spelling be judged, erring toward a deny.
        toks = [t.replace("'", "").replace('"', "") for t in cmd.replace("\n", " ; ").split()]
    # A comment starts only at the beginning of a word, and runs to the end of the line.
    out, skipping = [], False
    for t in toks:
        if skipping:
            if t == "\n":
                skipping = False
                out.append(t)
            continue
        if t.startswith("#"):
            skipping = True
            continue
        out.append(t)
    return out


def is_sep(t: str) -> bool:
    return bool(t) and set(t) <= SEPARATORS


def pipelines(toks: list[str]) -> list[list[list[str]]]:
    """[[segment, segment, …] per pipeline]: `|` joins segments, anything else ends the pipeline."""
    out, pipe, cur = [], [], []
    for t in toks:
        if is_sep(t):
            if cur:
                pipe.append(cur)
            cur = []
            if t not in ("|", "|&"):
                if pipe:
                    out.append(pipe)
                pipe = []
        else:
            cur.append(t)
    if cur:
        pipe.append(cur)
    if pipe:
        out.append(pipe)
    return out


def strip_redirects(seg: list[str]) -> tuple[list[str], list[str]]:
    """(words, here-strings)."""
    out, here, skip = [], [], None
    for t in seg:
        if skip is not None:
            if skip == "<<<":
                here.append(t)
            skip = None
            continue
        if REDIRECT.match(t):
            skip = t
            continue
        out.append(t)
    return out, here


def word(t: str) -> str:
    return os.path.basename(t.lstrip("\\")).lower()


def short_cluster(t: str) -> str:
    """The letters of a short-option cluster, '' for anything else."""
    return t[1:] if re.match(r"^-[A-Za-z]+$", t) else ""


def long_is(a: str, full: str, minimum: int = 4) -> bool:
    """GNU getopt and git accept an unambiguous prefix: --rec, --forc, --har."""
    a = a.split("=", 1)[0].lower()
    return len(a) >= minimum and full.startswith(a)


def judge_rm(args: list[str]) -> bool:
    recursive = force = False
    for a in args:
        if a == "--":
            break
        if a.startswith("--"):
            recursive |= long_is(a, "--recursive")
            force |= long_is(a, "--force")
        else:
            c = short_cluster(a)
            recursive |= "r" in c or "R" in c
            force |= "f" in c
    return recursive and force


def judge_git(args: list[str]) -> str | None:
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"):
            i += 2
        else:
            i += 1
    if i >= len(args):
        return None
    sub, rest = args[i].lower(), args[i + 1:]
    if sub == "push":
        for a in rest:
            if a.startswith("--") and (long_is(a, "--force", 5) or long_is(a, "--force-with-lease", 9)
                                       or long_is(a, "--force-if-includes", 9)):
                return "git-push-force"
            if "f" in short_cluster(a):
                return "git-push-force"
            if a.startswith("+") and len(a) > 1:
                return "git-push-force"
        return None
    if sub == "reset" and any(a.startswith("--") and long_is(a, "--hard", 4) for a in rest):
        return "git-reset-hard"
    if sub == "clean":
        dry = any(a in ("-n", "--dry-run") or "n" in short_cluster(a) for a in rest)
        for a in rest:
            if not dry and ((a.startswith("--") and long_is(a, "--force", 5)) or "f" in short_cluster(a)):
                return "git-clean-force"
    return None


def judge_find(args: list[str], depth: int) -> str | None:
    for i, a in enumerate(args):
        if a == "-delete":
            return "find-delete"
        if a in ("-exec", "-execdir", "-ok", "-okdir") and i + 1 < len(args):
            inner = []
            for t in args[i + 1:]:
                if t in (";", "+", "\\;"):
                    break
                inner.append(t)
            if inner and word(inner[0]) == "rm":
                return "find-delete"
            found = judge_words(inner, depth + 1) if depth < MAX_DEPTH else None
            if found:
                return found
    return None


def shell_body(args: list[str]) -> str | None:
    """The -c program of a shell invocation, '' for a shell reading stdin, None for a script file."""
    for i, a in enumerate(args):
        if a == "-c" or (short_cluster(a) and "c" in short_cluster(a)):
            return args[i + 1] if i + 1 < len(args) else ""
        if not a.startswith("-"):
            return None
    return ""


def judge_words(seg: list[str], depth: int, stdin_text: str = "") -> str | None:
    seg, here = strip_redirects(seg)
    while seg:
        if ASSIGN.match(seg[0]) or word(seg[0]) in KEYWORDS:
            seg = seg[1:]
            continue
        w = word(seg[0])
        if w in ESCALATE:
            return "sudo"
        if w in WRAPPERS:
            takes = WRAPPERS[w]
            rest = seg[1:]
            if w == "command" and rest and rest[0] in ("-v", "-V"):
                return None
            while rest and (rest[0].startswith("-") or (w == "env" and ASSIGN.match(rest[0]))):
                opt = rest[0]
                rest = rest[2:] if opt in takes else rest[1:]
            if w == "timeout" and rest:
                rest = rest[1:]                       # the duration
            if w == "nice" and rest and re.match(r"^-?[0-9]+$", rest[0]):
                rest = rest[1:]
            seg = rest
            continue
        break
    if not seg:
        return None
    w, args = word(seg[0]), seg[1:]
    if w == "rm":
        return "rm-recursive-force" if judge_rm(args) else None
    if w == "git":
        return judge_git(args)
    if w == "find":
        return judge_find(args, depth)
    if (w in SHELLS or w == "eval") and depth < MAX_DEPTH:
        body = " ".join(args) if w == "eval" else shell_body(args)
        texts = [t for t in (body, stdin_text, *here) if t]
        for t in texts:
            found = classify(t, depth + 1)
            if found:
                return found
    return None


def heredocs(cmd: str) -> tuple[str, list[tuple[int, str]]]:
    """The command with heredoc bodies removed, and (line index, body) for each.

    `<<` counts only outside quotes and comments, and `<<<` is a here-string, not a heredoc — so
    `echo '<<EOF'` cannot swallow the line after it.
    """
    lines = cmd.split("\n")
    kept, docs, i = [], [], 0
    while i < len(lines):
        line = lines[i]
        idx = len(kept)
        kept.append(line)
        i += 1
        for delim in _heredoc_delims(line):
            body = []
            while i < len(lines) and lines[i].strip() != delim:
                body.append(lines[i])
                i += 1
            i += 1
            docs.append((idx, "\n".join(body)))
    return "\n".join(kept), docs


def _heredoc_delims(line: str) -> list[str]:
    out, q, j = [], None, 0
    while j < len(line):
        c = line[j]
        if q:
            if c == q:
                q = None
            elif c == "\\" and q == '"':
                j += 1
        elif c in "'\"":
            q = c
        elif c == "\\":
            j += 1
        elif c == "#" and (j == 0 or line[j - 1] in " \t;&|("):
            break
        elif line.startswith("<<", j) and not line.startswith("<<<", j):
            m = re.match(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line[j:])
            if m:
                out.append(m.group(2))
                j += m.end()
                continue
        j += 1
    return out


def classify(cmd: str, depth: int = 0) -> str | None:
    cmd, docs = heredocs(normalise(cmd))
    lines = cmd.split("\n")
    # A heredoc body is data unless its line hands it to a shell — anywhere on the line, so
    # `cat <<EOF | bash` counts as well as `bash <<EOF`.
    stdin_for_line = {}
    for idx, body in docs:
        stdin_for_line.setdefault(idx, []).append(body)
    for idx, line in enumerate(lines):
        bodies = stdin_for_line.get(idx, [])
        for pipe in pipelines(tokens(line)):
            fed = "\n".join(bodies)
            for n, seg in enumerate(pipe):
                # Text piped into a shell is a program: everything the earlier stages name.
                upstream = " ".join(t for s in pipe[:n] for t in strip_redirects(s)[0][1:])
                found = judge_words(seg, depth, "\n".join(x for x in (fed, upstream) if x))
                if found:
                    return found
    if depth < MAX_DEPTH:
        for m in SUBST.finditer(cmd):
            body = m.group(1) if m.group(1) is not None else m.group(2)
            found = classify(body, depth + 1)
            if found:
                return found
    return None


# Kept for sensitive_paths.py, which reads heredoc bodies the same way.
def split_heredocs(cmd: str) -> tuple[str, list[tuple[str, str]]]:
    kept, docs = heredocs(cmd)
    lines = kept.split("\n")
    return kept, [(lines[i], body) for i, body in docs]


def feeds_shell(line: str) -> bool:
    for pipe in pipelines(tokens(line)):
        for seg in pipe:
            words, _ = strip_redirects(seg)
            while words and (ASSIGN.match(words[0]) or word(words[0]) in WRAPPERS
                             or word(words[0]) in ESCALATE or word(words[0]) in KEYWORDS):
                words = words[1:]
            if words and (word(words[0]) in SHELLS or word(words[0]) == "eval"):
                return True
    return False


def main() -> int:
    print(classify(os.environ.get("CMD_TEXT", "")) or "none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
