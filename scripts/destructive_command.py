#!/usr/bin/env python3
"""Classify a shell command against the destructive deny list (spec 083, R9, F038).

Called by scripts/destructive-command-guard-hook.sh with the command in $CMD_TEXT. Prints one line:

    none              nothing on the list
    <form>            the first destructive form found: rm-recursive-force, sudo, git-push-force,
                      git-push-delete, git-push-mirror, git-reset-hard, git-clean-force, find-delete

WHY A TOKENISER. `permissions.deny` in .claude/settings.json matches by prefix: `Bash(rm -rf *)` does
not match `rm -r -f x`, `/bin/rm -rf x`, `command rm -rf x` or `git -C . push -f`, and under
bypassPermissions + `allow: Bash` every one of those ran (H1 adversarial #3). This reads the command
the way a shell would split it: quotes honoured, operators and keywords separating commands, the
command word resolved through the wrappers that only run another command, case folded (macOS
filesystems find /bin/RM).

WHAT IT DOES NOT DO (the declared bound). It recognises spellings; it does not evaluate. A variable
(`$RM -rf x`), an alias, a function, brace expansion (`{rm,-rf,x}`), a script that deletes,
`eval "$cmd"`, `python -c "shutil.rmtree(...)"` and `git -c alias.x='!rm -rf .' x` all pass. So does
every destructive command the deny list never named (dd, mkfs, git branch -D). A
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_glob import ANSI_C, ansi_c_text as _ansi_c   # one copy of bash's $'…' rule (spec 090)

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


def normalise(cmd: str) -> str:
    # A backslash-newline is removed by the shell before it splits words: `rm -r \<nl>-f x` is one
    # command. $'…' (ANSI-C quoting) is decoded the way bash decodes it (\xHH, \NNN, \uHHHH, \n …),
    # then read as a single-quoted word: `git push origin $'\x3amain'` deletes main (spec 090,
    # adversarial review #6).
    cmd = cmd.replace("\\\r\n", "").replace("\\\n", "")
    return ANSI_C.sub(lambda m: "'" + _ansi_c(m.group(1)).replace("'", "") + "'", cmd)



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


# Spec 090 (R5, F084, developer O3): a push that deletes or mirrors a remote ref, set from the command
# line or through the config git reads for the next push. `remote.<x>.mirror` makes every plain `git
# push` a mirror; `remote.<x>.push` with `:` or `+` makes it a deletion or a force.
_REMOTE_PUSH_KEY = re.compile(r"^remote\..+\.(mirror|push)$", re.I)


def _push_config_form(key: str, value: str | None) -> str | None:
    m = _REMOTE_PUSH_KEY.match(key)
    if not m:
        return None
    if m.group(1).lower() == "mirror":
        return "git-push-mirror"
    v = (value or "").strip()
    if v.startswith("+"):
        return "git-push-force"
    if v.startswith(":") and len(v) > 1:
        return "git-push-delete"
    return None


def judge_push(rest: list[str]) -> str | None:
    for a in rest:
        if a == "--":
            break
        if a.startswith("--"):
            if long_is(a, "--force", 5) or long_is(a, "--force-with-lease", 9) or long_is(a, "--force-if-includes", 9):
                return "git-push-force"
            if long_is(a, "--mirror", 3):
                return "git-push-mirror"
            if long_is(a, "--delete", 4) or long_is(a, "--prune", 4):
                return "git-push-delete"
            continue
        c = short_cluster(a)
        if "f" in c:
            return "git-push-force"
        if "d" in c:
            return "git-push-delete"
        if a.startswith("+") and len(a) > 1:
            return "git-push-force"
        # `:main` deletes main on the remote; a bare `:` pushes the matching branches.
        if a.startswith(":") and len(a) > 1:
            return "git-push-delete"
    # Everything after `--` is a refspec.
    if "--" in rest:
        for a in rest[rest.index("--") + 1:]:
            if a.startswith("+") and len(a) > 1:
                return "git-push-force"
            if a.startswith(":") and len(a) > 1:
                return "git-push-delete"
    return None


def judge_git(args: list[str]) -> str | None:
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] == "-c" and i + 1 < len(args):
            key, _, value = args[i + 1].partition("=")
            form = _push_config_form(key, value)
            if form:
                return form
        # --config-env=<key>=<ENVVAR>: the value is unknown here, so the key alone decides; a `push`
        # key read from the environment is judged as a deletion (review #5).
        if args[i].startswith("--config-env"):
            spec = args[i].split("=", 1)[1] if "=" in args[i] else (args[i + 1] if i + 1 < len(args) else "")
            key = spec.split("=", 1)[0]
            form = _push_config_form(key, ":x") if _REMOTE_PUSH_KEY.match(key) else None
            if form:
                return form
            if "=" not in args[i]:
                i += 2
                continue
        if args[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"):
            i += 2
        else:
            i += 1
    if i >= len(args):
        return None
    sub, rest = args[i].lower(), args[i + 1:]
    if sub in ("push", "send-pack"):
        return judge_push(rest)
    # `git remote add --mirror=push bak <url>` sets remote.bak.mirror (review #5).
    if sub == "remote" and any(a == "--mirror" or a.startswith("--mirror=") for a in rest):
        return "git-push-mirror"
    if sub == "config":
        # Reading or removing the key changes nothing a push does.
        if any(a in ("--get", "--get-all", "--get-regexp", "--list", "-l", "--unset", "--unset-all")
               for a in rest):
            return None
        # Options that take a value (`--type bool`, `-f <file>`) would read their value as the key.
        words, j = [], 0
        while j < len(rest):
            a = rest[j]
            if a in ("--type", "-t", "-f", "--file", "--blob", "--default", "--comment", "--value"):
                j += 2
                continue
            if not a.startswith("-"):
                words.append(a)
            j += 1
        if words and words[0].lower() in ("get", "list", "unset", "rename-section", "remove-section", "edit"):
            return None
        if words and words[0].lower() == "set":
            words = words[1:]
        if words:
            form = _push_config_form(words[0], words[1] if len(words) > 1 else "")
            if form:
                return form
        return None
    if sub == "reset" and any(a.startswith("--") and long_is(a, "--hard", 4) for a in rest):
        return "git-reset-hard"
    if sub == "clean":
        dry = any(a in ("-n", "--dry-run") or "n" in short_cluster(a) for a in rest)
        for a in rest:
            if not dry and ((a.startswith("--") and long_is(a, "--force", 5)) or "f" in short_cluster(a)):
                return "git-clean-force"
    return None


def judge_find(args: list[str], depth: int, judge=None) -> str | None:
    for i, a in enumerate(args):
        if a == "-delete" and judge is None:
            return "find-delete"
        if a in ("-exec", "-execdir", "-ok", "-okdir") and i + 1 < len(args):
            inner = []
            for t in args[i + 1:]:
                if t in (";", "+", "\\;"):
                    break
                inner.append(t)
            if inner and word(inner[0]) == "rm" and judge is None:
                return "find-delete"
            found = judge_words(inner, depth + 1, "", judge) if depth < MAX_DEPTH else None
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


# 091 adversarial B1: GIT_CONFIG_COUNT/KEY_n/VALUE_n and GIT_CONFIG_PARAMETERS are `git -c` by environment.
GIT_CONFIG_ENV = re.compile(r"^GIT_CONFIG_(COUNT|KEY_\d+|VALUE_\d+|PARAMETERS)=", re.I)


def judge_words(seg: list[str], depth: int, stdin_text: str = "", judge=None) -> str | None:
    seg, here = strip_redirects(seg)
    env_config = False
    while seg:
        if ASSIGN.match(seg[0]) or word(seg[0]) in KEYWORDS:
            env_config = env_config or bool(GIT_CONFIG_ENV.match(seg[0]))
            seg = seg[1:]
            continue
        w = word(seg[0])
        if w in ESCALATE:
            if judge is None:
                return "sudo"
            seg = seg[1:]          # another guard's question (spec 091 R2) looks through sudo
            continue
        if w in WRAPPERS:
            takes = WRAPPERS[w]
            rest = seg[1:]
            if w == "command" and rest and rest[0] in ("-v", "-V"):
                return None
            while rest and (rest[0].startswith("-") or (w == "env" and ASSIGN.match(rest[0]))):
                opt = rest[0]
                env_config = env_config or bool(GIT_CONFIG_ENV.match(opt))
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
    # Spec 091 R2: `judge` is another guard's question about git, asked through the same word rules;
    # with one, rm and find are not this classifier's business.
    if judge is not None and (w == "git" and env_config or
                              w == "export" and any(GIT_CONFIG_ENV.match(a) for a in args)):
        return "git-config-trust"                      # an exported one reaches every git after it
    if w == "git":
        return (judge or judge_git)(args)
    if judge is None and w == "rm":
        return "rm-recursive-force" if judge_rm(args) else None
    if w == "find":
        return judge_find(args, depth, judge)                 # 091 adversarial B5: -exec git … too
    # 091 adversarial B4: git-core's dashed binaries (git-update-ref, git-remote) are the same command.
    if judge is not None and w.startswith("git-") and len(w) > 4:
        return judge([w[4:]] + args)
    if (w in SHELLS or w == "eval") and depth < MAX_DEPTH:
        body = " ".join(args) if w == "eval" else shell_body(args)
        texts = [t for t in (body, stdin_text, *here) if t]
        for t in texts:
            found = classify(t, depth + 1, judge)
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


def classify(cmd: str, depth: int = 0, judge=None) -> str | None:
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
                found = judge_words(seg, depth, "\n".join(x for x in (fed, upstream) if x), judge)
                if found:
                    return found
    if depth < MAX_DEPTH:
        for m in SUBST.finditer(cmd):
            body = m.group(1) if m.group(1) is not None else m.group(2)
            found = classify(body, depth + 1, judge)
            if found:
                return found
    return None


# ------------------------------------------------------------------ spec 091 R2: trust anchors in git
# trust-anchor-guard asks this through classify(cmd, judge=judge_git_trust). The template is now known
# by its root commit (template-identity.sh), so these denies are defence in depth: they keep origin, the
# upstream a Confirmed line is checked against (R9), and remote-tracking refs the developer's to move.
_TRUST_KEY = re.compile(r"^(remote\.|url\.|branch\.|include|alias\.)", re.I)
_CONFIG_READS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l",
                 "--show-origin", "--show-scope", "--name-only"}
_CONFIG_VALUED = {"--type", "-t", "-f", "--file", "--blob", "--default", "--comment", "--value"}
_CONFIG_WRITES = {"--unset", "--unset-all", "--add", "--replace-all", "-e", "--edit",
                  "--rename-section", "--remove-section"}


def _refspec_writes_tracking(spec: str) -> bool:
    if ":" not in spec:
        return False
    dst = spec.lstrip("+").split(":", 1)[1]
    # 091 adversarial B2: a pattern destination can land on refs/remotes/ under any spelling
    # (refs/rem*, refs/*/origin/main), so any `*` or any `remotes` in it counts.
    return "*" in dst or "remotes" in dst.lower()


# 091 adversarial B3: plumbing that writes refs without being fetch, push or update-ref.
_REF_PLUMBING = {"fast-import", "fetch-pack", "receive-pack"}
# 091 adversarial B6: global options whose value is the next word.
_GIT_VALUED = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env",
               "--attr-source", "--super-prefix", "--list-cmds"}


def judge_git_trust(args: list[str]) -> str | None:
    i = 0
    while i < len(args) and args[i].startswith("-"):
        # 091 adversarial B1: a one-shot -c or --config-env on a trust key redirects what this very
        # command fetches into refs/remotes (`git -c remote.origin.url=/tmp/forge fetch origin`).
        if args[i] in ("-c", "--config-env") and i + 1 < len(args) and _TRUST_KEY.match(args[i + 1]):
            return "git-config-trust"
        if args[i].startswith("--config-env=") and _TRUST_KEY.match(args[i].split("=", 1)[1]):
            return "git-config-trust"
        i += 2 if args[i] in _GIT_VALUED else 1
    if i >= len(args):
        return None
    sub, rest = args[i].lower(), args[i + 1:]
    if sub in _REF_PLUMBING:
        return "git-ref-write"
    if sub == "remote":
        verbs = [a.lower() for a in rest if not a.startswith("-")]
        if verbs and verbs[0] in ("add", "set-url", "rename", "remove", "rm", "set-head", "set-branches"):
            return "git-remote-write"
        return None
    if sub in ("update-ref", "symbolic-ref"):
        if sub == "symbolic-ref" and len([a for a in rest if not a.startswith("-")]) < 2:
            return None                                   # reading HEAD's target
        return "git-ref-write"
    if sub in ("fetch", "push", "pull", "send-pack"):
        if any(_refspec_writes_tracking(a) for a in rest if not a.startswith("-")):
            return "git-ref-write"
        if any(a.startswith("--refmap") for a in rest):
            return "git-ref-write"
        return None
    if sub == "config":
        if any(a in _CONFIG_READS for a in rest):
            return None
        words, j = [], 0
        while j < len(rest):
            if rest[j] in _CONFIG_VALUED:
                j += 2
                continue
            if not rest[j].startswith("-"):
                words.append(rest[j])
            j += 1
        verb = words[0].lower() if words else ""
        if verb in ("get", "list"):
            return None
        if verb == "edit" or any(a in ("-e", "--edit") for a in rest):
            return "git-config-trust"                     # an editor can change any key
        if verb in ("set", "unset", "rename-section", "remove-section"):
            words = words[1:]
        elif len(words) == 1 and not any(a in _CONFIG_WRITES for a in rest):
            return None                                   # `git config remote.origin.url` reads it
        return "git-config-trust" if words and _TRUST_KEY.match(words[0]) else None
    return None


TRUST_VERDICTS = ("git-remote-write", "git-ref-write", "git-config-trust")


def classify_trust(cmd: str) -> str | None:
    found = classify(cmd, 0, judge_git_trust)
    return found if found in TRUST_VERDICTS else None


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
