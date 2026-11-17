#!/bin/bash
# PreToolUse guard: state that stands for a human decision stays out of the agent's tools (spec 088 R3).
#
# WHY THIS EXISTS
# ---------------
# Two gates promise that a person decided something, and both kept that decision in a place the gated
# agent could write (H3 adversarial #3 and #7, F091 and F094):
#
#   * the 082 nightly runs a suite, mutation runner or ratchet only if its hash is in
#     .git/claude-trusted-commands. `project-maintenance.sh --trust --yes`, MAINTENANCE_TTY=<a file
#     holding yes>, or a plain write to the store put any command there.
#   * a full or hardened spec unlocks production code once acceptance.md carries a Confirmed line with
#     the cases' digest. The line is markdown, the digest is printed by --digest, and nothing tied the
#     quoted answer to the developer.
#
# Spec 088 moved the second decision onto .git/claude-developer-words, which only the PostToolUse hook
# on AskUserQuestion writes (scripts/developer-answers-hook.sh). This guard denies the agent's tools:
#
#   (a) any file_path with a `.git` component: the two stores, the rest of the git dir, and a planted
#       `.git` file or directory (F090's own move). A symlink is judged where it lands, at any
#       component of the path (spec 098 R1, F139), and a git dir kept outside the tree that the
#       project's .git file names counts as the git dir.
#   (b) an Edit/MultiEdit/Write that adds, removes or changes a Confirmed line in an acceptance.md
#       (the edit is applied to the current bytes first, so a line spliced across old_string is seen),
#       and a payload naming such a file, or a glob that can match one, with no bytes at all: that is
#       how bash-write-guard delegates a shell write (`sed -i`, `>`, `tee`)
#   (c) a Bash command whose text, with $'…' decoded and ' " \ removed, names either store
#       (claude-trusted…, claude-developer…, …trusted-commands, …developer-words), uses a glob or brace on
#       a path through .git/, names MAINTENANCE_TTY, CLAUDECODE, .git/worktrees or `Confirmed:**`, or
#       carries the option --trust at all (a copied or glob-named project-maintenance.sh still parses it)
#   (e) spec 091 R2: a Bash git command that rewrites a remote, an upstream or a remote-tracking ref
#       (destructive_command.classify_trust); R7: any write to .claude/workload-placement.tsv
#   (f) spec 095: a persistent `git config` write to a key git runs as a program (core.hooksPath,
#       core.fsmonitor, filter.*, credential.*, …, R10); an mcp__ tool whose strings name a store, a
#       cases file or the placement table, or carry a command (R3). --trust counts as a shell word, not
#       as prose inside a quoted argument (R8).
#   (g) spec 098: chmod, chown, chgrp, chflags, chattr, setfacl, xattr, mv or rename on a path with a
#       .git component. None writes bytes, so bash-write-guard never delegated them, and each makes git
#       fail at once, which the root walk reads as an answer.
#   (h) spec 105: rm, rmdir, unlink, shred, truncate, touch, mkdir, ln, install, cp and dd join (g),
#       judged per simple command on the destination (R1); a line that writes and names
#       claude-hook-notices or substitutes git rev-parse --git-dir|--git-common-dir|--absolute-git-dir|
#       --git-path (R2); any write into a directory on PATH, by path or by a shell writer (R4, developer
#       O2: the guards run git, perl, timeout, python3 and jq by PATH); an Edit, MultiEdit or Write that
#       leaves a scripts/*.sh or *.py unparseable while it parses now (R6).
#   (d) an AskUserQuestion whose tool_input already carries `answers`. An honest call never does at
#       PreToolUse (measured 2026-10-01); the answers arrive after the developer picks them.
#
# THE BOUND. Command text only, like bash-write-guard: a script file the agent writes and then runs, or a
# name assembled at runtime ($x, $(…), printf into a variable), is not seen here. project-maintenance.sh
# still refuses --yes under CLAUDECODE and any prompt input that is not a terminal (R2), and the
# spec-interview gate re-checks an uncommitted Confirmed line against the answer store (R5), so those
# routes need more than one hidden step. The developer's own routes are untouched: --trust in their own
# terminal, and answering the AskUserQuestion. There is no override variable; these stores are
# human-only by definition. To read one, use the Read tool.
#
# FAILS CLOSED on a payload it cannot read when the raw text holds a trigger word. Never echoes the
# command (bash-write-guard FR-015: a command can carry a credential). Exit: always 0.

set -u

INPUT=$(cat 2>/dev/null || true)   # mutant-equivalent: no set -e and the assignment's status is never read; `cat && true` captures the same bytes (none on a closed stdin) and the next line decides on the text alone
[ -z "$INPUT" ] && exit 0

# Cheapest exit first: no trigger word in the payload, nothing to decide. A long payload goes straight
# to the parser (bash 3.2 pattern substitution is slow on tens of KB, row 047).
#
# Only the tool call itself is matched, from "tool_input" on: the harness fields before it
# (transcript_path, scratchpad_dir=/…/claude-501/…) named a trigger word on every call, which sent
# every call to python and turned one crash into a lockout of every tool (found 2026-10-01).
TI=${INPUT#*\"tool_input\"}
HIT=0
[[ $INPUT =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"AskUserQuestion\" ]] && HIT=1
[[ $INPUT =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"mcp__ ]] && HIT=1   # spec 095 R3: any field may name a store
if [ "${#TI}" -gt 4096 ]; then
  HIT=1
else
  N=${TI//[\"\'\\]/}
  shopt -s nocasematch
  case "$N" in
    *claude-*|*trusted-comm*|*developer-word*|*mod-accepted*|*maintenance_tty*|*claudecode*|*confirmed:*|*acceptance*) HIT=1 ;;
    # .git as a path component, not .gitignore or .github; a glob for an acceptance.md is caught below.
    *--trust*|*'.git/'*|*'.git'|*'.git'[!a-zA-Z0-9_-]*|*separate-git*) HIT=1 ;;
  esac
  # Spec 091 R2/R7: git commands that move origin, an upstream or a remote-tracking ref, and the
  # placement table. `git` plus one of the words, so a plain `cat tsconfig.json` stays cheap.
  case "$N" in
    *workload-placement*) HIT=1 ;;
    *git*remote*|*git*config*|*git*update-ref*|*git*symbolic-ref*|*refs/remotes*|*insteadof*|*git*:remotes/*) HIT=1 ;;
    *git*:refs/*|*git*:\**|*git*refmap*) HIT=1 ;;    # a refspec whose destination could be a tracking ref
    *git_config_*|*fast-import*|*fetch-pack*|*receive-pack*|*send-pack*|*git-remote*|*git-config*) HIT=1 ;;
  esac
  case "$TI" in *"\$'"*) HIT=1 ;; esac        # ANSI-C quoting: the stripped text no longer shows it
  # Spec 105 R2 (F177): git's own spelling of the git dir. R4 (F176): a PATH directory, which names a
  # bin dir, a PATH entry, or the home directory a ~ or $HOME expands to.
  case "$N" in
    *--git-dir*|*--git-common-dir*|*--absolute-git-dir*|*--git-path*) HIT=1 ;;
    */bin/*|*/bin|*/sbin/*|*'~/'*|*'$HOME'*|*'${HOME}'*) HIT=1 ;;   # path-shaped only: python costs ~50 ms
  esac
  # A glob that can spell .git (.g[i]t, .gi?, .*): the parser matches it against the name (threat model #2).
  case "$N" in *.[g*?[]*) case "$N" in *[*?[]*) HIT=1 ;; esac ;; esac
  if [ "$HIT" -eq 0 ]; then
    _ifs=$IFS; IFS=:
    for _pe in $PATH; do
      [ -n "$_pe" ] && case "$N" in *"$_pe"*) HIT=1; break ;; esac
    done
    IFS=$_ifs
  fi
  shopt -u nocasematch
  # A file_path that is a symlink may land on a store under an innocent name, and a glob (a shell write
  # bash-write-guard delegates unexpanded) may match an acceptance.md under any spelling.
  # notebook_path too: NotebookEdit writes as much as Write does (098 review R1-2).
  if [ "$HIT" -eq 0 ] && [[ $TI =~ \"(file_path|notebook_path)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    _fp="${BASH_REMATCH[2]}"
    case "$_fp" in *[*?{[]*) HIT=1 ;; esac
    # Spec 105 R6 (F174): a shell or python script under scripts/ is parse-checked before it lands.
    # Case-folded, as the parser judges it (SCRIPTS/x.SH on a folding file system; adversarial review #6).
    shopt -s nocasematch
    case "$_fp" in scripts/*.sh|scripts/*.py|*/scripts/*.sh|*/scripts/*.py) HIT=1 ;; esac
    shopt -u nocasematch
    # Spec 105 R4 (F176): a write into a directory on PATH (the parser compares resolved paths).
    _fd=${_fp%/*}
    case "${_fd##*/}" in bin|sbin) HIT=1 ;; esac
    case ":$PATH:" in *":$_fd:"*|*":$_fd/:"*) HIT=1 ;; esac
    # Spec 098 R1 (F139): a link at ANY component, not only the last: with gd -> .git in the tree,
    # gd/info/exclude names no trigger word. The shared ancestor walk (spec 090 R2(b)) reads the
    # payload's cwd for a relative path, so it gets the whole payload. Not loadable: look.
    if . "${BASH_SOURCE[0]%/*}/guard-precheck.sh" 2>/dev/null; then
      guard_precheck_link "$INPUT" && HIT=1
    else
      HIT=1
    fi
    # Spec 098 TB1: a .git FILE at the project root may name a git dir kept elsewhere, which has no
    # .git component. A text prefix test missed $P/../gd/hooks/x and gd//hooks (098 review R1-1), so
    # such a project sends every path to the parser, which compares resolved paths.
    [ -f "${CLAUDE_PROJECT_DIR:-}/.git" ] && HIT=1
    # A hard link to an acceptance.md under another name (/security-review, spec 088): -ef compares
    # device and inode, as a builtin.
    if [ "$HIT" -eq 0 ] && [ -f "$_fp" ]; then   # mutant-equivalent: with HIT=1 the loop can only set HIT=1 again; -f only skips the glob for a path that cannot -ef a regular file
      # acceptance_cases.ACCEPTANCE_GLOBS, spelled for bash (the verdict below imports the list itself).
      for _a in "${CLAUDE_PROJECT_DIR:-.}"/specs/*/acceptance.md "${CLAUDE_PROJECT_DIR:-.}"/.specify/specs/*/acceptance.md \
                "${CLAUDE_PROJECT_DIR:-.}"/*/specs/*/acceptance.md; do
        [ -f "$_a" ] && [ "$_fp" -ef "$_a" ] && { HIT=1; break; }
      done
    fi
  fi
fi
[ "$HIT" -eq 1 ] || exit 0

HOOK_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! . "$HOOK_DIR/guard-lib.sh" 2>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED — trust-anchor-guard cannot load scripts/guard-lib.sh, and this call mentions a trust store, a Confirmed line or an answered question. Re-run the template sync (it is in CORE_SCRIPTS)."}}'
  exit 0
fi

# The program is passed with -c and the payload on stdin: an environment string is capped at 128 KB on
# Linux, and a large Write would have failed to start the parser and been denied (adversarial #8).
PROG=$(cat <<'PY'
import fnmatch, glob, json, os, re, shlex, sys

sys.path.insert(0, sys.argv[1])
from acceptance_cases import ACCEPTANCE_GLOBS, CONFIRMED_PREFIX as PREFIX   # the parser's own rules
from shell_glob import ANSI_C, BRACE_CAP, TooMany, ansi_c, brace_alts      # bash's word rules (spec 090)

STORES = ("claude-trusted-commands", "claude-developer-words", "claude-mod-accepted")   # 105 R8: the mod pin
GLOBCH = re.compile(r"[*?\[{]")

try:
    d = json.loads(sys.stdin.read())
    if not isinstance(d, dict):
        raise ValueError
except Exception:
    print("unparseable"); sys.exit(0)

tool = d.get("tool_name") or ""
ti = d.get("tool_input") or {}
if not isinstance(ti, dict):
    print("unparseable"); sys.exit(0)
cwd = d.get("cwd") or os.getcwd()

def parts_of(p):
    return [x for x in p.replace("\\", "/").split("/") if x]

def path_hits(p, pred):
    """pred(lower-cased components) for the path as spelled or as resolved."""
    return any(pred([x.lower() for x in parts_of(q)]) for q in (p, os.path.realpath(p)))

def _project_git_dirs():
    """Spec 098 TB1: a .git FILE at the project root names its git dir with a gitdir: line. A git dir
    kept elsewhere (`git init --separate-git-dir`) has no .git component for touches_git to see, and a
    linked worktree's commondir names the shared one."""
    root = os.environ.get("CLAUDE_PROJECT_DIR") or ""
    g = os.path.join(root, ".git")
    if not root or not os.path.isfile(g):
        return []
    try:
        with open(g, encoding="utf-8", errors="replace") as fh:
            line = fh.readline().strip()
    except OSError:
        return []
    if not line.startswith("gitdir: "):
        return []
    t = line[len("gitdir: "):]
    t = os.path.realpath(t if os.path.isabs(t) else os.path.join(root, t))
    out = [t]
    try:
        with open(os.path.join(t, "commondir"), encoding="utf-8", errors="replace") as fh:
            c = fh.readline().strip()
        out.append(os.path.realpath(c if os.path.isabs(c) else os.path.join(t, c)))
    except OSError:
        pass
    return [d.lower() for d in out]

_GIT_DIRS = []

def touches_git(p):
    if path_hits(p, lambda ps: ".git" in ps or (bool(ps) and ps[-1] in STORES)):
        return True
    if not _GIT_DIRS:
        _GIT_DIRS.append(_project_git_dirs())             # read once, and only when a path is judged
    rp = os.path.realpath(p if os.path.isabs(p) else os.path.join(cwd, p)).lower()
    return any(rp == d or rp.startswith(d + os.sep) for d in _GIT_DIRS[0])

# Spec 090 R8(b) (F112): a glob is judged by what bash expands it to, not by whether its last
# component could spell acceptance.md. `{/* c */}` in a heredoc fixture ended in `*`, which "could",
# and every such command was denied. Braces expand the way bash expands them (a comma or a `..`
# sequence; `{/*` is literal), each glob component is matched case-insensitively against what is on
# disk (macOS opens ACCEPT*.MD), and a bracket expression fnmatch cannot read ([[=c=]], [[:alpha:]])
# is widened to `*`, which can only add matches (threat model #5).
def widen(comp):
    return re.sub(r"\[.*?\]+", "*", comp) if "[" in comp else comp

def expand(p):
    """Existing paths a glob p names, components matched case-insensitively (bash on a folding FS)."""
    cur = ["/"] if p.startswith("/") else [cwd]
    for comp in parts_of(p):
        nxt = []
        for d in cur:
            if not GLOBCH.search(comp):
                nxt.append(os.path.join(d, comp))
                continue
            pat = widen(comp).lower()
            try:
                names = os.listdir(d)
            except OSError:
                continue
            for n in names:
                if n.startswith(".") and not comp.startswith("."):
                    continue
                if fnmatch.fnmatchcase(n.lower(), pat):
                    nxt.append(os.path.join(d, n))
        if len(nxt) > 4 * BRACE_CAP:
            raise TooMany
        cur = nxt
        if not cur:
            return []
    return [c for c in cur if os.path.lexists(c)]

def same_as_acceptance(q):
    if os.path.basename(q).lower() == "acceptance.md" or os.path.basename(os.path.realpath(q)).lower() == "acceptance.md":
        return True
    try:
        if os.path.isfile(q) and os.stat(q).st_nlink > 1:
            root = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
            for pat in ACCEPTANCE_GLOBS:
                for a in glob.glob(os.path.join(root, pat)):
                    if os.path.samefile(q, a):
                        return True
    except OSError:
        pass
    return False

def is_acceptance(p):
    if GLOBCH.search(p):
        try:
            alts = brace_alts(p)
        except TooMany:
            return True
        for alt in alts:
            if not GLOBCH.search(alt):
                if is_acceptance(alt):
                    return True
                continue
            # A literal last component spelling acceptance.md names one, existing or about to.
            last = parts_of(alt)[-1] if parts_of(alt) else ""
            if not GLOBCH.search(last) and last.lower() == "acceptance.md":
                return True
            try:
                hits = expand(alt)
            except TooMany:
                return True
            if any(same_as_acceptance(m) for m in hits):
                return True
        return False
    for q in (p, os.path.realpath(p)):
        ps = parts_of(q)
        if ps and ps[-1].lower() == "acceptance.md":
            return True
    # A hard link is the same file under another name: judged by inode (/security-review, spec 088).
    try:
        if os.path.isfile(p) and os.stat(p).st_nlink > 1:
            root = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
            for pat in ACCEPTANCE_GLOBS:
                for a in glob.glob(os.path.join(root, pat)):
                    if os.path.samefile(p, a):
                        return True
    except OSError:
        pass
    return False

def conf_lines(text):
    return sorted(l.lstrip("\ufeff").rstrip() for l in text.splitlines() if l.lstrip("\ufeff").startswith(PREFIX))

def apply(text, e):
    old, new = e.get("old_string"), e.get("new_string")
    if not isinstance(old, str) or not isinstance(new, str):
        raise ValueError("no strings")
    return text.replace(old, new) if e.get("replace_all") else text.replace(old, new, 1)

# (d) the agent answering its own question
if tool == "AskUserQuestion":
    print("answers" if ti.get("answers") else "none"); sys.exit(0)

TRUST_RE = re.compile(r"(^|[\s=;&|(,\[\x27\x22])--trust(?![\w-])")
PROGRAM_FLAGS = {"-c", "-e", "--eval", "--command", "-lc", "-ec", "-ic", "eval"}

def trust_option(cmd):
    """Spec 095 R8 (F121): --trust as a word the shell passes on, not as prose inside a quoted argument
    (`finding.sh --add "… --trust …"`). It counts as its own word or an assignment's value
    (`A=--trust; … $A`), inside a program string handed to -c, -e or eval, and anywhere on a line
    that feeds a shell."""
    text = ANSI_C.sub(ansi_c, cmd)
    if not TRUST_RE.search(re.sub(r"[\"'\\]", "", text).lower()):
        return False
    from destructive_command import SHELLS, heredocs, pipelines, strip_redirects, tokens, word
    if "<<<" in text:
        return True                                      # a here-string handed to a program
    # A heredoc body is data unless its line runs a shell or an interpreter: notes written with
    # `cat >> f <<EOF` may quote the option (found 095).
    kept, docs = heredocs(text)
    lines = kept.split("\n")
    runners = SHELLS | {"eval", "python", "python3", "perl", "ruby", "node", "xargs"}
    fed = [body for idx, body in docs
           if any(word(t) in runners for t in tokens(lines[idx] if idx < len(lines) else ""))]
    text = "\n".join([kept] + fed)
    if not TRUST_RE.search(re.sub(r"[\"'\\]", "", text).lower()):
        return False
    for line in text.split("\n"):
        for pipe in pipelines(tokens(line)):
            for seg in pipe[1:]:                         # echo x | sh: the text upstream is a program
                ws = strip_redirects(seg)[0]
                if ws and (word(ws[0]) in SHELLS or word(ws[0]) in ("eval", "xargs")):
                    return True
    try:
        toks = shlex.split(text, posix=True)
    except ValueError:
        return True
    program = False                  # a -c/-e cluster or eval seen: every later word may be the program
    for t in toks:
        tl = t.lower()
        if (not re.search(r"\s", t) or program) and TRUST_RE.search(tl):
            return True
        if tl in PROGRAM_FLAGS or re.fullmatch(r"-[a-z]*[ce][a-z]*", tl) or tl.rpartition("/")[2] == "eval":
            program = True               # bash -c -x '…', bash -c -- '…' (095 /security-review)
    return False

# Spec 098 (threat model #6): a mode, owner, flag or name change on the git dir. None of these is a
# byte write, so bash-write-guard never delegated them, and each makes git fail in milliseconds with an
# answer (exit 128) that moves the root the guards walk to, or hides the stores. `.git` as a path
# component only: .gitignore and .github are not it.
# Spec 105 R1 (F184, F187): removing, creating or linking a path there is the same move. rm -r .git
# (without -f) passed every guard, and with .git gone the walk found no root; touch and mkdir under
# .git/claude-hook-notices pre-planted the once-per-session stamp. Judged per simple command: the verb by
# its basename past wrappers (/bin/rm, a backtick before it), and for cp, ln, install and dd only the
# destination, so copying out of .git stays a read. A glob component that can match .git counts
# (.g[i]t, .gi?, .*). Threat model #1, #2, #4. GIT_META, the regex, is the fallback for text the
# splitter cannot read.
META_VERBS = frozenset("chmod chown chgrp chflags chattr setfacl xattr mv rename rm rmdir unlink shred "
                       "truncate touch mkdir ln install cp dd rsync ditto tar unzip patch curl wget".split())
GIT_META = re.compile(r"(?:^|[\s;&|(/])(?:" + "|".join(sorted(META_VERBS)) + r")\b"
                      r"[^;&|\n]*?(?:^|[\s/=])\.git(?:/|[\s;&|)]|$)")
WRAPPERS = frozenset("sudo doas command builtin exec nice nohup env time stdbuf caffeinate timeout gtimeout "
                     "xargs busybox flock setsid ionice chroot".split())
# Options of a wrapper that take a value (sudo -u USER, timeout -s KILL, xargs -I {}), and wrappers whose
# first operand is not the command (flock LOCKFILE cmd, chroot DIR cmd). /security-review, spec 105:
# verb_of returned the option (-n) or the wrapper itself (timeout), and every per-command rule passed.
WRAPPER_VALUED = frozenset("-u -g -h -p -C -D -U -s -k -n -c -I -L -P -d -E -a -S -o -w --signal --kill-after "
                           "--user --group --chdir --unset --split-string".split())
WRAPPER_OPERAND = frozenset(("flock", "chroot"))
SEGCH = ";&|<>()"

_SEGS = {}

def segments(text):
    """Split once per text: git_meta, line_writes and path_write all read the same command (/simplify)."""
    if text not in _SEGS:
        _SEGS[text] = _split_segments(text)
    return _SEGS[text]

def _split_segments(text):
    """[(words, redirect_targets)] per simple command, quotes removed; None when it cannot be split."""
    out = []
    for line in text.split("\n"):
        lex = shlex.shlex(line, posix=True, punctuation_chars=SEGCH)
        lex.whitespace_split = True
        lex.commenters = ""
        words, targets, pend = [], [], None
        try:
            for t in lex:
                if t and all(c in SEGCH for c in t):
                    if ">" in t and not t.endswith("&") and "<" not in t:
                        pend = "out"                         # > f, >> f, &> f
                        if words and words[-1].isdigit():
                            words.pop()
                    elif t.endswith("<<<"):
                        pend = None                          # a here-string is data the command reads: kept as
                                                             # a word (xargs chmod 000 <<< .git)
                    elif "<" in t or ">" in t:
                        pend = "skip"                        # < f, << EOF, >&2: no file written
                    else:
                        if words or targets:
                            out.append((words, targets))
                        words, targets, pend = [], [], None
                    continue
                if pend == "out":
                    targets.append(t)
                elif pend is None:
                    words.append(t)
                pend = None
        except ValueError:
            return None
        if words or targets:
            out.append((words, targets))
    return out

def verb_of(words):
    """(basename of the command word past assignments, wrappers and the wrappers' own options, values
    and operands, its arguments)."""
    i, wrapped = 0, False
    while i < len(words):
        w = words[i].lstrip("\x60")
        b = w.rpartition("/")[2].lower()
        if re.match(r"^[A-Za-z_]\w*=", w):
            i += 1
            continue
        if b in WRAPPERS:
            wrapped = True
            i += 2 if b in WRAPPER_OPERAND else 1
            continue
        if wrapped and w.startswith("-"):
            i += 2 if (w in WRAPPER_VALUED and "=" not in w) else 1
            continue
        if wrapped and (re.fullmatch(r"[\d.]+[smhd]?", w) or re.fullmatch(r"(?:SIG)?[A-Z]+\d*", w)):
            i += 1                                       # timeout 5, timeout -s KILL 5
            continue
        return b, words[i + 1:]
    return "", []

def names_git(w):
    for c in w.replace("\\", "/").split("/"):
        c = c.strip("\x60").lower()
        if c == ".git" or (c.startswith(".") and GLOBCH.search(c) and fnmatch.fnmatchcase(".git", widen(c))):
            return True
    return False

# The option that names where a writer writes, per verb: (short letter, long names). A short option is
# read bare (-t d), attached (-td), or at the end of a cluster (-at d); adversarial review #1, #2, #9.
DEST_OPTS = {"cp": ("t", ("--target-directory",)), "ln": ("t", ("--target-directory",)),
             "install": ("t", ("--target-directory",)), "mv": ("t", ("--target-directory",)),
             "tar": ("C", ("--directory",)), "unzip": ("d", ()), "patch": ("d", ("--directory",)),
             "curl": ("o", ("--output",)), "wget": ("O", ("--output-document", "--directory-prefix"))}

def option_values(args, short, longs):
    out = []
    for i, a in enumerate(args):
        nxt = args[i + 1] if i + 1 < len(args) else ""
        if a in longs:
            out.append(nxt)
        elif any(a.startswith(l + "=") for l in longs):
            out.append(a.split("=", 1)[1])
        elif re.fullmatch(r"-[A-Za-z]*" + short, a):
            out.append(nxt)
        else:
            m = re.fullmatch(r"-[A-Za-z]*?" + short + r"(.+)", a)
            if m and not a.startswith("--"):
                out.append(m.group(1))
    return [v for v in out if v]

def destinations(verb, args):
    if verb == "dd":
        return [a[3:] for a in args if a.lower().startswith("of=")]
    named = option_values(args, *DEST_OPTS[verb]) if verb in DEST_OPTS else []
    ops = [a for a in args if not a.startswith("-")]
    if verb in ("cp", "ln", "install", "rsync", "ditto"):
        return named or ops[-1:]                     # the sources are read
    if verb in ("tar", "unzip", "curl", "wget"):
        return named                                 # where it extracts or downloads to
    return named + ops                               # mv moves its sources away; patch writes its file

def git_meta(text):
    segs = segments(text)
    if segs is None:
        return bool(GIT_META.search(re.sub(r"[\"'\\]", "", text).lower()))
    for words, _ in segs:
        verb, args = verb_of(words)
        if verb in META_VERBS and any(names_git(a) for a in destinations(verb, args)):
            return True
    return False

# Spec 105 R2 (F177): git spells the git dir without a .git component, so a substitution of it on a line
# that writes is a write into it. Printing it, or reading through it, is not; neither is grepping for the
# stamp directory's name (threat model #7). \x60 is a backtick, never written literally in this program
# (098 incident).
# Matched anywhere on the line, not only inside a $( ) the regex can balance: a nested $(:) before git
# hid it (adversarial review #3). A line that writes and asks git for its git dir is judged as writing there.
GIT_DIR_SUBST = re.compile(r"\brev-parse\b[^;&|\n]*--(?:git-dir|git-common-dir|absolute-git-dir|git-path)\b")
LINE_WRITERS = META_VERBS | frozenset("tee sed perl python python3 ruby node".split())

def line_writes(text):
    segs = segments(text)
    if segs is None:
        return True
    return any(targets or verb_of(words)[0] in LINE_WRITERS for words, targets in segs)

# Spec 105 R4 (F176, developer O2): the guards run git, timeout, perl, python3 and jq by PATH, so a file
# written into a PATH directory can answer for any of them. Any name: a list of tool names would drift.
FOLD = sys.platform in ("darwin", "win32", "cygwin")

def path_dirs():
    out = set()
    for e in (os.environ.get("PATH") or "").split(os.pathsep):
        if not os.path.isabs(e):
            continue          # an empty or relative entry is the cwd: recorded as F261, not judged here
        for v in (os.path.normpath(e), os.path.realpath(e)):
            out.add(v.casefold() if FOLD else v)
    return out

_PATH_DIRS = []

def _norm_dir(d):
    return [v.casefold() if FOLD else v for v in (os.path.normpath(d), os.path.realpath(d))]

def on_path(q, as_dir=False):
    """q (absolute) is in a PATH directory, or is one when as_dir."""
    if not _PATH_DIRS:
        _PATH_DIRS.append(path_dirs())
    q = os.path.normpath(q)
    if q == "/dev" or q.startswith("/dev/"):
        return False
    d = q if as_dir else os.path.dirname(q)
    return any(v in _PATH_DIRS[0] for v in _norm_dir(d))

# rm and unlink too: a guard whose jq or perl is gone fails open (threat model #14).
PATH_WRITERS = frozenset("ln install touch chmod cp mv rsync ditto dd tee mkdir truncate rm unlink tar unzip curl wget patch".split())
INTO_DIR = frozenset("ln install cp mv rsync ditto tar unzip wget".split())

def _expand_home(w):
    home = os.environ.get("HOME") or os.path.expanduser("~")
    for pre in ("~/", "$HOME/", "${HOME}/"):
        if w.startswith(pre):
            return os.path.join(home, w[len(pre):])
    if w in ("~", "$HOME", "${HOME}"):
        return home
    return w

def path_write(text):
    def hit(a, verb=""):
        a = _expand_home(a)
        if not a or "$" in a:
            return False
        q = a if os.path.isabs(a) else os.path.join(cwd, a)
        return on_path(q) or (verb in INTO_DIR and on_path(q, as_dir=True))
    for words, targets in segments(text) or ():
        if any(hit(t) for t in targets):
            return True
        verb, args = verb_of(words)
        if verb in PATH_WRITERS and any(hit(a, verb) for a in destinations(verb, args)):
            return True
    return False

def shell_verdict(cmd):
    n = ANSI_C.sub(ansi_c, cmd)                              # $'\x63laude' -> claude (adversarial #2)
    n = re.sub(r"[\"'\\]", "", n).lower()
    if (re.search(r"claude-(trusted|developer|mod-acc)|trusted-comm|developer-word|mod-accepted", n)
            or re.search(r"\.git/\S*[*?\[{]", n) or re.search(r"\.git\S*[*?\[{]\S*/", n)
            or re.search(r"claude-[^\s/]*[*?\[{]", n)):
        return "bash-store"
    if "maintenance_tty" in n or "claudecode" in n:
        return "bash-tty"
    if ".git/worktrees" in n or "separate-git-dir" in n or re.search(r"\bln\b[^;&|]*acceptance\.md", n):
        return "bash-gitdir"
    text = ANSI_C.sub(ansi_c, cmd)
    if git_meta(text):
        return "bash-gitmeta"
    if ("claude-hook-notices" in n or GIT_DIR_SUBST.search(n)) and line_writes(text):
        return "bash-notice"
    if path_write(text):
        return "bash-path-write"
    if "confirmed:**" in n:
        return "bash-confirmed"
    if trust_option(cmd):
        return "bash-trust"
    from destructive_command import classify_trust                            # git's word rules (spec 091 R2)
    return classify_trust(cmd)

# (c) shell text
cmd = ti.get("command")
if isinstance(cmd, str) and not tool.startswith("mcp__"):
    print(shell_verdict(cmd) or "none"); sys.exit(0)

# Spec 095 R3 (F116): an MCP or plugin tool names its file in a field of its own choosing. Every
# string is read (values, object keys, runs of neighbouring strings), and a command-shaped string is
# judged as shell text. A tool whose name says it reads is left alone, as the Read tool is.
if tool.startswith("mcp__"):
    from settings_guard import McpTooBig, mcp_inputs                         # one reading of the payload
    try:
        found = mcp_inputs(tool, ti)
    except McpTooBig:
        print("acceptance-shell" if re.search(r"\.git|acceptance|placement", json.dumps(ti).lower()) else "none")
        sys.exit(0)
    if found is None:
        print("none"); sys.exit(0)
    paths, commands = found
    for q in paths:
        q = os.path.expanduser(q)
        q = q if os.path.isabs(q) else os.path.join(cwd, q)
        if touches_git(q):
            print("store"); sys.exit(0)
        if path_hits(q, lambda ps: ps[-2:] == [".claude", "workload-placement.tsv"]):
            print("placement"); sys.exit(0)
        if on_path(q):
            print("path-write"); sys.exit(0)
        if is_acceptance(q):
            print("acceptance-shell"); sys.exit(0)
    for s in commands:
        verdict = shell_verdict(s)
        if verdict:
            print(verdict); sys.exit(0)
    print("none"); sys.exit(0)

# (a) (b) a path
fp = ti.get("file_path") or ti.get("notebook_path")
if not isinstance(fp, str) or not fp:
    print("none"); sys.exit(0)
p = fp if os.path.isabs(fp) else os.path.join(cwd, fp)
if touches_git(p):
    print("store"); sys.exit(0)
# Spec 091 R7 (O2): which jobs may be stamped done from the cloud is the developer's decision.
if path_hits(p, lambda ps: ps[-2:] == [".claude", "workload-placement.tsv"]):
    print("placement"); sys.exit(0)
if on_path(p):
    print("path-write"); sys.exit(0)

# Spec 105 R6 (F174): an edit that leaves a script under scripts/ unparseable. A live PreToolUse guard
# that does not parse exits 2 on every call it matches, its own repair included. Refused only when the
# current bytes parse: a new or already-broken file can always be written. A check that cannot run is no
# verdict.
def parse_error(path, text):
    try:
        if path.endswith(".py"):
            try:
                compile(text, path, "exec")
            except SyntaxError as e:
                return "line %s: %s" % (e.lineno, e.msg)
            except ValueError as e:                      # a NUL byte before 3.12 (adversarial review #7)
                return str(e)
            return ""
        import subprocess
        # The interpreter the shebang names, when it is a shell that has -n (threat model #23).
        sh = "bash"
        m = re.match(r"#!\s*(?:/usr/bin/env\s+)?(?:\S*/)?(sh|bash|zsh|dash|ksh)\b", text)
        if m and m.group(1) != "bash":
            sh = m.group(1)
        r = subprocess.run([sh, "-n"], input=text.encode("utf-8", "replace"),
                           capture_output=True, timeout=5)
        if r.returncode == 0:
            return ""
        msg = r.stderr.decode("utf-8", "replace").strip().splitlines()
        return re.sub(r"^bash: (?:line |-: line )?", "line ", msg[0]) if msg else "bash -n exit %d" % r.returncode
    except Exception:
        return None

def after_of(cur):
    if isinstance(ti.get("content"), str):
        return ti["content"]
    if isinstance(ti.get("edits"), list):
        out = cur
        for e in ti["edits"]:
            out = apply(out, e)
        return out
    if "old_string" in ti:
        return apply(cur, ti)
    raise ValueError("no bytes")

# scripts/ judged case-folded and resolved (SCRIPTS/x.sh, a link s -> scripts); only a regular file under
# 2 MB is read, never a FIFO (threat model #21, #22).
_rp = os.path.realpath(p)
if tool in ("Edit", "Write", "MultiEdit") and _rp.lower().endswith((".sh", ".py")) \
        and "scripts" in (os.path.basename(os.path.dirname(p)).lower(), os.path.basename(os.path.dirname(_rp)).lower()):
    _cur = None
    try:
        if os.path.isfile(_rp) and os.path.getsize(_rp) <= 2 * 1024 * 1024:
            with open(_rp, "r", encoding="utf-8", errors="replace", newline="") as fh:
                _cur = fh.read()
    except OSError:
        _cur = None
    if _cur is not None:
        try:
            _new = after_of(_cur)
        except Exception:
            _new = None
        _kind = ".py" if _rp.lower().endswith(".py") else ".sh"
        # The new bytes first: an edit that parses (the common case) costs one check, not two (/simplify).
        _err = parse_error(_kind, _new) if _new is not None else None
        if _err and parse_error(_kind, _cur) == "":
            print("syntax\t" + " ".join(_err.split())[:200]); sys.exit(0)

if not is_acceptance(p):
    print("none"); sys.exit(0)

has_bytes = any(k in ti for k in ("content", "old_string", "new_string", "edits", "new_source"))
if not has_bytes or GLOBCH.search(fp):
    print("acceptance-shell"); sys.exit(0)
try:
    with open(p, "r", encoding="utf-8", errors="replace", newline="") as fh:
        cur = fh.read()
except OSError:
    cur = ""
try:
    if isinstance(ti.get("content"), str):
        after = ti["content"]
    elif isinstance(ti.get("edits"), list):
        after = cur
        for e in ti["edits"]:
            after = apply(after, e)
    elif "old_string" in ti:
        after = apply(cur, ti)
    else:
        raise ValueError("no bytes")
except Exception:
    # Cannot simulate: judge the written strings, conservatively.
    print("acceptance-confirmed" if "confirmed:" in json.dumps(ti).lower() else "none"); sys.exit(0)
print("acceptance-confirmed" if conf_lines(after) != conf_lines(cur) else "none")
PY
)
VERDICT=$(printf '%s' "$INPUT" | python3 -c "$PROG" "$HOOK_DIR" 2>/dev/null) || VERDICT="crash"
[ -n "$VERDICT" ] || VERDICT="crash"

# The repair path (found 2026-10-01): a crash inside this verdict denied every call, its own repair
# included. A crash still denies, except an Edit/Write of the files the verdict runs on. In a project
# those are CORE, so core-machinery-guard still stands in front of them.
if [ "$VERDICT" = crash ] && [[ $TI =~ \"file_path\"[[:space:]]*:[[:space:]]*\"[^\"]*/scripts/(trust-anchor-guard-hook\.sh|acceptance_cases\.py|shell_glob\.py|settings_guard\.py|destructive_command\.py|guard-lib\.sh)\" ]]; then
  guard_context "trust-anchor-guard crashed and ALLOWED this edit unchecked, because it is an edit of the guard's own code (${BASH_REMATCH[1]}): a guard that cannot run must not block its own repair. Fix the crash; every other call it would judge is denied until then."
  exit 0
fi

HUMAN_ROUTES="The developer's own routes are unchanged: they trust nightly commands with  bash scripts/project-maintenance.sh --trust  in a terminal of their own, and they confirm acceptance cases by answering an AskUserQuestion that shows the cases and their digest, after which  bash scripts/acceptance-cases.sh --confirm <spec-dir> --quote \"<their exact answer>\"  records it."

case "$VERDICT" in
  none) exit 0 ;;
  store)
    guard_deny "BLOCKED — this call writes inside a git directory, or writes a .git entry (spec 088, R3).

That covers the two trust stores (.git/claude-trusted-commands decides what the unattended nightly may execute; .git/claude-developer-words holds the developer's AskUserQuestion answers), the rest of .git/, and a new .git file or directory below the project, which used to move the root the pipeline guards walk to (F090). Only the developer at a terminal, the developer-words hook and git itself write there.

To look at a file there, use the Read tool. $HUMAN_ROUTES" ;;
  bash-store)
    guard_deny "BLOCKED — this shell command names a trust store, or a glob through .git/ that can expand to one (spec 088, R3).

The command is not shown here. Shell access to .git/claude-trusted-commands and .git/claude-developer-words is refused whether it reads or writes, because the guard judges the command text; to look at one, use the Read tool. $HUMAN_ROUTES" ;;
  bash-tty)
    guard_deny "BLOCKED — this shell command names MAINTENANCE_TTY or CLAUDECODE (spec 088, R3).

The first picks where project-maintenance.sh --trust reads the human's \`yes\`; the second is how it knows it runs inside Claude Code and refuses --yes. Setting or clearing either from an agent's shell is answering for the developer. $HUMAN_ROUTES" ;;
  bash-gitdir)
    guard_deny "BLOCKED — this shell command names .git/worktrees, uses --separate-git-dir, or hard-links an acceptance.md (spec 088, R1/R3).

A linked worktree below the project is a root the pipeline guards stop at, recognised by the link git keeps in this project's own git dir. Create one with \`git worktree add\`, which this guard allows; making the link by hand, or a repository whose git dir lives elsewhere, is not allowed. A hard link would let an acceptance.md be edited under a name this guard does not judge." ;;
  bash-gitmeta)
    guard_deny "BLOCKED — this shell command removes, creates, links or changes the mode, owner, flags or name of a path in the git dir (specs 098, 105 R1).

rm or rmdir on .git leaves the guards with no root to walk to; touch or mkdir there can pre-plant a notice stamp; chmod, chown, chflags, setfacl, xattr or mv on .git makes git fail at once. The pipeline guards read that failure as an answer and walk to another root, and the trust stores in .git stop being readable. Only the developer changes the git dir; ask them, and they can run it themselves with the ! prefix." ;;
  bash-notice)
    guard_deny "BLOCKED — this shell command names the guards' notice stamps (claude-hook-notices), or spells the git dir through git rev-parse inside a substitution (spec 105, R2).

A stamp there marks a fail-open guard's notice as already said this session; one made in advance silences the notice for you and the developer's toast. \$(git rev-parse --git-dir) is the git dir without a .git in the text, so it is judged as the git dir. Printing it on its own (git rev-parse --git-dir) is fine." ;;
  bash-path-write|path-write)
    guard_deny "BLOCKED — this call writes into a directory on PATH (spec 105, R4).

The guards run git, timeout, perl, python3 and jq by name through PATH, so a file placed in a PATH directory (~/.local/bin, /opt/homebrew/bin, …) can answer for any of them and switch every guard off. Installing a tool there is the developer's step; ask them, and they can run it with the ! prefix." ;;
  syntax*)
    guard_deny "BLOCKED — this edit leaves the script unparseable: ${VERDICT#syntax	} (spec 105, R6).

The file parses now and would not after this edit. A PreToolUse guard that does not parse fails every call it matches, its own repair included, and only the developer can fix it with !. Fix the edit (check quoting, an unclosed \$( or heredoc, a backtick inside a \$( <<'PY' program) and try again. A file that is already broken, or a new one, is never refused by this check." ;;
  bash-trust)
    guard_deny "BLOCKED — this shell command passes --trust (spec 088, R3).

Trusting is the step where a person reads what the 02:30 nightly will execute and agrees to it. An agent cannot take it, with or without --yes, under any name for the script. Tell the developer which items are untrusted and ask them to run it. $HUMAN_ROUTES" ;;
  bash-confirmed)
    guard_deny "BLOCKED — this shell command writes the text of an acceptance-case Confirmed line (spec 088, R3).

Only scripts/acceptance-cases.sh --confirm writes that line, and only for a quote the developer gave in an AskUserQuestion. $HUMAN_ROUTES" ;;
  acceptance-confirmed)
    guard_deny "BLOCKED — this edit adds, removes or changes the **Confirmed:** line of an acceptance.md (spec 088, R3).

Edit the cases themselves freely; changing a case un-confirms it, and that is the point. The Confirmed line is written only by scripts/acceptance-cases.sh --confirm, for a quote the developer gave. $HUMAN_ROUTES" ;;
  acceptance-shell)
    guard_deny "BLOCKED — a shell write to an acceptance.md, or to a glob that can match one (spec 088, R3).

The shell route carries no bytes to this guard, so it cannot tell a case edit from a forged Confirmed line. Use the Edit tool for the cases (it is judged on the bytes), and scripts/acceptance-cases.sh --confirm for the Confirmed line. $HUMAN_ROUTES" ;;
  git-config-exec)
    guard_deny "BLOCKED — this git config write sets a key whose value git runs as a program, or a key spelled at runtime (spec 095, R10).

core.hooksPath, core.fsmonitor, core.sshCommand, core.pager, core.editor, filter.*, credential.*, diff.*.textconv, merge.*.driver and the like run a command inside the developer's next git call, and inside every guard that calls git. They are the developer's to set. A one-shot \`git -c key=value <command>\` is not refused: it reaches only the command it prefixes. If the change is really needed, ask the developer to run it with ! in the prompt." ;;
  git-remote-write|git-config-trust|git-ref-write)
    guard_deny "BLOCKED — this git command changes a remote, an upstream or a remote-tracking ref (spec 091, R2).

\`git remote add|set-url|rename|remove\`, a \`git config\` write under remote.*, url.* (insteadOf), branch.*, include* or alias.*, \`git update-ref\`, \`git symbolic-ref\` with a target, and a fetch or push refspec that writes refs/remotes/ are the developer's steps. Where origin points and which upstream a branch tracks decide what the guards trust: the template is recognised by its history, and a Confirmed line counts only when this clone recorded the developer's answer (spec 098). Reading is fine: \`git remote -v\`, \`git config --get …\`, \`git fetch origin\`, \`git push\`. If the change is really needed, ask the developer to run it with ! in the prompt." ;;
  placement)
    guard_deny "BLOCKED — .claude/workload-placement.tsv decides which maintenance jobs a cloud run may mark done (spec 091, R7).

Placing a job in the cloud means trusting a stamp that arrives on a branch, so it is the developer's decision, like --trust. Tell the developer which line you would change and why; they edit it themselves or with ! in the prompt. Reading it (Read, cat, workload-placement.sh --list) is fine." ;;
  answers)
    guard_deny "BLOCKED — this AskUserQuestion already carries answers (spec 088, R3).

An honest question reaches this hook with questions only; the answers come from the developer afterwards, and the developer-words hook records them. Ask again without an answers field." ;;
  crash)
    guard_deny "BLOCKED — trust-anchor-guard crashed (python3 missing, or an error in its verdict) on a call whose text mentions a trust store, a Confirmed line, --trust or an answered question. It does not allow what it could not judge (spec 088, R3). Its own files (scripts/trust-anchor-guard-hook.sh, acceptance_cases.py, guard-lib.sh) stay editable with the Edit tool so it can be repaired." ;;
  *)
    guard_deny "BLOCKED — trust-anchor-guard cannot read this call (the payload is not JSON, or python3 is missing), and its text mentions a trust store, a Confirmed line, --trust or an answered question. A guard that cannot see what it guards does not allow (spec 088, R3)." ;;
esac
exit 0
