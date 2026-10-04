#!/bin/bash
# guard-lib.sh — what every PreToolUse guard needs and none of them may get wrong (spec 083).
#
# Source it; do not execute it:
#     . "$(dirname "${BASH_SOURCE[0]}")/guard-lib.sh"
#
# WHY THIS FILE EXISTS
# --------------------
# H1's adversarial pass found the guards failing in the same three ways, each guard on its own:
#
#   * jq missing (F044). Every guard read its payload with `jq -r … 2>/dev/null`, so with no jq the
#     path came back empty and the guard exited 0. The deny itself was printed by `jq -n`, so even a
#     guard that reached its verdict printed nothing. Nearly every guard allowed, and none said so.
#   * an unnormalised path (F040). `<root>/x/../scripts/<core>.sh` and `<root>//scripts/<core>.sh`
#     were judged by string prefix and fell outside every pattern. A relative path found no .git.
#   * an exemption that was a substring (F041). `*/scripts/*` exempted `src/scripts/app.js`.
#
# Seven copies of the same mistake is what a library is for. Each function below is the one place
# its question is answered.
#
# FAIL-CLOSED AND FAIL-OPEN ARE BOTH LEGITIMATE — SILENT IS NOT
# -------------------------------------------------------------
# spec-register, pipeline-state and spec-interview protect a process the project committed to: when
# they cannot read a payload that names a source file they deny (guard_unreadable_deny). The
# developer chose that (spec 083, O3). core-machinery, core-owed-tick and bash-write protect files
# the template owns or sit in front of every Bash call; they keep failing open for the reasons in
# their headers, but they now say so (guard_announce). No guard may allow without a word when it
# could not decide.
#
# Spec 098 carried that to the root walk: git runs bounded (_guard_git), and a walk that needed git
# and got no answer sets GUARD_GIT_UNSURE. The pipeline guards deny on it (guard_unsure_deny), the
# CORE guards announce. The announce stamp lives in the git dir, where the agent cannot plant one.
#
# Callers set INPUT to the raw payload before calling guard_field without a second argument.

# hook-notice.sh owns the per-session "say this once" state; reused, not copied.
_GUARD_LIB_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=/dev/null
[ -f "$_GUARD_LIB_DIR/hook-notice.sh" ] && . "$_GUARD_LIB_DIR/hook-notice.sh"

# ------------------------------------------------------------------ which parser
# jq | python3 | none. Decided once per process; PATH does not change under a hook.
if command -v jq >/dev/null 2>&1; then GUARD_PARSER=jq
elif command -v python3 >/dev/null 2>&1; then GUARD_PARSER=python3
else GUARD_PARSER=none; fi

guard_parser_state() { printf '%s\n' "$GUARD_PARSER"; }

# ------------------------------------------------------------------ reading a field
# guard_field <.dotted.path> [json]
#   0  the value on stdout (a string as-is, anything else as JSON text, absent/null as empty)
#   3  no parser on PATH
#   4  the payload is not a JSON object
# Paths are literals from the calling guard, never from the payload.
guard_field() {
  local path="$1" json
  if [ $# -ge 2 ]; then json="$2"; else json="${INPUT:-}"; fi
  case "$GUARD_PARSER" in
    jq)
      printf '%s' "$json" | jq -r "if type == \"object\" then ($path // \"\") else error(\"not an object\") end
                                   | if type == \"string\" then . else tojson end" 2>/dev/null || return 4
      ;;
    python3)
      printf '%s' "$json" | python3 -c '
import json, sys
try:
    v = json.loads(sys.stdin.read())
except Exception:
    sys.exit(4)
if not isinstance(v, dict):
    sys.exit(4)
for k in sys.argv[1].split("."):
    if k:
        v = v.get(k) if isinstance(v, dict) else None
if v is None:
    v = ""
sys.stdout.write(v if isinstance(v, str) else json.dumps(v))
' "$path" 2>/dev/null
      ;;
    *) return 3 ;;
  esac
}

# ------------------------------------------------------------------ writing JSON
# guard_json_str <text>: one JSON string literal. jq, then python3, then bash, so a deny never
# depends on the tool whose absence it may be reporting.
guard_json_str() {
  case "$GUARD_PARSER" in
    jq)      printf '%s' "$1" | jq -Rs . 2>/dev/null && return 0 ;;
    python3) python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1]))' "$1" 2>/dev/null && return 0 ;;
  esac
  local s="$1" c i oct
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  # The remaining C0 controls. Bash cannot hold NUL, so 1..31 is the whole set.
  for i in 1 2 3 4 5 6 7 8 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
    oct=$(printf '%03o' "$i")
    c=$(printf "\\$oct")
    case "$s" in *"$c"*) s=${s//"$c"/$(printf '\\u%04x' "$i")} ;; esac
  done
  printf '"%s"' "$s"
}

# guard_deny <reason>: the PreToolUse deny, with hookEventName (spec 046: without it the CLI drops
# the whole object). The caller exits 0 afterwards — the CLI reads stdout JSON on exit 0 only.
guard_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(guard_json_str "$1")"
}

# guard_context <text>: additionalContext for the model, no decision.
guard_context() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' \
    "$(guard_json_str "$1")"
}

# guard_announce <guard> <cause>: a fail-open guard could not decide. Once per session per cause, so
# a broken machine is heard without every tool call repeating it. Without a session id (a test, an
# old harness) it is said every time.
#
# Spec 098 R6 (F144, developer O4): the once-per-session stamp lives in the project's git dir, which
# trust-anchor-guard keeps the agent's tools out of. Under $TMPDIR its path was predictable, and a
# stamp made first silenced the notice for the model and the developer's toast (096). No git dir found
# means no stamp at all: the notice is said every time, never kept under $TMPDIR.
guard_announce() {
  local guard="$1" cause="$2" sid text base
  text="$guard could not decide and ALLOWED this call: $cause. It fails open by design (see its header), so this edit or command was not checked by it. Fix the cause to restore the check."
  sid=""
  if command -v hn_session_id >/dev/null 2>&1; then sid=$(hn_session_id "${INPUT:-}"); fi
  if command -v hn_first_time >/dev/null 2>&1 && [ -n "$sid" ] && base=$(_guard_notice_base); then
    hn_first_time "$sid" "guard-announce:$guard:$cause" "$base" || return 0
  fi
  guard_context "$text"
}

# _guard_notice_base: <git dir>/claude-hook-notices for CLAUDE_PROJECT_DIR, found upward (a monorepo
# package directory has no .git of its own) and through a .git file's gitdir: line. Builtins only.
# Exit 1 when there is none.
_guard_notice_base() {
  local d="${CLAUDE_PROJECT_DIR:-}" g
  [ -n "$d" ] || return 1
  d="${d%/}"
  while [ -n "$d" ]; do
    if [ -d "$d/.git" ] && [ ! -L "$d/.git" ]; then printf '%s/.git/claude-hook-notices' "$d"; return 0; fi
    if [ -f "$d/.git" ]; then
      _guard_gitdir_of "$d" || return 1
      g=$GUARD_GITDIR
      [ -d "$g" ] || return 1
      printf '%s/claude-hook-notices' "${g%/}"; return 0
    fi
    [ -e "$d/.git" ] && return 1            # a symlinked or odd .git: no stamp, say it every time
    d="${d%/*}"
  done
  return 1
}

# guard_cause <rc>: the words for a guard_field failure.
guard_cause() {
  case "$1" in
    3) printf 'no JSON parser on PATH (install jq; python3 is the fallback)' ;;
    4) printf 'the hook payload is not a JSON object' ;;
    *) printf 'the payload could not be read (rc %s)' "$1" ;;
  esac
}

# guard_unreadable_deny <guard> <cause>: the fail-closed verdict (spec 083 R2, O3).
guard_unreadable_deny() {
  guard_deny "BLOCKED — $1 cannot read this tool call: $2.

The call names a source-code file, and this guard protects the pipeline this project committed to. A gate that cannot see what it is guarding does not allow (spec 083, R2).

To fix: install jq (brew install jq · apt/dnf/pacman install jq · winget install jqlang.jq). python3 is the fallback parser, so either one restores the check.

Edits under scripts/, specs/, .specify/ and .claude/ at the project root, and every non-source file, stay allowed, so the tooling can be repaired now."
}

# ------------------------------------------------------------------ which file system
# macOS and Windows fold case (and macOS folds Unicode normalisation), so two spellings open one file.
# NTFS also drops trailing dots and spaces from a name. Decided once from OSTYPE, as PATH is above.
GUARD_ANCHOR_FOLD=0
GUARD_NTFS=0
case "${OSTYPE:-}" in
  darwin*) GUARD_ANCHOR_FOLD=1 ;;
  msys*|cygwin*|win*) GUARD_ANCHOR_FOLD=1; GUARD_NTFS=1 ;;
esac
# OSTYPE says linux for WSL on /mnt/c, a casefold ext4 directory and an SMB mount, all of which fold
# (spec 090 threat model, #6). Two stats ask the project itself: a folding file system opens .GIT too.
if [ "$GUARD_ANCHOR_FOLD" -eq 0 ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ] \
   && [ -e "$CLAUDE_PROJECT_DIR/.git" ] && [ -e "$CLAUDE_PROJECT_DIR/.GIT" ]; then
  GUARD_ANCHOR_FOLD=1
fi

# ------------------------------------------------------------------ canonical paths
# THE STORED NAME (spec 090 R1, F082, F105). A canonical path used to keep the spelling it was given:
# bash's builtin `pwd -P` prints the case and Unicode form cd was handed (measured on APFS), so
# <proj>/SCRIPTS/x.sh and <proj>/scripts/x.sh were two paths to the guards and one file to the disk,
# and a CLAUDE_PROJECT_DIR spelled NFD did not contain a file spelled NFC. Where the file system folds,
# directories now come from getcwd (/bin/pwd -P), which returns the name as stored, and an existing
# final component is matched case-insensitively in its directory. A name that does not exist keeps
# its typed spelling, since nothing is stored to look up.
#
# Still open (spec 090 threat model): a hard link that already exists under an innocent name (one
# inode, two names; telling them apart needs a stat per Edit), a name that does not exist yet, NTFS
# short names (APPCS~1.CS) and named streams other than ::$DATA.
#
# _guard_pwd: the working directory as stored. Falls back to the builtin, which is the old behaviour.
_guard_pwd() {
  if [ "$GUARD_ANCHOR_FOLD" -eq 1 ] && [ -x /bin/pwd ]; then /bin/pwd -P 2>/dev/null && return 0; fi
  pwd -P
}

# _guard_stored_name <name>: GUARD_STORED, the entry of the current directory that <name> opens. A
# builtin glob with every letter as a bracket and nocaseglob on; an exact match wins (a case-sensitive
# volume can hold both App.cs and APP.CS), then a single folded match, else the name as given.
# Called inside guard_canon's subshell, so the shell options it sets do not leak.
_guard_stored_name() {
  local n="$1" pat="" i c m
  GUARD_STORED="$n"
  [ "$GUARD_ANCHOR_FOLD" -eq 1 ] || return 0
  { [ -e "$n" ] || [ -L "$n" ]; } || return 0
  for ((i = 0; i < ${#n}; i++)); do
    c=${n:i:1}
    case "$c" in [[:alpha:]]) pat="$pat[$c]" ;; *) pat="$pat\\$c" ;; esac
  done
  set +f
  shopt -s nocaseglob nullglob dotglob
  local IFS=''
  # shellcheck disable=SC2086
  set -- $pat
  for m in "$@"; do [ "$m" = "$n" ] && return 0; done
  [ $# -eq 1 ] && GUARD_STORED="$1"
  return 0
}

# _guard_ntfs_trim <name>: GUARD_TRIMMED, the name NTFS opens: trailing dots and spaces dropped, and a
# `::$DATA` suffix (the file's own data stream). Used on the components of a path on msys/cygwin/win,
# and by guard_ext_of on every platform (developer, 090 O2: WSL on an NTFS mount reports linux).
_guard_ntfs_trim() {
  local b="$1" prev=""
  while [ "$b" != "$prev" ]; do
    prev=$b
    case "$b" in .|..) break ;; esac
    case "$b" in *'::$'[Dd][Aa][Tt][Aa]) b=${b%???????} ;; esac
    case "$b" in ?*.|?*' ') b=${b%?} ;; esac
  done
  GUARD_TRIMMED=$b
}

# guard_ext_of <path>: GUARD_EXT, the extension of the file a write lands on (spec 090 R3, F096). On
# NTFS `App.cs.`, `App.cs ` and `App.cs::$DATA` are App.cs, and read by their last dot they were not
# source at all. Case is left to the caller, which compares with nocasematch.
guard_ext_of() {
  _guard_ntfs_trim "${1##*/}"
  case "$GUARD_TRIMMED" in *.*) GUARD_EXT=${GUARD_TRIMMED##*.} ;; *) GUARD_EXT="" ;; esac
}

# guard_target_path: FILE, the path a pipeline guard judges, and guard_field's return code. NotebookEdit
# names its file notebook_path (spec 090 R4, F084).
guard_target_path() {
  local rc
  FILE=$(guard_field .tool_input.file_path); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$FILE" ]; then FILE=$(guard_field .tool_input.notebook_path); rc=$?; fi
  return $rc
}

# guard_is_source <path>: 0 when the extension NTFS reads is in the caller's SOURCE_EXTS (R3).
guard_is_source() {
  local rc=1 was=0
  guard_ext_of "$1"
  shopt -q nocasematch && was=1
  shopt -s nocasematch
  [[ $GUARD_EXT =~ ^($SOURCE_EXTS)$ ]] && rc=0
  [ "$was" -eq 1 ] || shopt -u nocasematch
  return $rc
}

# guard_canon <path> [base]: an absolute path with ., .. and // resolved (spec 083 R4, F040).
#
# Walked left to right the way the kernel walks it: each component that is an existing directory is
# entered with `cd -P`, so a symlinked directory and a `..` after it land where a write would land.
# The first component that does not exist as a directory ends the walk; the rest is normalised
# lexically, since there is nothing on disk to consult. A symlink in the final component is
# followed afterwards, by guard_canon, so the file a write would really change is the one judged.
#
# A relative path is taken against <base>, else the payload's .cwd, else $PWD. One subshell for the
# whole walk — this runs on the Edit hot path, after the cheap prechecks. Trailing slashes are
# stripped first so the last element is the name, never "".
guard_canon() {
  # The final component is followed when it is a symlink (spec 083, adversarial review #11): a Write
  # to docs/x.txt that links to src/App.cs writes App.cs, so App.cs is what the guards must judge. At
  # most 8 hops; a loop past that is judged at the last name reached.
  local out hops=0 link
  out=$(_guard_canon_walk "$@") || return 1
  while [ "$hops" -lt 8 ]; do
    [ -L "$out" ] || break
    link=$(readlink "$out") || break
    case "$link" in /*) ;; *) link="${out%/*}/$link" ;; esac
    out=$(_guard_canon_walk "$link") || return 1
    hops=$((hops + 1))
  done
  printf '%s\n' "$out"
}

_guard_canon_walk() {
  local p="$1" base="${2:-}"
  # A Windows spelling under Git Bash or Cygwin: C:\proj\scripts\x.sh, \\?\C:\..., C:/proj/...; the
  # walk below splits on `/` only (spec 090 threat model, #6). cygpath ships with both.
  if [ "$GUARD_NTFS" -eq 1 ]; then
    case "$p" in *\\*) p=${p//\\//} ;; esac
    case "$p" in //\?/*|//./*) p=${p#//?/} ;; esac
    case "$p" in [A-Za-z]:/*|[A-Za-z]:) command -v cygpath >/dev/null 2>&1 && p=$(cygpath -u -- "$p" 2>/dev/null || printf '%s' "$p") ;; esac
  fi
  case "$p" in
    /*) ;;
    *)  if [ -z "$base" ]; then base=$(guard_field .cwd 2>/dev/null) || base=""; fi
        [ -n "$base" ] || base="$PWD"
        p="$base/$p" ;;
  esac
  # `.` and `..` are resolved AS TEXT first, because that is what the CLI's Write/Edit do before they
  # open the file (/security-review, spec 083): `<proj>/lnk/../src/App.cs` writes <proj>/src/App.cs
  # even when lnk points elsewhere. Walking `..` physically judged a different file than the one
  # written. What is left has no `..`, and its directories are then resolved physically below.
  local seg norm="" IFS_SAVE="$IFS"
  set -f; IFS=/
  # shellcheck disable=SC2086
  set -- $p
  IFS="$IFS_SAVE"; set +f
  for seg in "$@"; do
    # On NTFS `scripts./x.sh` is scripts/x.sh and `.. ` is `..` (spec 090 R1): trimmed before `.` and
    # `..` are read. Elsewhere a trailing dot is part of a real name.
    if [ "$GUARD_NTFS" -eq 1 ] && [ -n "$seg" ]; then _guard_ntfs_trim "$seg"; seg=$GUARD_TRIMMED; fi
    case "$seg" in
      ''|.) ;;
      ..)   norm="${norm%/*}" ;;
      *)    norm="$norm/$seg" ;;
    esac
  done
  p="${norm:-/}"
  local dir="${p%/*}" name="${p##*/}"
  [ -n "$dir" ] || dir="/"
  (
    set -f
    cd -P / 2>/dev/null || exit 1
    tail=""
    IFS=/
    # shellcheck disable=SC2086
    set -- $dir
    unset IFS
    for seg in "$@"; do
      if [ -z "$tail" ]; then
        case "$seg" in
          ''|.) continue ;;
          ..)   cd -P .. 2>/dev/null; continue ;;
        esac
        if [ -d "$seg" ] && cd -P -- "$seg" 2>/dev/null; then continue; fi
      fi
      tail="$tail/$seg"
    done
    out=$(_guard_pwd)
    [ "$out" = "/" ] && out=""
    # Every directory existed, so the name is an entry here: take its stored spelling (R1).
    if [ -z "$tail" ]; then
      case "$name" in ''|.|..) ;; *) _guard_stored_name "$name"; name=$GUARD_STORED; set -f ;; esac
    fi
    IFS=/
    # shellcheck disable=SC2086
    set -- $tail "$name"
    unset IFS
    for seg in "$@"; do
      case "$seg" in
        ''|.) ;;
        ..)   out="${out%/*}" ;;
        *)    out="$out/$seg" ;;
      esac
    done
    printf '%s\n' "${out:-/}"
  )
}

# ------------------------------------------------------------------ the root walk's anchor
# guard_anchor_for <canonical-file>, then guard_git_boundary <dir> in the walk (spec 088 R1, F090).
#
# The five Edit-path guards find "the project" by walking up from the edited file to the first .git.
# A .git is a plain file write with no source extension, so nothing stopped the gated agent from
# planting one: an empty src/app/.git made src/app the root, with no register and no language marker,
# and src/app/main.py was allowed. scripts/.git made a CORE script non-CORE the same way.
#
# The harness hands every hook CLAUDE_PROJECT_DIR, and the agent cannot change a hook's environment.
# So when the edited file lies inside that directory, no .git strictly below it is a boundary: the
# walk passes through and stops at the anchor or above it, where the project's real .git is. A nested
# repo or a submodule below the anchor is gated by the project's register (developer, 088 O1).
# A file outside the anchor, and a run with no usable CLAUDE_PROJECT_DIR (a self-test, an older
# harness), walk exactly as before. Residual: a session started in a subdirectory, where a .git
# planted in that start directory is AT the anchor and still ends the walk.
#
# Two exceptions, both from the 088 adversarial review:
#   * a LINKED WORKTREE below the anchor is still a root. `git worktree add .claude/worktrees/w` makes a
#     full checkout with its own register; ignoring its .git made every file in it a <root>/.claude/**
#     path, which guard_root_exempt lets through. It is recognised by the link git keeps both ways: the
#     .git file says `gitdir: <common>/worktrees/<n>`, and that directory's `gitdir` file names this
#     .git back. A planted file has no such back-link (writing one means writing inside .git/, which
#     trust-anchor-guard denies).
#   * on a case-insensitive file system (macOS, Windows) /users/x/proj/src/main.py is the anchor's file,
#     so the comparison folds case there. Since spec 090 both sides are stored names (R1), which also
#     settles Unicode normalisation; the fold stays as a second layer.
#
# Spec 090 adds two more, both decided by the developer or found reproduced:
#   * a .git AT the anchor, when a directory above the anchor also holds one (a session started in a
#     subdirectory), is a boundary only when it is a repository with a commit whose top level is the
#     anchor (R6, developer O1). An empty file, an empty directory and a fresh `git init` are not, and
#     the walk goes on to the project. With no .git above, nothing changes and git is not run.
#   * a linked worktree is a root of kind `worktree` (GUARD_BOUNDARY_KIND). guard_walk takes a register
#     or language marker the worktree lacks from above it (R7, F106, F122): a `--no-checkout` worktree,
#     or one at a commit before the register existed, has neither, and it allowed every edit.
GUARD_ANCHOR=""
GUARD_BOUNDARY_KIND=""

_guard_realdir() { CDPATH='' cd -P -- "$1" 2>/dev/null && _guard_pwd; }   # call as $(_guard_realdir d)

# _guard_under <path> <dir>: 0 when path lies strictly below dir, case-folded where the file system
# folds. Builtins only: this runs on every Edit.
_guard_under() { _guard_fold_match "$1" "$2" under; }

# _guard_fold_match <string> <dir> under|is: below <dir>, or <dir> itself, case-folded where the file
# system folds; the caller's nocasematch is left as it was.
_guard_fold_match() {
  local rc=1 was=0
  shopt -q nocasematch && was=1
  [ "$GUARD_ANCHOR_FOLD" -eq 1 ] && shopt -s nocasematch
  case "$3" in
    under) [[ $1 == "$2"/* ]] && rc=0 ;;
    *)     [[ $1 == "$2" ]] && rc=0 ;;
  esac
  [ "$was" -eq 1 ] || shopt -u nocasematch
  return $rc
}

# _guard_gitdir_of <dir>: GUARD_GITDIR = the target of <dir>/.git's `gitdir:` line, made absolute.
# Exit 1 when <dir>/.git is not such a file. Builtins only.
_guard_gitdir_of() {
  local line
  GUARD_GITDIR=""
  IFS= read -r line < "$1/.git" 2>/dev/null || return 1
  case "$line" in "gitdir: "*) GUARD_GITDIR="${line#gitdir: }" ;; *) return 1 ;; esac
  case "$GUARD_GITDIR" in /*) ;; *) GUARD_GITDIR="$1/$GUARD_GITDIR" ;; esac
}

guard_anchor_for() {
  GUARD_ANCHOR=""
  GUARD_GIT_UNSURE=""                   # both walks start here (spec 098 R4)
  local a="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$a" ] || return 0
  a=$(_guard_realdir "$a") || return 0
  [ "$a" = "/" ] && return 0   # mutant-equivalent: every caller ignores the return code; GUARD_ANCHOR stays ""
  _guard_under "$1" "$a" && GUARD_ANCHOR="$a"
  return 0
}

# _guard_git <args…>: git for the root walk (spec 098 R4, F142). The output lands in GUARD_GIT_OUT and
# git's own exit code is returned: 128 "not a repository" is an answer. Not an answer: no git on PATH,
# nothing to bound the call with, or no reply within GUARD_GIT_TIMEOUT seconds (default 5). Each of
# those sets GUARD_GIT_UNSURE to the cause and returns 125, so the walk reads "not a worktree" as before
# but the guard knows its root is a guess (developer O3: pipeline guards deny, CORE guards announce).
# Called directly, never inside $( ): the flag has to reach the caller's shell. Every GIT_ variable is
# dropped, as in acceptance_cases._git_env (spec 095 R5).
_guard_git() {
  local to rc
  GUARD_GIT_OUT=""
  command -v git >/dev/null 2>&1 || { GUARD_GIT_UNSURE="git is not on PATH"; return 125; }
  if [ -z "${_GUARD_GIT_TO:-}" ]; then              # chosen once per process
    if command -v timeout >/dev/null 2>&1; then _GUARD_GIT_TO=timeout
    elif command -v gtimeout >/dev/null 2>&1; then _GUARD_GIT_TO=gtimeout
    elif command -v perl >/dev/null 2>&1; then _GUARD_GIT_TO=perl
    else GUARD_GIT_UNSURE="neither timeout, gtimeout nor perl is on PATH to bound git"; return 125; fi
  fi
  to=$_GUARD_GIT_TO
  GUARD_GIT_OUT=$(
    for _v in $(compgen -e -X '!GIT_*'); do unset "$_v"; done
    if [ "$to" = perl ]; then perl -e 'alarm shift; exec @ARGV' "${GUARD_GIT_TIMEOUT:-5}" git "$@" 2>/dev/null
    else "$to" "${GUARD_GIT_TIMEOUT:-5}" git "$@" 2>/dev/null; fi
    rc=$?; printf x; exit $rc)
  rc=$?
  GUARD_GIT_OUT=${GUARD_GIT_OUT%x}
  # 124: timeout/gtimeout ran out. 142: perl's alarm (SIGALRM). 137: timeout's own KILL.
  case "$rc" in
    124|137|142) GUARD_GIT_UNSURE="git did not answer within ${GUARD_GIT_TIMEOUT:-5}s"; return 125 ;;
  esac
  return "$rc"
}

_guard_linked_worktree() {   # $1 = dir whose .git is a file
  local line target back common
  [ -f "$1/.git" ] || return 1
  _guard_gitdir_of "$1" || return 1
  target=$GUARD_GITDIR
  # The link must point into THIS project's own git dir, at <common>/worktrees/<one name>: a back-link
  # placed anywhere else (`git init --separate-git-dir=/tmp/worktrees/x`) is no worktree of ours
  # (/security-review, spec 088).
  _guard_git -C "$GUARD_ANCHOR" rev-parse --git-common-dir || return 1
  common=${GUARD_GIT_OUT%$'\n'}
  case "$common" in /*) ;; *) common="$GUARD_ANCHOR/$common" ;; esac
  common=$(_guard_realdir "$common") || return 1
  target=$(_guard_realdir "$target") || return 1
  case "$target" in "$common"/worktrees/*/*) return 1 ;; "$common"/worktrees/*) ;; *) return 1 ;; esac
  IFS= read -r back < "$target/gitdir" 2>/dev/null || return 1
  [ "$(_guard_realdir "${back%/.git}")" = "$(_guard_realdir "$1")" ]
}

# _guard_is <a> <b>: the same directory, case-folded where the file system folds.
_guard_is() { _guard_fold_match "$1" "$2" is; }

# _guard_anchor_git_counts <anchor>: R6 (F105, developer O1). Called only for the anchor's own .git.
_guard_anchor_git_counts() {
  local d="${1%/*}" top
  while [ -n "$d" ]; do
    [ -e "$d/.git" ] && break
    d="${d%/*}"
  done
  [ -n "$d" ] || return 0                       # nothing above: the anchor is the project, as before
  # A symlinked .git (`.git -> ../.git`) is the outer repository under another name (review #9).
  [ -L "$1/.git" ] && return 1
  # A .git FILE that is not a linked worktree of ours (checked by the caller) counts only when its
  # gitdir is a git dir of its own: a submodule or a --separate-git-dir repository the developer
  # started in (review #7). `gitdir: ../.git` names an outer repository's own git dir, a plant that
  # rev-parse accepts (threat model #2).
  if [ -f "$1/.git" ]; then
    local line target up
    _guard_gitdir_of "$1" || return 1
    target=$(_guard_realdir "$GUARD_GITDIR") || return 1
    up="$d"
    while [ -n "$up" ]; do
      [ -d "$up/.git" ] && _guard_is "$target" "$(_guard_realdir "$up/.git")" && return 1
      up="${up%/*}"
    done
  fi
  _guard_git -C "$1" rev-parse --show-toplevel -q --verify HEAD || return 1
  top=${GUARD_GIT_OUT%$'\n'}
  case "$top" in *$'\n'?*) top=${top%%$'\n'*} ;; *) return 1 ;; esac
  _guard_is "$top" "$1"
}

guard_git_boundary() {
  GUARD_BOUNDARY_KIND=root
  [ -e "$1/.git" ] || return 1          # a worktree's .git is a file (spec 083)
  [ -n "$GUARD_ANCHOR" ] || return 0
  if _guard_under "$1" "$GUARD_ANCHOR"; then
    _guard_linked_worktree "$1" || return 1
    GUARD_BOUNDARY_KIND=worktree
    return 0
  fi
  if _guard_is "$1" "$GUARD_ANCHOR"; then
    # A session started inside a linked worktree: the same inheritance as one below the anchor (R7).
    if _guard_linked_worktree "$1"; then GUARD_BOUNDARY_KIND=worktree; return 0; fi
    _guard_anchor_git_counts "$1"
    return
  fi
  return 0
}

# ------------------------------------------------------------------ the pipeline guards' walk
# guard_walk <canonical-file>: the one walk spec-register, pipeline-state and spec-interview share
# (spec 090; each used to carry its own copy). From the file's directory up to the git boundary it
# collects:
#   GUARD_LANG_MARKER   the nearest language marker: is this a code project at all
#   GUARD_REGISTER      the OUTERMOST specs/INDEX.md (spec 083, adversarial #3: a planted nested
#                       register, every row ticked, must not stand in for the real one)
#   GUARD_PROJECT_ROOT  the directory holding that register
#   GUARD_GIT_ROOT      the boundary, where exemptions are anchored
#   GUARD_INHERITED     1 when the register or marker came from above a linked worktree (R7)
# A linked worktree that lacks a register or a marker does not end the collection: the walk goes on
# to the project's own boundary and fills in only what is missing. GUARD_GIT_ROOT stays the worktree,
# so `.claude/worktrees/w/src/x.cs` is judged relative to the worktree and is never a `.claude/**`
# path of the project.
guard_walk() {
  local dir own_reg="" marker
  GUARD_LANG_MARKER=""; GUARD_REGISTER=""; GUARD_PROJECT_ROOT=""; GUARD_GIT_ROOT=""; GUARD_INHERITED=0
  guard_anchor_for "$1"                 # spec 088 R1 (F090): a .git planted below the project is no root
  dir="${1%/*}"; [ -n "$dir" ] || dir="/"
  while [ "$dir" != "/" ]; do
    if [ -z "$GUARD_LANG_MARKER" ]; then
      for marker in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile build.gradle build.gradle.kts pom.xml pubspec.yaml; do
        if [ -f "$dir/$marker" ]; then GUARD_LANG_MARKER="$marker"; break; fi
      done
    fi
    # Builtin stand-in for `ls "$dir"/*.csproj` (spec 073, R9).
    [ -z "$GUARD_LANG_MARKER" ] && _guard_has_match "$dir"/*.csproj && GUARD_LANG_MARKER="*.csproj"
    [ -z "$GUARD_LANG_MARKER" ] && _guard_has_match "$dir"/*.sln && GUARD_LANG_MARKER="*.sln"
    if [ -f "$dir/specs/INDEX.md" ] && { [ "$GUARD_INHERITED" -eq 0 ] || [ -z "$own_reg" ]; }; then
      GUARD_REGISTER="$dir/specs/INDEX.md"; GUARD_PROJECT_ROOT="$dir"
    fi
    if guard_git_boundary "$dir"; then
      # Past an inheriting worktree only the project's own root ends the walk: a worktree nested in a
      # worktree (`.claude/worktrees/w/inner`) is passed through too (adversarial review #1).
      if [ "$GUARD_INHERITED" -eq 1 ]; then
        [ "$GUARD_BOUNDARY_KIND" = worktree ] || break
      else
        GUARD_GIT_ROOT="$dir"
        if [ "$GUARD_BOUNDARY_KIND" = worktree ] && { [ -z "$GUARD_REGISTER" ] || [ -z "$GUARD_LANG_MARKER" ]; }; then
          own_reg="$GUARD_REGISTER"; GUARD_INHERITED=1
        else
          break
        fi
      fi
    fi
    dir="${dir%/*}"; [ -n "$dir" ] || dir="/"
  done
  # Spec 095 R6 (F120). Deleting or renaming the only language marker used to turn all three pipeline
  # guards off. A register, or the sync stamp, at the git root now stands in for the marker, except in
  # the template itself (template-identity.sh: its URL and its root commit; a missing library means a
  # project). Asked about the git root, so a template clone nested in a project does not count.
  if [ -z "$GUARD_LANG_MARKER" ] && [ -n "$GUARD_GIT_ROOT" ] \
     && { [ -n "$GUARD_REGISTER" ] || [ -f "$GUARD_GIT_ROOT/.claude/.template-sync" ]; }; then
    local _gl_id=project
    if . "${BASH_SOURCE[0]%/*}/template-identity.sh" 2>/dev/null; then
      _gl_id=$(template_identity "$GUARD_GIT_ROOT")
    fi
    if [ "$_gl_id" != template ]; then
      if [ -n "$GUARD_REGISTER" ]; then GUARD_LANG_MARKER="specs/INDEX.md"; else GUARD_LANG_MARKER=".claude/.template-sync"; fi
    fi
  fi
  return 0
}

_guard_has_match() { local f; for f in "$@"; do { [ -e "$f" ] || [ -L "$f" ]; } && return 0; done; return 1; }

# guard_core_synced <sync-root> <hook-dir>: 0 when the root shows it was synced from the template: the
# stamp, a register, or the running hook installed in its scripts/ (spec 098 R3, threat model #4).
guard_core_synced() {
  [ -f "$1/.claude/.template-sync" ] || [ -f "$1/specs/INDEX.md" ] || [ "$2" -ef "$1/scripts" ]
}

# guard_unsure_deny <guard>: spec 098 R4 (F142, developer O3) for the three pipeline guards. When the
# walk needed git and git could not answer, the root (and every exemption anchored at it) is a guess,
# so the guard denies before its exemptions. Prints the deny and returns 0; returns 1 when the walk
# was sure. The CORE guards announce instead (guard_announce), keyed by file (threat model #7).
guard_unsure_deny() {
  [ -n "${GUARD_GIT_UNSURE:-}" ] || return 1
  guard_deny "BLOCKED — $1 could not find this project's root: $GUARD_GIT_UNSURE (spec 098).

The walk from the edited file up to the git root asks git whether a .git file is a linked worktree of this project, or whether the session's own .git is the real one. Without an answer the root, and the scripts/ specs/ .claude/ exemptions anchored at it, would be a guess. Put git on PATH or make it answer (GUARD_GIT_TIMEOUT, default 5 s), then retry. This is not something an edit can fix."
  return 0
}

# guard_core_root <canonical-file>: the two roots the CORE guards need (spec 090, adversarial #1).
#   GUARD_CORE_ROOT  the boundary the file is relative to (REL for --is-core)
#   GUARD_SYNC_ROOT  the root whose .claude/ and scripts/template-autosync.sh decide
# They are the same directory except for a linked worktree that has no sync of its own (made with
# --no-checkout, or at a commit that predates the sync): its scripts/<core>.sh is still CORE, judged by
# the project's sync above it.
guard_core_root() {
  local dir="${1%/*}"
  GUARD_CORE_ROOT=""; GUARD_SYNC_ROOT=""
  guard_anchor_for "$1"
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    if guard_git_boundary "$dir"; then
      [ -n "$GUARD_CORE_ROOT" ] || GUARD_CORE_ROOT="$dir"
      # A worktree with no sync of its own, nested or not, defers to the next root up (review #1).
      if [ "$GUARD_BOUNDARY_KIND" = worktree ] && { [ ! -d "$dir/.claude" ] || [ ! -f "$dir/scripts/template-autosync.sh" ]; }; then
        dir="${dir%/*}"; continue
      fi
      GUARD_SYNC_ROOT="$dir"; break
    fi
    dir="${dir%/*}"
  done
  [ -n "$GUARD_SYNC_ROOT" ] || GUARD_SYNC_ROOT="$GUARD_CORE_ROOT"
}

# guard_walk_exempt <canonical-file>: the directory allow list of spec 083 R5, anchored at the git root
# and, for a monorepo whose register sits in a package directory below it, at that directory too. A
# register inherited from ABOVE a worktree (R7) anchors nothing: that is the project's root, and the
# worktree's files are not its tooling.
guard_walk_exempt() {
  guard_root_exempt "${1#"$GUARD_GIT_ROOT"/}" && return 0
  case "$GUARD_PROJECT_ROOT" in
    "$GUARD_GIT_ROOT"/*) guard_root_exempt "${1#"$GUARD_PROJECT_ROOT"/}" && return 0 ;;
  esac
  return 1
}

# ------------------------------------------------------------------ root-anchored exemptions
# guard_root_exempt <relative-path>: 0 when the path is under one of the four tooling directories AT
# THE ROOT it is relative to (spec 083 R5, F041). The pipeline guards never block their own repair
# path — every one of them is a file under scripts/ — but "contains /scripts/" was never that.
guard_root_exempt() {
  case "$1" in
    scripts/*|specs/*|.specify/*|.claude/*) return 0 ;;
  esac
  return 1
}

# guard_name_exempt <absolute-path>: 0 for the extension-less names the pipeline guards always let
# through, matched on the whole basename. Exact names only (adversarial review #15): `README*` and
# `.env.*` also matched README.sh and .env.ts, which are source. A README.md or .env.local needs no
# entry here — its extension is not a source extension, and the extension test lets it through.
guard_name_exempt() {
  case "${1##*/}" in
    CLAUDE.md|CLAUDE.local.md|README|LICENSE|CHANGELOG) return 0 ;;
    .gitignore|.env|.editorconfig|.gitattributes|Dockerfile|.dockerignore) return 0 ;;
  esac
  return 1
}
