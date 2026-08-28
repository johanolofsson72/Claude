#!/bin/sh
# validate-scenario-traceability.sh — the SC-id traceability gate.
#
# WHY THIS EXISTS: four comments in this directory cited this script by name for months —
# archive-spec-history.sh:25 and test-archive-spec-history.sh:9,55,271 — and they did not cite it as
# something that ought to exist. They cited it as something that had run:
#
#     "…with validate-scenario-traceability.sh reporting 100% and exit 0 throughout"
#
# No such file had ever been written. Not in this repo's history, not in the template, not under any
# other name. So that sentence was not a report of a gate that failed to bite; it was a measurement
# attributed to an instrument that did not exist, and a reader had no way to tell those two silences
# apart. Spec 007bs built the instrument and corrected the citations. This is the instrument.
#
# WHAT IT CHECKS — both directions, because each catches a different lie:
#
#   uncovered  a row whose Status claims ✓ or ◐ but which no test under the reference roots names.
#              The map says the scenario is proven; nothing in the suite mentions it.
#   dangling   an SC-id a test names that is not a row in the map. The suite believes in a scenario
#              the map does not have — a typo, or a row deleted out from under a test.
#   duplicate  one id on more than one row. An id is a permanent handle (.claude/rules/scenarios.md),
#              so this is two scenarios wearing one name, and it makes both directions above
#              approximate: a reference cannot say which of the two it proves.
#
# A ☐ row is EXEMPT from coverage. It is mapped and not yet tested, which is a legitimate state for
# every scenario of every unbuilt spec; counting it as a failure would leave this gate permanently
# red on any project with a roadmap, and a gate that can never be green gets switched off. That is
# how the last one became a comment. A retired (struck, ~~SC-NNN~~) row is exempt from coverage too —
# nothing is expected to test a retired scenario — but its id still counts as REAL for the dangling
# check, because .claude/rules/scenarios.md makes an id a permanent handle that is never reused.
#
# ------------------------------------------------------------------------------------------------
# THE LOCALE TRAP — read this before "simplifying" the classification into one awk line.
#
# The natural way to classify delimited rows is awk. On macOS awk (version 20200816) under this
# developer's locale, awk's string EQUALITY operator says these three symbols are the same symbol:
#
#     $ printf 'a|✓\nb|◐\nc|☐\n' | awk -F'|' '$2=="✓"{print $1}'      # LANG=sv_SE.UTF-8
#     a
#     b
#     c
#     $ printf 'a|✓\nb|◐\nc|☐\n' | LC_ALL=C awk -F'|' '$2=="✓"{print $1}'
#     a
#
# It is specifically `==`, which goes through the locale's collation table; U+2713, U+25D0 and U+2610
# carry no distinguishing primary weight in the Swedish collation, so strcoll() calls them equal.
# Regex match ($2 ~ /✓/), index($2,"✓"), field splitting, shell `case`, `[ = ]` and `grep -F` are all
# byte-oriented and all correct. Only `==` lies.
#
# On the real map that one line selects 187 of 188 rows instead of 96 — every ☐ row and every struck
# row classified as a validated one. A gate built that way computes coverage over a denominator the
# map does not support and reports a clean run over a live gap: reporting 100% and exit 0 the whole
# time, which is the exact sentence this script exists to retire. The fix would have re-committed the
# defect it was written to fix.
#
# This is not hypothetical. The first draft of spec 007bs carried "62 uncovered, 88 of 150" in its
# own evidence table. Those numbers came from a scoping command that classified with awk `==` under
# the live shell; the true figures are 28 and 122 of 150. The wrong numbers survived into a written
# draft of the document arguing that these numbers go wrong.
#
# TWO defences, and neither is redundant:
#   1. LC_ALL=C is exported below — it protects any comparison a later maintainer adds without
#      reading this header.
#   2. The status decision is a shell `case`, never awk `==` — it protects against a caller that
#      exports a locale into a sub-invocation after the pin is read.
# scripts/test-validate-scenario-traceability.sh case 14 runs this gate under LANG=sv_SE.UTF-8 and
# checks its per-status counts against a `grep -c` oracle. A gate whose own tests only ever run under
# LC_ALL=C has not been tested on the machine it runs on.
# ------------------------------------------------------------------------------------------------
#
# WHAT IT DOES NOT DO: it never writes. It reads the map, reads the tests, and reports.
#
# Usage:
#   scripts/validate-scenario-traceability.sh                       # ./specs, roots: tests
#   scripts/validate-scenario-traceability.sh --dir path/to/specs
#   scripts/validate-scenario-traceability.sh --roots tests,src
#   scripts/validate-scenario-traceability.sh --quiet               # totals + failures only
#
# Exit codes — "I cannot answer" is never reported as "the answer is fine":
#   0  clean — nothing uncovered, nothing dangling
#   1  uncovered and/or dangling ids found
#   2  usage error
#   3  the map could not be read, the extractor refused, or it yielded zero rows
#   4  a configured reference root does not exist
#
# Cross-platform: POSIX sh + POSIX awk + grep. Runs under macOS, Linux, and Git Bash/WSL.

# Defence 1 of 2 against the collation trap documented above. See defence 2 at `is_claimed`.
#
# The `>>> name` / `<<< name` markers below are sabotage targets. The harness swaps exactly one
# marked region at a time to prove which defence is carrying which case — a blind `sed` over the
# whole file could not tell "removed the pin" from "removed the pin and broke the parser".
# >>> locale-pin
LC_ALL=C
export LC_ALL
# <<< locale-pin

set -eu

SPECS_DIR=""
ROOTS="tests"
QUIET=0

# Not configurable, and deliberately so: scenario-map-rows.sh hardcodes SC- in its row pattern, so a
# map using any other prefix extracts to zero rows. A --id-prefix flag here would let a caller ask
# for references to ids the extractor can never report as rows — every one of them dangling.
PREFIX="SC"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)       [ "$#" -ge 2 ] || { echo "--dir needs a path" >&2; exit 2; }; SPECS_DIR="$2"; shift 2 ;;
    --roots)     [ "$#" -ge 2 ] || { echo "--roots needs a value" >&2; exit 2; }; ROOTS="$2"; shift 2 ;;
    --quiet)     QUIET=1; shift ;;
    # Print the whole leading comment block rather than a hardcoded line range: this header will
    # grow, and a range silently truncates --help when it does (the project-maintenance.sh lesson).
    -h|--help)   awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *)           echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# scenario-map-rows.sh emits TAB-separated fields, and the tab is load-bearing: a scenario cell
# may contain a pipe (SC-436 quotes a formula-injection payload), so splitting on "|" pushes
# status into expected and the row stops counting as validated without anything erroring. Read
# that script's OUTPUT block before changing this.
TAB=$(printf '\t')

if [ -z "$SPECS_DIR" ]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
  SPECS_DIR="$ROOT/specs"
fi

if [ ! -d "$SPECS_DIR" ]; then
  echo "scenario-traceability: no specs directory at $SPECS_DIR" >&2
  exit 3
fi

PROJECT=$(CDPATH='' cd -- "$SPECS_DIR/.." && pwd)

# ------------------------------------------------------------------ the map, via the one predicate
# Sourced, not re-decided: five consumers already ask scenario-map-layout.sh where the rows live, and
# two of them disagreeing would be worse than either being wrong, because the disagreement is silent.
# shellcheck source=scripts/scenario-map-layout.sh
. "$HERE/scenario-map-layout.sh"
LAYOUT=$(scenario_map_layout "$PROJECT")

INDEX="$SPECS_DIR/SCENARIOS.md"
[ -f "$INDEX" ] || { echo "scenario-traceability: no scenario map at $INDEX" >&2; exit 3; }

MAP_FILES="$INDEX"
if [ "$LAYOUT" = "split" ]; then
  for f in "$SPECS_DIR"/scenarios/*.md; do
    [ -f "$f" ] && MAP_FILES="$MAP_FILES
$f"
  done
fi
MAP_COUNT=$(printf '%s\n' "$MAP_FILES" | grep -c .)

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t scenario-traceability)
trap 'rm -rf "$TMP"' EXIT INT TERM

# ------------------------------------------------------------------------------ rows, via the one
# extractor. NOT a grep for bare ids: scenario-map-rows.sh anchors to five-column table rows, so
# prose mentions, flowchart labels and the SC2086 shellcheck lookalike cannot enter the id set. It
# also knows that a retired row is written ~~SC-NNN~~, which the obvious '^| SC-' pattern misses —
# and those are precisely the ids that must never be reused.
# shellcheck disable=SC2086
if ! printf '%s\n' "$MAP_FILES" | tr '\n' '\0' | xargs -0 "$HERE/scenario-map-rows.sh" > "$TMP/rows" 2>"$TMP/rows.err"; then
  echo "scenario-traceability: scenario-map-rows.sh refused the map" >&2
  [ -s "$TMP/rows.err" ] && cat "$TMP/rows.err" >&2
  exit 3
fi

ROW_COUNT=$(grep -c . "$TMP/rows" || true)
if [ "$ROW_COUNT" -eq 0 ]; then
  # "0 of 0, all clear" is arithmetically clean and semantically empty. Reporting it as success is
  # the failure this script is named after.
  echo "scenario-traceability: the map yielded zero rows — nothing to check, and that is not a pass" >&2
  exit 3
fi

# The extractor promises six pipe-separated fields. If that ever stops being true, say so rather than
# silently mis-slicing the status column — a gate reading the wrong field is worse than no gate.
BADFIELDS=$(awk -F'\t' 'NF != 6 {c++} END {print c+0}' "$TMP/rows")
if [ "$BADFIELDS" -ne 0 ]; then
  echo "scenario-traceability: $BADFIELDS row(s) did not split into 6 fields — the extractor's format changed" >&2
  exit 3
fi

# ---------------------------------------------------------------------------------- classification
# Defence 2 of 2. Shell `case` on the status cell, by CONTAINMENT rather than an enumerated list of
# exact strings: `✓ *` is a validated row carrying a footnote (SC-155 today), not a third status, and
# an enumeration would need extending every time someone adds a marker — with silent exemption as the
# cost of forgetting.
#
# Deliberately a function, and deliberately marked: it is the single place the ✓/◐/☐ distinction is
# made, so it is the single place the collation trap could re-enter.
# >>> classify
is_claimed() { # <status-cell> — true when the row claims to be tested or validated
  case "$1" in
    *✓*|*◐*) return 0 ;;
  esac
  return 1
}
# <<< classify

: > "$TMP/claimed"
: > "$TMP/allids"
# The three fields this loop needs are the first, the fifth and the sixth, and they are cut out by
# suffix removal rather than by `IFS=<tab> read -r id kind scen expected status struck`. That reads
# better and is wrong: a tab is IFS WHITESPACE, so `read` collapses a run of them into one delimiter
# and an empty cell silently shifts every field after it — status would land in expected and the row
# would stop counting as claimed. The BADFIELDS guard above cannot see it, because awk with an
# explicit FS does NOT collapse, so the same line is six fields to awk and five to read. With "|" as
# the delimiter this could not happen; it is the cost of the delimiter change and it is paid here.
while IFS= read -r line; do
  id=${line%%"$TAB"*}
  [ -n "$id" ] || continue
  struck=${line##*"$TAB"}
  status=${line%"$TAB"*}; status=${status##*"$TAB"}
  printf '%s\n' "$id" >> "$TMP/allids"
  # >>> struck-exempt
  [ "$struck" = "1" ] && continue
  # <<< struck-exempt
  if is_claimed "$status"; then printf '%s\n' "$id" >> "$TMP/claimed"; fi
done < "$TMP/rows"

sort -u "$TMP/allids" -o "$TMP/allids"
sort -u "$TMP/claimed" -o "$TMP/claimed"

# Braces are load-bearing: bash decides where a variable name ends by the locale's notion of an
# identifier character, and under a UTF-8 locale "$TAB✓" parses as the variable TAB✓ — unbound,
# and with set -u that is an exit before a single row is counted. Under the LC_ALL=C pin above it
# parses as intended, so the bug is invisible until the pin is removed. The sabotage entry that
# removes the pin is what found this, which is the entry existing to prove the OTHER defence.
N_VALIDATED=$(grep -c "${TAB}✓${TAB}" "$TMP/rows" || true)
N_TESTED=$(grep -c "${TAB}◐${TAB}" "$TMP/rows" || true)
N_MAPPED=$(grep -c "${TAB}☐${TAB}" "$TMP/rows" || true)
N_STRUCK=$(awk -F'\t' '$6 == "1" {c++} END {print c+0}' "$TMP/rows")

# ------------------------------------------------------------------------------------- references
# One tree walk emitting every id token, not one `grep -r` per id: 150 ids would be 150 walks.
: > "$TMP/refs"
OLDIFS=$IFS
IFS=,
for root in $ROOTS; do
  IFS=$OLDIFS
  [ -n "$root" ] || continue
  case "$root" in
    /*) rp="$root" ;;
    *)  rp="$PROJECT/$root" ;;
  esac
  # >>> root-guard
  if [ ! -d "$rp" ]; then
    # A missing root yields zero references, which renders as "every claimed scenario is uncovered" —
    # a catastrophic-looking report with a trivial cause. Silence here is the same class of defect
    # this whole script exists to remove.
    echo "scenario-traceability: reference root does not exist: $root (looked in $rp)" >&2
    exit 4
  fi
  # <<< root-guard
  # Match ids of ANY length, then keep the three-digit ones. Matching [0-9]{3} directly would truncate
  # a hypothetical SC-1234 to SC-123 and invent a reference to a real scenario.
  grep -rhoIE "${PREFIX}-[0-9]+" "$rp" 2>/dev/null >> "$TMP/refs" || true
  IFS=,
done
IFS=$OLDIFS

grep -xE "${PREFIX}-[0-9]{3}" "$TMP/refs" 2>/dev/null | sort -u > "$TMP/refs.u" || : > "$TMP/refs.u"

# --------------------------------------------------------------------------------- the two answers
comm -23 "$TMP/claimed" "$TMP/refs.u" > "$TMP/uncovered"
# >>> dangling
comm -13 "$TMP/allids"  "$TMP/refs.u" > "$TMP/dangling"
# <<< dangling

# >>> duplicate-check
# A THIRD answer, and it is not about tests at all. .claude/rules/scenarios.md makes an id a
# permanent handle that is never reused, so one id on two rows is not a backlog item — it is two
# scenarios wearing one name, and every number above it silently becomes an approximation: the
# uncovered list cannot say WHICH of the two a test reference proves, and `sort -u` on the claimed
# set quietly counts them once. Reported like dangling rather than like uncovered, for the reason
# project-maintenance.sh gives: uncovered is a backlog, this is a mistake, and it is zero on a
# healthy map. It went unseen here because scenario-map-rows.sh does check uniqueness — but only
# under --summary, which this gate does not use and nothing else calls. agentcrm had 104 of them,
# one contiguous block allocated twice by two developers working different specs in parallel.
cut -f1 "$TMP/rows" | sort | uniq -d > "$TMP/duplicate"
# <<< duplicate-check
N_DUP=$(grep -c . "$TMP/duplicate" || true)

N_CLAIMED=$(grep -c . "$TMP/claimed" || true)
N_UNCOV=$(grep -c . "$TMP/uncovered" || true)
N_DANGL=$(grep -c . "$TMP/dangling" || true)
N_COVERED=$((N_CLAIMED - N_UNCOV))

# ----------------------------------------------------------------------------------------- report
row_detail() { # <id> — echo "  ID  status  scenario"
  awk -F'\t' -v want="$1" '$1 == want {printf "  %s  %s  %s\n", $1, $5, $3; exit}' "$TMP/rows"
}

echo "scenario traceability — $LAYOUT layout, $MAP_COUNT map file(s), roots: $ROOTS"
echo

if [ "$N_UNCOV" -gt 0 ]; then
  echo "uncovered — the row claims ✓/◐ but no test under the roots names it ($N_UNCOV):"
  if [ "$QUIET" -eq 0 ]; then
    while read -r id; do [ -n "$id" ] && row_detail "$id"; done < "$TMP/uncovered"
  fi
  echo
fi

if [ "$N_DANGL" -gt 0 ]; then
  echo "dangling — a test names an id the map does not have ($N_DANGL):"
  if [ "$QUIET" -eq 0 ]; then
    while read -r id; do [ -n "$id" ] && echo "  $id"; done < "$TMP/dangling"
  fi
  echo
fi

if [ "$N_DUP" -gt 0 ]; then
  echo "duplicate — one id on more than one row; an id is a permanent handle ($N_DUP):"
  if [ "$QUIET" -eq 0 ]; then
    while read -r id; do
      [ -n "$id" ] || continue
      # Every occurrence, not the first: the point is that they are different scenarios.
      awk -F'\t' -v want="$id" '$1 == want {printf "  %s  %s  %s\n", $1, $5, $3}' "$TMP/rows"
    done < "$TMP/duplicate"
  fi
  echo
fi

# BOTH numbers, never a bare percentage. "100%" with its denominator dropped is the sentence that
# started spec 007bs; a fraction that carries its denominator cannot be quoted into a claim about a
# different one.
echo "coverage: $N_COVERED of $N_CLAIMED claimed rows referenced by a test"
echo "  ($ROW_COUNT rows: $N_VALIDATED ✓ · $N_TESTED ◐ · $N_MAPPED ☐ exempt · $N_STRUCK retired exempt)"

[ "$N_UNCOV" -eq 0 ] && [ "$N_DANGL" -eq 0 ] && [ "$N_DUP" -eq 0 ] && exit 0
exit 1
