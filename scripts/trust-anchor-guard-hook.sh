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
#       `.git` file or directory (F090's own move). A symlink is judged where it lands.
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

INPUT=$(cat 2>/dev/null || true)
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
if [ "${#TI}" -gt 4096 ]; then
  HIT=1
else
  N=${TI//[\"\'\\]/}
  shopt -s nocasematch
  case "$N" in
    *claude-*|*trusted-comm*|*developer-word*|*maintenance_tty*|*claudecode*|*confirmed:*|*acceptance*) HIT=1 ;;
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
  shopt -u nocasematch
  # A file_path that is a symlink may land on a store under an innocent name, and a glob (a shell write
  # bash-write-guard delegates unexpanded) may match an acceptance.md under any spelling.
  if [ "$HIT" -eq 0 ] && [[ $TI =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    _fp="${BASH_REMATCH[1]}"
    case "$_fp" in *[*?{[]*) HIT=1 ;; esac
    [ -L "$_fp" ] && HIT=1
    # A hard link to an acceptance.md under another name (/security-review, spec 088): -ef compares
    # device and inode, as a builtin.
    if [ "$HIT" -eq 0 ] && [ -f "$_fp" ]; then
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
import fnmatch, glob, json, os, re, sys

sys.path.insert(0, sys.argv[1])
from acceptance_cases import ACCEPTANCE_GLOBS, CONFIRMED_PREFIX as PREFIX   # the parser's own rules
from shell_glob import ANSI_C, BRACE_CAP, TooMany, ansi_c, brace_alts      # bash's word rules (spec 090)

STORES = ("claude-trusted-commands", "claude-developer-words")
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

def touches_git(p):
    return path_hits(p, lambda ps: ".git" in ps or (bool(ps) and ps[-1] in STORES))

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

# (c) shell text
cmd = ti.get("command")
if isinstance(cmd, str):
    n = ANSI_C.sub(ansi_c, cmd)                              # $'\x63laude' -> claude (adversarial #2)
    n = re.sub(r"[\"'\\]", "", n).lower()
    if (re.search(r"claude-(trusted|developer)|trusted-comm|developer-word", n)
            or re.search(r"\.git/\S*[*?\[{]", n) or re.search(r"\.git\S*[*?\[{]\S*/", n)
            or re.search(r"claude-[^\s/]*[*?\[{]", n)):
        print("bash-store"); sys.exit(0)
    if "maintenance_tty" in n or "claudecode" in n:
        print("bash-tty"); sys.exit(0)
    if ".git/worktrees" in n or "separate-git-dir" in n or re.search(r"\bln\b[^;&|]*acceptance\.md", n):
        print("bash-gitdir"); sys.exit(0)
    if "confirmed:**" in n:
        print("bash-confirmed"); sys.exit(0)
    if re.search(r"(^|[\s=;&|(])--trust(?![\w-])", n):
        print("bash-trust"); sys.exit(0)
    from destructive_command import classify_trust                            # git's word rules (spec 091 R2)
    found = classify_trust(cmd)
    if found:
        print(found); sys.exit(0)
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
if [ "$VERDICT" = crash ] && [[ $TI =~ \"file_path\"[[:space:]]*:[[:space:]]*\"[^\"]*/scripts/(trust-anchor-guard-hook\.sh|acceptance_cases\.py|shell_glob\.py|guard-lib\.sh)\" ]]; then
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
  git-remote-write|git-config-trust|git-ref-write)
    guard_deny "BLOCKED — this git command changes a remote, an upstream or a remote-tracking ref (spec 091, R2).

\`git remote add|set-url|rename|remove\`, a \`git config\` write under remote.*, url.* (insteadOf), branch.*, include* or alias.*, \`git update-ref\`, \`git symbolic-ref\` with a target, and a fetch or push refspec that writes refs/remotes/ are the developer's steps. Where origin points and which upstream a branch tracks decide what the guards trust: the template is recognised by its history, and a Confirmed line counts once it is on the upstream. Reading is fine: \`git remote -v\`, \`git config --get …\`, \`git fetch origin\`, \`git push\`. If the change is really needed, ask the developer to run it with ! in the prompt." ;;
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
