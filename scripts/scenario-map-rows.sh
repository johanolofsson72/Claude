#!/bin/sh
# scenario-map-rows.sh — extract the scenario ledger from a map, in a stable, diffable form.
#
# WHY: spec 007bl moves 188 rows out of specs/SCENARIOS.md into per-feature files under
# specs/scenarios/. The claim is "a move, not an edit". That claim is not eyeballable across
# 188 rows, so it is checked mechanically: snapshot before, extract after, diff. This script
# is both halves of that, and scripts/test-scenario-map-split.sh is the gate around it.
#
# OUTPUT: one line per row, sorted by id, pipe-separated:
#     id|kind|scenario|expected_outcome|status|struck
# where `struck` is 1 for a retired row (written ~~SC-NNN~~ in the map) and 0 otherwise.
# The id is emitted WITHOUT the strikethrough markers so ids sort and compare naturally;
# the strike survives as its own field, because losing it would free a reserved id.
#
# THREE TRAPS THIS SCRIPT EXISTS TO AVOID. The first two were found while scoping 007bl; the
# third was found by the gate refusing a real map on 2026-08-28:
#
#   1. The obvious pattern '^\| SC-' misses every retired row, because those are written
#      `| ~~SC-033~~ |`. Extracting with it yields 185 and looks correct. All three rows it
#      drops are precisely the ones whose ids must never be reused (.claude/rules/scenarios.md
#      forbids reuse), so a check built on it would certify exactly the loss that matters most.
#      Hence the (~~)? in the row pattern below, and the struck field.
#
#   2. A naive `SC-[0-9]+` grep over the repo counts one id too many: a map row quotes a
#      shellcheck code that looks like an id while explaining it must not be read as one.
#      This script never greps for bare ids — it only reads five-column table rows whose first
#      cell IS an id — so prose mentions, flowchart references and comments cannot inflate the
#      count. That is the whole reason extraction is anchored to the table rather than the text.
#
#   3. FS = "|" splits a markdown-escaped pipe. GFM writes a literal pipe inside a cell as \|
#      and renders it as text, not as a column break — so a row whose scenario text quotes one
#      arrives at awk with six cells and is rejected as malformed. agentcrm's SC-436 does exactly
#      that (a formula-injection payload beginning `=cmd\|`), and one such row took the whole
#      traceability gate down for a 482-row map: the guard reports the row and exits 2, so nothing
#      downstream got a single scenario out of a file that was never malformed. Adversarial rows
#      are where the payloads live, so this will keep happening. See the rejoin loop below.
#
# The map's rows are uniform: exactly five columns, none wrapped across lines. If that ever stops
# being true this script reports it rather than silently emitting a short row — see the
# column-count guard. An escaped pipe is NOT a shape change and no longer trips that guard.
#
# USAGE:
#   scripts/scenario-map-rows.sh specs/SCENARIOS.md
#   scripts/scenario-map-rows.sh specs/SCENARIOS.md specs/scenarios/*.md
#   scripts/scenario-map-rows.sh --summary specs/SCENARIOS.md      # counts, not rows
#
# EXIT: 0 extracted cleanly · 1 no readable input · 2 a malformed row was found.

set -eu

SUMMARY=0
if [ "${1:-}" = "--summary" ]; then
  SUMMARY=1
  shift
fi

if [ "$#" -eq 0 ]; then
  echo "usage: $0 [--summary] <map-file> [more-files...]" >&2
  exit 1
fi

READABLE=0
for f in "$@"; do
  [ -f "$f" ] && READABLE=$((READABLE + 1))
done
if [ "$READABLE" -eq 0 ]; then
  echo "scenario-map-rows: no readable input among: $*" >&2
  exit 1
fi

# awk does the parsing so the cell splitting is one implementation, not one per call site.
# A row is: leading '|', optional '~~', SC-<digits>. Everything else in the file is ignored,
# including flowchart node labels that name an SC-id and prose that quotes one.
EXTRACT='
  BEGIN { FS = "|"; bad = 0 }

  /^[[:space:]]*\|[[:space:]]*(~~)?SC-[0-9]+/ {
    # Rejoin the cells FS cut apart at an escaped pipe (trap 3). A field ending in an ODD
    # number of backslashes was cut mid-cell: the last one escapes the delimiter. An even
    # number is literal backslashes standing in front of a real column break, so the count
    # is what distinguishes them — a bare /\\$/ test would join the second case wrongly.
    # The pipe is put back in its ESCAPED form, so a restored cell still contains no bare
    # delimiter: this script emits pipe-separated rows, and every caller splits them on "|".
    # Unescaping here would shift status and struck into the wrong fields for exactly the
    # rows this rejoin exists to rescue — a fix that reads as a fix and corrupts silently.
    n = 0
    cur = $1
    for (i = 2; i <= NF; i++) {
      if (odd_backslashes(cur)) cur = cur "|" $i
      else { cell[++n] = cur; cur = $i }
    }
    cell[++n] = cur

    # n-2 is the cell count: FS on a full-width markdown row yields an empty first and
    # last field. The map is uniformly five columns; anything else is a shape change this
    # script must not paper over.
    if (n - 2 != 5) {
      printf "scenario-map-rows: %s:%d has %d columns, expected 5: %s\n", FILENAME, FNR, n - 2, $0 > "/dev/stderr"
      bad = 1
      next
    }

    id       = trim(cell[2])
    kind     = trim(cell[3])
    scenario = trim(cell[4])
    expected = trim(cell[5])
    status   = trim(cell[6])

    struck = 0
    if (id ~ /^~~.*~~$/) {
      struck = 1
      sub(/^~~/, "", id)
      sub(/~~$/, "", id)
    }

    # Collapse internal whitespace runs so a reflowed cell (same words, different padding)
    # is not reported as a changed row. The move copies rows verbatim, but a future editor
    # reformatting a table should not read as scenario loss.
    scenario = squeeze(scenario)
    expected = squeeze(expected)
    status   = squeeze(status)
    kind     = squeeze(kind)

    printf "%s|%s|%s|%s|%s|%d\n", id, kind, scenario, expected, status, struck
  }

  END { if (bad) exit 2 }

  # The trailing run of backslashes, isolated by deleting everything up to the last character
  # that is not one. A string that is ALL backslashes matches nothing and is left whole, which
  # is the case a greedy /.*\\/ strip would get wrong.
  function odd_backslashes(s,   t) {
    t = s
    sub(/^.*[^\\]/, "", t)
    return (length(t) % 2) == 1
  }

  function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
  function squeeze(s) { gsub(/[[:space:]]+/, " ", s); return s }
'

# awk runs on its own line, NOT as `$(awk ... | sort)`. In a pipeline `$?` is the LAST
# command's status, so piping straight into sort reports sort's exit and silently discards
# awk's `exit 2` — the malformed-row guard above would print its warning and then return 0,
# which is the guard failing in the one direction nobody checks. Sort afterwards instead.
RAW=$(awk "$EXTRACT" "$@")
RC=$?
[ "$RC" -ne 0 ] && exit "$RC"
ROWS=$(printf '%s\n' "$RAW" | sed '/^$/d' | sort -t'|' -k1,1)

if [ "$SUMMARY" -eq 0 ]; then
  printf '%s\n' "$ROWS"
  exit 0
fi

# --summary: the numbers T002 asserts against, so the snapshot is verified rather than trusted.
TOTAL=$(printf '%s\n' "$ROWS" | grep -c . || true)
UNIQUE=$(printf '%s\n' "$ROWS" | cut -d'|' -f1 | sort -u | grep -c . || true)
DUPES=$((TOTAL - UNIQUE))

printf 'rows:      %s\n' "$TOTAL"
printf 'unique:    %s\n' "$UNIQUE"
printf 'duplicate: %s\n' "$DUPES"
printf 'struck:    %s\n' "$(printf '%s\n' "$ROWS" | awk -F'|' '$6 == 1' | grep -c . || true)"
printf -- '--- status histogram ---\n'
printf '%s\n' "$ROWS" | awk -F'|' '{ h[$5]++ } END { for (k in h) printf "%-6s %d\n", k, h[k] }' | sort -k2 -rn

[ "$DUPES" -eq 0 ] || {
  echo "scenario-map-rows: $DUPES duplicate id(s) — ids are permanent handles and must be unique" >&2
  exit 2
}
exit 0
