#!/bin/bash
# workload-placement.sh — where a maintenance job runs: on this machine or in Claude cloud (row 075).
#
# WHY THIS EXISTS. Row 074 measured every heavy job; nothing read the numbers, so Stryker kept
# running on the laptop. The decision now lives in a table, and this is the only reader of it, so
# project-maintenance.sh (which job to run) and maintenance-due.sh (what to tell the developer)
# cannot disagree about a job's place.
#
# The table: scripts/workload-placement.tsv ships with the template (CORE). A project overrides it
# line by line in .claude/workload-placement.tsv, which sync never touches. One line per job:
#   job<TAB>place<TAB>reason        place is `local` or `cloud`; `#` starts a comment
# A job with no line is local. A place that is neither is an error, never a quiet `local`: a typo
# must not keep Stryker on the laptop forever, nor skip it everywhere.
#
# Usage:
#   bash scripts/workload-placement.sh --place JOB   # prints local|cloud; exit 3 on an unknown place
#   bash scripts/workload-placement.sh --here        # prints cloud when CLAUDE_CODE_REMOTE=true, else local
#   bash scripts/workload-placement.sh --list        # job<TAB>place<TAB>source, the effective table
#
# Exit: 0 ok · 2 usage · 3 the table names a place that is neither local nor cloud.
# WORKLOAD_PLACEMENT_ROOT overrides the repository root (tests).
# bash 3.2-safe (macOS system bash), no python: Git Bash on Windows reads it too.

set -u

ROOT="${WORKLOAD_PLACEMENT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TEMPLATE_TABLE="$ROOT/scripts/workload-placement.tsv"
PROJECT_TABLE="$ROOT/.claude/workload-placement.tsv"

usage() {
  awk '/^# Usage:/ {on=1; next} on && /^#   / {sub(/^# +/, "  "); print; next} on {exit}' "$0" >&2
  exit 2
}

# lines FILE SOURCE — the file's job lines as job<TAB>place<TAB>source, comments and blanks dropped.
# CR is stripped: a table saved on Windows must not turn `cloud` into `cloud\r`, an unknown place.
lines() {
  [ -f "$1" ] || return 0
  tr -d '\r' < "$1" | awk -F'\t' -v src="$2" '
    /^[[:space:]]*(#|$)/ { next }
    { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      if ($1 != "") print $1 "\t" $2 "\t" src }'
}

# The effective table: the project's line for a job wins over the template's.
effective() {
  { lines "$PROJECT_TABLE" project; lines "$TEMPLATE_TABLE" template; } | awk -F'\t' '!seen[$1]++'
}

case "${1:-}" in
  --here)
    [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && echo cloud || echo local
    ;;
  --list)
    effective
    ;;
  --place)
    [ -n "${2:-}" ] || usage
    LINE=$(effective | awk -F'\t' -v j="$2" '$1 == j' | head -1)
    if [ -z "$LINE" ]; then echo local; exit 0; fi
    PLACE=$(printf '%s' "$LINE" | cut -f2)
    case "$PLACE" in
      local|cloud) echo "$PLACE" ;;
      *)
        SRC=$(printf '%s' "$LINE" | cut -f3)
        [ "$SRC" = project ] && FILE=".claude/workload-placement.tsv" || FILE="scripts/workload-placement.tsv"
        echo "workload-placement: job '$2' has place '$PLACE' in $FILE — expected local or cloud" >&2
        exit 3 ;;
    esac
    ;;
  *) usage ;;
esac
