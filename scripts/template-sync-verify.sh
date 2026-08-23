#!/bin/bash
# Discharge the obligation a template sync left behind (spec 007at).
#
# The sync rewrites a project's enforcement machinery at SessionStart, commits it and
# pushes it. It cannot check the project afterwards: it is bounded at 120 s by a hook
# whose contract is that a template problem never blocks a session from starting, and a
# real regression suite is tens of seconds even warm. So it writes what it did not check
# to .git/template-sync-unverified, and this is the thing that checks it.
#
# This is the ONLY place the project's declared command is ever executed, and it runs
# only when a human types it. The sync and both SessionStart hooks read the marker and
# never run anything — the declaration is a command string in a repository file, and
# unattended machinery has no business executing one.
#
#   scripts/template-sync-verify.sh
#
#   exit 0  verified (or nothing outstanding)  ·  1  the command failed  ·  3  no
#   declaration  ·  2  usage
#
# Declare the command in .claude/.template-sync-verify — first line that is neither
# blank nor a # comment. It should be the project's real regression suite, and NOT a
# filter narrowed to whatever class you are thinking about today: spec 007an shipped
# over seven red tests precisely because its filtered runs never selected the class
# they were in.

set -u

TAIL_LINES="${TEMPLATE_SYNC_VERIFY_TAIL:-20}"
case "$TAIL_LINES" in ''|*[!0-9]*) TAIL_LINES=20 ;; esac
HISTORY_LINES=20

case "${1:-}" in
  -h|--help)
    # Everything from the shebang to the first non-comment line. A hard line range drifts
    # the first time the header is edited, and the drift is silent.
    awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  "") ;;
  *)
    printf 'template-sync-verify: unknown argument %s (try --help)\n' "$1" >&2
    exit 2 ;;
esac

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
if [ -z "$PROJECT_ROOT" ]; then
  printf 'template-sync-verify: not inside a git repository.\n'
  exit 0
fi

MARKER="$PROJECT_ROOT/.git/template-sync-unverified"
HISTORY="$PROJECT_ROOT/.git/template-sync-verified"
DECL="$PROJECT_ROOT/.claude/.template-sync-verify"

# Nothing outstanding runs nothing. A verify that burns the suite whether or not there
# is anything to check is a verify people stop running, and this one is worth running.
if [ ! -f "$MARKER" ]; then
  printf 'nothing to verify: no template-sync commit is outstanding on this branch.\n'
  if [ -f "$HISTORY" ]; then
    printf 'last verified: %s\n' "$(tail -1 "$HISTORY")"
  fi
  exit 0
fi

field() { sed -n "s/^$1=//p" "$MARKER" 2>/dev/null | head -1; }
COMMIT=$(field commit)
COMMITS=$(field commits)
TEMPLATE=$(field template)
SYNCED=$(field synced)
PUSHED=$(field pushed)

COMMAND=""
[ -r "$DECL" ] && COMMAND=$(grep -v '^[[:space:]]*#' "$DECL" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)

if [ -z "$COMMAND" ]; then
  printf 'This project declares no regression command, so there is nothing to run.\n\n'
  printf 'Outstanding: %s (template %s, %s)\n\n' \
    "${COMMIT:-unknown}" "${TEMPLATE:-unknown}" "${SYNCED:-unknown}"
  printf 'Create .claude/.template-sync-verify with one line — the command that proves\n'
  printf 'this project still works. For a .NET project that is usually its unit suite:\n\n'
  printf '    dotnet test tests/<Project>.Tests.Unit/<Project>.Tests.Unit.csproj\n\n'
  printf 'Then run this script again. The obligation stands until something checks it.\n'
  exit 3
fi

printf 'Verifying %s (template %s, synced %s, %s)\n' \
  "${COMMIT:-unknown}" "${TEMPLATE:-unknown}" "${SYNCED:-unknown}" \
  "$([ "$PUSHED" = yes ] && echo 'already pushed' || echo 'not pushed')"
printf '  %s\n\n' "$COMMAND"

LOG=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/template-sync-verify.$$")

# Streamed, not captured. A suite that prints nothing for a minute cannot be told from a
# hang, and the first thing anyone does about that is stop running it. The tee keeps a
# copy only so the marker can carry a tail.
( cd "$PROJECT_ROOT" && sh -c "$COMMAND" 2>&1 ) | tee "$LOG"
RC=${PIPESTATUS[0]}

NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if [ "$RC" -eq 0 ]; then
  rm -f "$MARKER"
  # Every outstanding SHA, not just the newest. One run of the suite verifies the tree as it
  # stands, which is all of them — and a history line naming one of three is the same kind of
  # partial truth this whole mechanism exists to stop.
  printf '%s verified %s (template %s) — %s\n' \
    "$NOW" "${COMMITS:-${COMMIT:-unknown}}" "${TEMPLATE:-unknown}" "$COMMAND" >> "$HISTORY"
  # Bounded: this file answers "when was this branch last checked", which needs the last
  # few entries and never the first ones.
  if [ "$(grep -c . "$HISTORY" 2>/dev/null)" -gt "$HISTORY_LINES" ]; then
    tail -n "$HISTORY_LINES" "$HISTORY" > "$HISTORY.tmp" 2>/dev/null && mv -f "$HISTORY.tmp" "$HISTORY"
  fi
  N_DISCHARGED=$(printf '%s\n' $COMMITS | grep -c .)
  if [ "${N_DISCHARGED:-1}" -gt 1 ]; then
    printf '\nverified %s — %s outstanding sync commits discharged.\n' "$COMMITS" "$N_DISCHARGED"
  else
    printf '\nverified %s — the obligation is discharged.\n' "${COMMIT:-unknown}"
  fi
  rm -f "$LOG"
  exit 0
fi

# Failed. The obligation is not merely renewed, it is upgraded: the branch is now known
# bad rather than unchecked, and the reminder says so in those words from here on.
{
  printf '# Template sync commits this branch has not been verified against (spec 007at).\n'
  printf '# Written by scripts/template-autosync.sh · discharged by scripts/template-sync-verify.sh\n'
  printf 'commit=%s\n' "$COMMIT"
  printf 'commits=%s\n' "$COMMITS"
  printf 'template=%s\n' "$TEMPLATE"
  printf 'synced=%s\n' "$SYNCED"
  printf 'pushed=%s\n' "$PUSHED"
  printf 'result=failed\n'
  # The command's OWN exit code, kept rather than flattened into this script's 1: it is the
  # first thing anyone reading the marker wants, and a test runner's code carries meaning
  # that the word "failed" does not.
  printf 'exit=%s\n' "$RC"
  printf 'failed=%s\n' "$NOW"
  # Bounded at the END. The last lines are where a runner puts its verdict; a head-bounded
  # tail would faithfully record twenty lines of build chatter.
  tail -n "$TAIL_LINES" "$LOG" 2>/dev/null | tr -d '\r' | sed 's/^/tail /'
  grep '^file ' "$MARKER" 2>/dev/null
} > "$MARKER.tmp" 2>/dev/null && mv -f "$MARKER.tmp" "$MARKER"

rm -f "$LOG"
printf '\nverification FAILED (exit %s) for %s.\n' "$RC" "${COMMIT:-unknown}"
printf 'The obligation stands and now reads "failed" — every session start will say so\n'
printf 'until the project passes again.\n'
exit 1
