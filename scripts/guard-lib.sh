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
# Callers set INPUT to the raw payload before calling guard_field without a second argument.

# hook-notice.sh owns the per-session "say this once" state; reused, not copied.
_GUARD_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
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
guard_announce() {
  local guard="$1" cause="$2" sid text
  text="$guard could not decide and ALLOWED this call: $cause. It fails open by design (see its header), so this edit or command was not checked by it. Fix the cause to restore the check."
  sid=""
  if command -v hn_session_id >/dev/null 2>&1; then sid=$(hn_session_id "${INPUT:-}"); fi
  if command -v hn_first_time >/dev/null 2>&1 && [ -n "$sid" ]; then
    hn_first_time "$sid" "guard-announce:$guard:$cause" || return 0
  fi
  guard_context "$text"
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

# ------------------------------------------------------------------ canonical paths
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
  while [ -L "$out" ] && [ "$hops" -lt 8 ]; do
    link=$(readlink "$out") || break
    case "$link" in /*) ;; *) link="${out%/*}/$link" ;; esac
    out=$(_guard_canon_walk "$link") || return 1
    hops=$((hops + 1))
  done
  printf '%s\n' "$out"
}

_guard_canon_walk() {
  local p="$1" base="${2:-}"
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
    out=$(pwd -P)
    [ "$out" = "/" ] && out=""
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
