#!/bin/bash
# SessionStart hook: say that a template sync committed to this branch and nobody
# has checked whether the project still passes.
#
# Why this exists (spec 007at). The sync rewrites a project's enforcement machinery
# unattended, commits it, pushes it, and classifies its own run from an exit code
# that means "the copy loop finished" and knows nothing about the project. It has
# done real damage twice: 0a30a77 took seven of spec 007ak's tests red and the next
# spec ran a full pipeline on top of them and reported green; 5d9234b reverted spec
# 007as and pushed seven red tests to origin/main under "3 updated, 0 added".
#
# The sync cannot run the suite itself — it is bounded at 120 s from a hook whose
# whole contract is that a template problem never blocks a session from starting,
# and msroute's unit suite alone is 46 s warm. So the sync records an obligation and
# this hook keeps reporting it until scripts/template-sync-verify.sh discharges it.
#
# Deliberately NOT rate-limited, unlike template-autosync-hook.sh. That one does
# network I/O and a two-minute sync; this one does a stat and a small read. And
# once-per-six-hours is the failure being fixed: 0a30a77 DID announce itself, once,
# at a session start, and the spec that followed shipped over it anyway. Speaking
# every time is the entire difference between a notification and an obligation.
#
# Executes nothing. The declared command is run only by template-sync-verify.sh, on
# an explicit human invocation — an unattended hook that executes a command string
# read out of a repository file is a trust boundary this spec does not cross.
#
# Fails open on every path: a bookkeeping problem must never stop a session.

set -u

[ "${CLAUDE_TEMPLATE_SYNC_VERIFY_REMINDER:-1}" = "0" ] && exit 0

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  # A directory, not merely a path: a git worktree's .git is a FILE, and a marker
  # path built inside one would be a hook inventing news of a shape nobody tested.
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || exit 0

MARKER="$PROJECT_ROOT/.git/template-sync-unverified"
[ -f "$MARKER" ] || exit 0
[ -r "$MARKER" ] || exit 0

field() { sed -n "s/^$1=//p" "$MARKER" 2>/dev/null | head -1; }

COMMIT=$(field commit)
COMMITS=$(field commits)
TEMPLATE=$(field template)
SYNCED=$(field synced)
PUSHED=$(field pushed)
RESULT=$(field result)
FAILED_AT=$(field failed)
EXIT_CODE=$(field exit)

# A marker with no commit in it is a marker this hook does not understand. Saying
# nothing is the conservative answer; a half-parsed reminder is worse than none.
[ -n "$COMMIT" ] || exit 0

N=$(printf '%s\n' $COMMITS | grep -c . 2>/dev/null)
[ "${N:-0}" -gt 0 ] || N=1

# The file list is what makes the reminder actionable rather than merely alarming —
# "your enforcement machinery moved" reads very differently from "a doc moved". Bounded
# for the same reason the sync's [changed] block is: this text is forwarded verbatim
# into a session's context, and enforcement comes first there for the same reason.
FILES=$(sed -n 's/^file //p' "$MARKER" 2>/dev/null \
  | awk '{ if ($0 == ".claude/settings.json") r = 0
           else if ($0 ~ /^\.claude\/rules\//) r = 1
           else if ($0 ~ /^scripts\//)         r = 2
           else                                r = 3
           printf "%d\t%s\n", r, $0 }' \
  | LC_ALL=C sort -t"$(printf '\t')" -k1,1n -k2,2 | cut -f2)
N_FILES=$(printf '%s\n' "$FILES" | grep -c .)
FILE_LINES=$(printf '%s\n' "$FILES" | head -8 | sed 's/^/  /')
[ "${N_FILES:-0}" -gt 8 ] && FILE_LINES="$FILE_LINES
  … and $((N_FILES - 8)) more"

COMMAND=""
DECL="$PROJECT_ROOT/.claude/.template-sync-verify"
[ -r "$DECL" ] && COMMAND=$(grep -v '^[[:space:]]*#' "$DECL" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)

if [ "$N" -eq 1 ]; then
  HEAD_LINE="A template sync committed to this branch and nothing has checked the project since."
else
  HEAD_LINE="$N template syncs have committed to this branch and nothing has checked the project since."
fi

BODY="$HEAD_LINE
  $COMMIT — template ${TEMPLATE:-unknown}, $([ "$PUSHED" = yes ] && echo pushed || echo "not pushed"), ${SYNCED:-unknown}"
[ "$N" -gt 1 ] && BODY="$BODY
  all outstanding: $COMMITS"
[ -n "$FILES" ] && BODY="$BODY
what it rewrote:
$FILE_LINES"

if [ "$RESULT" = "failed" ]; then
  TAIL=$(sed -n 's/^tail //p' "$MARKER" 2>/dev/null | sed 's/^/  /')
  BODY="$BODY
Verification has already FAILED here — exit ${EXIT_CODE:-?} at ${FAILED_AT:-unknown}:
$TAIL
This branch is known bad, not merely unchecked. Fix it before building on it."
else
  BODY="$BODY
Nobody has run the project's own regression command against it yet."
fi

if [ -n "$COMMAND" ]; then
  BODY="$BODY
Run: scripts/template-sync-verify.sh   ($COMMAND)"
else
  BODY="$BODY
This project declares no regression command. Put one in .claude/.template-sync-verify
(first non-comment line), then run scripts/template-sync-verify.sh."
fi

# Same escaping as template-autosync-hook.sh: quotes, then newlines to \n. jq is not
# assumed present — this hook must work on a machine that has nothing installed.
MSG=$(printf '%s' "$BODY" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/$/\\n/' | tr -d '\n')
printf '{"systemMessage": "%s"}\n' "$MSG"
exit 0
