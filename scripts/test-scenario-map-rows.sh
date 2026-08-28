#!/bin/sh
# test-scenario-map-rows.sh — the parser harness for scenario-map-rows.sh.
#
# WHY THIS EXISTS: scenario-map-rows.sh was the single implementation of cell splitting for the
# whole scenario-map toolchain and it had no test of its own. test-scenario-map-layouts.sh calls
# it, but only to compare one layout against another — both sides run the same parser, so a
# parsing bug cancels out and the comparison stays green. That is precisely how trap 3 survived:
# on 2026-08-28 the traceability gate refused agentcrm's 482-row map over ONE row containing a
# markdown-escaped pipe, and every harness that touched the parser was passing at the time.
#
# WHAT IT ASSERTS, and why each case is here rather than being obvious:
#
#   - the escaped pipe (\|) is a cell's content, not a column break                    [trap 3]
#   - the OUTPUT is TAB-separated and every row still has exactly six fields. This is the half
#     the first attempt at the fix got wrong: it rejoined the cell and kept the pipe escaped,
#     reasoning that \| is not a delimiter. It is one — `cut -d'|'` and `IFS='|' read` see the
#     byte, not the backslash — so the emitted row split into seven, status landed in expected,
#     struck read "✓|0", and the row stopped counting as validated with nothing erroring. The
#     field-count case below is what caught it, one command after the change.
#   - an EVEN run of backslashes before a delimiter is a real column break. This is the case a
#     naive "field ends in a backslash" test gets wrong, and it cannot be found by staring at a
#     map that happens to contain no such row.
#   - a genuinely six-column row is STILL rejected. This is the known positive from trap 4 in
#     .claude/rules/mutation-timeouts.md: a fix that widens a guard must be shown to leave the
#     guard biting, or "no malformed rows" stops distinguishing a clean map from a blind parser.
#   - a retired (~~SC-NNN~~) row keeps its id and reports struck=1                     [trap 1]
#   - prose and flowchart mentions of an id are not rows                               [trap 2]
#
# FIXTURE IDS ARE DERIVED, NEVER WRITTEN (register row H7bd). Every id below comes from
# scenario-probe-ids.sh, which hands back ids no row in the project's real map owns, and the fixture
# bodies carry @IDn@ placeholders substituted on the way to disk. Spelling a real id here instead
# would be shorter and would be a false binding: the id-accounting gate scans scripts/, cannot tell a
# fixture from an assertion, and counts a probe map about column parsing as proof that the real
# scenario is tested. Measured in consultpilot — the id in the "prose is not a row" fixture below was
# the ONLY reference to a real ✓ scenario in that entire tree, so the gate reported it traced on the
# strength of a sentence written to prove sentences do not count. Do not "simplify" these back to
# literals; scenario-probe-ids.sh's header has the two alternatives and why neither works here.
#
# Run:  bash scripts/test-scenario-map-rows.sh
# Exit: 0 all cases pass · 1 one or more failed

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROWS="$SCRIPT_DIR/scenario-map-rows.sh"
FAILED=0

# shellcheck source=scripts/scenario-probe-ids.sh
. "$SCRIPT_DIR/scenario-probe-ids.sh"

# The project's map, if it has one. The template ships none, and that is a legitimate state rather
# than a broken one: with no map every id is free, which is exactly right for a tree that owns no
# scenarios. Resolved without scenario-map-layout.sh on purpose — a per-feature file cannot allocate
# an id the index does not also list, so the index alone is a sufficient owned set here, and this
# harness has no other reason to know what a layout is.
PROBE_MAP=$(git rev-parse --show-toplevel 2>/dev/null)/specs/SCENARIOS.md

PROBE_WANT=9
PROBE_IDS=$(scenario_probe_ids "$PROBE_WANT" "$PROBE_MAP")
if [ "$(printf '%s\n' "$PROBE_IDS" | grep -c .)" -ne "$PROBE_WANT" ]; then
  # Refuse rather than run short. A fixture missing an id still parses, still passes, and quietly
  # stops asserting the case it is named after — the failure this whole derivation exists to avoid,
  # arriving through the back door.
  printf 'test-scenario-map-rows: fewer than %d free scenario ids in the probe window.\n' "$PROBE_WANT" >&2
  printf '  The id space is exhausted and this harness can no longer build a fixture the map does\n' >&2
  printf '  not own. Widen the id format (extractor pattern, gate regex and the probe window) first.\n' >&2
  exit 1
fi

# shellcheck disable=SC2086
set -- $PROBE_IDS
ID1=$1; ID2=$2; ID3=$3; ID4=$4; ID5=$5; ID6=$6; ID7=$7; ID8=$8; ID9=$9
SUBST=$(scenario_probe_sed_script "$ID1" "$ID2" "$ID3" "$ID4" "$ID5" "$ID6" "$ID7" "$ID8" "$ID9")

ok()  { printf '  ok:   %s\n' "$1"; }
bad() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t scenrows)
trap 'rm -rf "$TMP"' EXIT INT TERM

TAB=$(printf '\t')

# expect_row <label> <map-file> <id> <expected full output line>
expect_row() {
  _label=$1; _file=$2; _id=$3; _want=$4
  _got=$(sh "$ROWS" "$_file" 2>/dev/null | grep "^$_id$TAB")
  if [ "$_got" = "$_want" ]; then ok "$_label"
  else bad "$_label" "got [$_got] want [$_want]"
  fi
}

printf '== scenario-map-rows: cell splitting ==\n'

# --- trap 3: the escaped pipe ---------------------------------------------------------
sed "$SUBST" > "$TMP/escaped.md" <<'MAP'
| @ID1@ | adversarial | A note beginning `=cmd\|` shown in the preview | Rendered as text, never as a formula | ✓ |
| @ID2@ | happy | A plain row with no pipes at all | Extracted unchanged | ✓ |
| @ID3@ | edge | Two \| escaped \| pipes in one cell | Still one cell | ◐ |
| ~~@ID4@~~ | happy | A retired row | Its id stays reserved | ☐ |
MAP

expect_row 'escaped pipe is content, not a column break' "$TMP/escaped.md" "$ID1" \
  "${ID1}${TAB}adversarial${TAB}A note beginning \`=cmd\\|\` shown in the preview${TAB}Rendered as text, never as a formula${TAB}✓${TAB}0"
expect_row 'a row with no pipes is untouched' "$TMP/escaped.md" "$ID2" \
  "${ID2}${TAB}happy${TAB}A plain row with no pipes at all${TAB}Extracted unchanged${TAB}✓${TAB}0"
expect_row 'two escaped pipes in one cell' "$TMP/escaped.md" "$ID3" \
  "${ID3}${TAB}edge${TAB}Two \\| escaped \\| pipes in one cell${TAB}Still one cell${TAB}◐${TAB}0"
expect_row 'a retired row keeps its id and reports struck' "$TMP/escaped.md" "$ID4" \
  "${ID4}${TAB}happy${TAB}A retired row${TAB}Its id stays reserved${TAB}☐${TAB}1"

if sh "$ROWS" "$TMP/escaped.md" >/dev/null 2>&1; then
  ok 'a map whose only pipes are escaped exits 0'
else
  bad 'a map whose only pipes are escaped exits 0' "exit $?"
fi

# The output contract, asserted on the rows most able to break it. validate-scenario-traceability.sh
# refuses the whole run when any row is not six fields, and this is the case that caught the first
# fix keeping a pipe in the emitted cell: four rows out, one of them seven fields long.
_wrongwidth=$(sh "$ROWS" "$TMP/escaped.md" 2>/dev/null | awk -F'\t' 'NF != 6 { c++ } END { print c+0 }')
if [ "$_wrongwidth" = "0" ]; then
  ok 'every emitted row is exactly six tab-separated fields'
else
  bad 'every emitted row is exactly six tab-separated fields' "$_wrongwidth row(s) split wrong"
fi

# --- the even-backslash case ----------------------------------------------------------
# `\\` is a literal backslash in markdown; the pipe after it IS a column break. A parser that
# tests only "ends in a backslash" swallows that break and reports four columns.
sed "$SUBST" > "$TMP/evenslash.md" <<'MAP'
| @ID5@ | edge | Ends in a literal backslash \\ | Still five columns | ✓ |
MAP
expect_row 'an even backslash run leaves the column break alone' "$TMP/evenslash.md" "$ID5" \
  "${ID5}${TAB}edge${TAB}Ends in a literal backslash \\\\${TAB}Still five columns${TAB}✓${TAB}0"

# --- the known positive: the guard must still bite ------------------------------------
sed "$SUBST" > "$TMP/malformed.md" <<'MAP'
| @ID6@ | edge | A genuinely six-column row | With one cell too many | ✓ | oops |
MAP
_err=$(sh "$ROWS" "$TMP/malformed.md" 2>&1 >/dev/null)
_rc=$?
# `case`, not `printf | grep -q`: grep -q exits at the first match and the printf ahead of it
# then dies of SIGPIPE, which under pipefail is 141 — a true claim read as false. See
# validate-no-sigpipe-assertions.sh, which refuses that shape in this directory.
case "$_err" in *'has 6 columns, expected 5'*) _named=1 ;; *) _named=0 ;; esac
if [ "$_rc" -eq 2 ] && [ "$_named" -eq 1 ]; then
  ok 'a real six-column row is still rejected with exit 2'
else
  bad 'a real six-column row is still rejected with exit 2' "rc=$_rc err=[$_err]"
fi

# --- trap 2: only table rows count ----------------------------------------------------
sed "$SUBST" > "$TMP/prose.md" <<'MAP'
Some prose that mentions @ID7@ without being a row, and a flowchart node @ID8@.

| @ID9@ | happy | The only actual row | Counted once | ✓ |
MAP
_ids=$(sh "$ROWS" "$TMP/prose.md" 2>/dev/null | cut -d"$TAB" -f1 | tr '\n' ' ')
if [ "$_ids" = "$ID9 " ]; then
  ok 'prose and flowchart mentions are not rows'
else
  bad 'prose and flowchart mentions are not rows' "extracted [$_ids]"
fi

# --- --summary agrees with the rows it counted ----------------------------------------
_total=$(sh "$ROWS" --summary "$TMP/escaped.md" 2>/dev/null | awk '/^rows:/ { print $2 }')
if [ "$_total" = "4" ]; then
  ok '--summary counts the escaped-pipe rows it can now parse'
else
  bad '--summary counts the escaped-pipe rows it can now parse' "rows: $_total, want 4"
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf 'scenario-map-rows: all cases pass\n'
  exit 0
fi
printf 'scenario-map-rows: %d case(s) failed\n' "$FAILED"
exit 1
