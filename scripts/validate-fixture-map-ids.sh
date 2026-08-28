#!/bin/sh
# validate-fixture-map-ids.sh — refuse a real scenario id written into a fixture-map harness.
#
# WHY THIS EXISTS. A harness that needs a scenario map writes one, and the shortest way to write one
# is to spell out ids the real map already owns. The id-accounting gate scans scripts/ for
# references and cannot tell a fixture from an assertion, so a probe map about column parsing is
# counted as proof that the real scenario is tested.
#
# Measured in consultpilot on 2026-08-28 (register row H7bd): nine real ids were bound that way
# across two harnesses, and one of them — the id in a fixture line whose entire purpose was to prove
# that PROSE MENTIONS ARE NOT ROWS — had no other reference anywhere in tests/ or scripts/. Its map
# row read ✓ and the gate reported it traced, on the strength of a sentence written to prove that
# sentences do not count.
#
# The rule had been written down before, correctly, and could not stop anything. A note in
# test-archive-spec-history.sh has said "fixture rows deliberately use ID-, never SC-" for months,
# with the reason spelled out and a "do not fix this back" warning. The harness that broke the rule
# was written afterwards, by someone who had no reason to read that file. A rule that exists only as
# a comment in one file is a rule the next file breaks.
#
# WHAT IT CHECKS.
#
#   population   a script under the scan root that either (a) contains a scenario-map TABLE ROW whose
#                first cell is a literal id the map owns, or (b) sources scenario-probe-ids.sh, i.e.
#                has already been converted to derived ids.
#   finding      any literal SC-id token in such a file whose number the map owns — in a fixture row,
#                in a heredoc, or in prose.
#
# THE POPULATION IS DELIBERATELY THE UNION, and (b) is the half that matters. Trigger (a) alone
# describes the tree before the fix and NOT the tree after it: once a harness is converted its
# fixture rows are placeholders, it drops out of the population, and the gate stops watching the one
# file most likely to regress. A gate that disarms itself on success is exactly the coincidence this
# whole line of work removes — it would report clean for the same reason a deleted gate does.
#
# The check is FILE-scoped, not line-scoped, inside that population. A converted harness must not
# spell a real id anywhere, including in the comment explaining why it must not — that comment is
# itself a reference, and writing one was the first mistake made while landing this row.
#
# WHAT IT DOES NOT DO, and each omission is an argument rather than an oversight:
#
#   - It does not police ids in harnesses that embed no map. Naming the scenario a case asserts is
#     how tests bind to the map; that is the mechanism working, not a defect.
#   - It does not look outside the scan root. Every map-embedding harness in these trees is a shell
#     script under scripts/; widening to a population with no known members would add a branch with
#     no red case.
#   - It never writes. It reads the map, reads the scripts, and reports.
#
# Usage:
#   scripts/validate-fixture-map-ids.sh                 # the repo's own map and scripts/
#   scripts/validate-fixture-map-ids.sh --map PATH      # a different map (the self-test uses this)
#   scripts/validate-fixture-map-ids.sh --root DIR      # a different scan root
#   scripts/validate-fixture-map-ids.sh --quiet         # verdict line only
#
# Exit codes — "I cannot answer" is never reported as "the answer is fine":
#   0  clean
#   1  at least one finding
#   2  usage error
#   3  NOT RUN — no scenario map to compare against, so there is no owned set and no verdict
#
# Cross-platform: POSIX sh + POSIX awk + grep.

LC_ALL=C
export LC_ALL

set -eu

MAP=""
ROOT=""
QUIET=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --map)   [ "$#" -ge 2 ] || { echo "--map needs a path" >&2; exit 2; };  MAP="$2";  shift 2 ;;
    --root)  [ "$#" -ge 2 ] || { echo "--root needs a path" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$HERE/..")

[ -n "$MAP" ]  || MAP="$PROJECT/specs/SCENARIOS.md"
[ -n "$ROOT" ] || ROOT="$PROJECT/scripts"

if [ ! -d "$ROOT" ]; then
  echo "fixture-map-ids: NOT RUN — no scan root at $ROOT" >&2
  exit 3
fi

# NOT RUN, never clean. A tree with no scenario map owns no ids, so every fixture id in it is free
# and the gate has nothing to refuse — which is a true statement about an absent map, not a verdict
# about the files. The template itself is in exactly this state, and a `clean` there would read as
# "these harnesses were checked". They were not; there was nothing to check them against.
if [ ! -f "$MAP" ]; then
  echo "fixture-map-ids: NOT RUN — no scenario map at $MAP, so there is no owned id set"
  echo "  (a tree with no map allocates no ids; nothing here is a verdict about the harnesses)"
  exit 3
fi

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t fixturemapids)
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---------------------------------------------------------------------------------- the owned set
# A table row allocates an id; prose does not. Struck rows count — an id is a permanent handle that
# is never reused, so a retired row's number stays occupied and a fixture taking it still collides
# with a row that still exists. The suffix letter is dropped because the NUMBER is what a collision
# is about: a fixture spelling the stem of a suffixed pair collides with both.
awk '
  /^\| *~*SC-[0-9]/ {
    if (match($0, /SC-[0-9]+/)) print substr($0, RSTART + 3, RLENGTH - 3) + 0
  }
' "$MAP" | sort -u > "$TMP/owned"

OWNED_COUNT=$(grep -c . "$TMP/owned" || true)
if [ "$OWNED_COUNT" -eq 0 ]; then
  # A map file that yields zero rows is not an empty map, it is an unreadable one — the same
  # distinction validate-scenario-traceability.sh refuses to blur. "0 owned, nothing to collide
  # with, clean" is arithmetically true and says nothing.
  echo "fixture-map-ids: NOT RUN — $MAP yielded zero scenario rows, so the owned set is unknown" >&2
  exit 3
fi

# ------------------------------------------------------------------------------- the population
# Self-exclusion: this file and its own harness must be able to spell the shapes they describe.
# Everything else in the root is fair game, including the helper — a helper that spelled a real id
# in its documentation would bind it exactly as a fixture would.
SELF=$(basename "$0")
SELF_TEST="test-fixture-map-ids.sh"

: > "$TMP/findings"
SCANNED=0
POPULATION=0

for f in "$ROOT"/*.sh; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  case "$base" in "$SELF"|"$SELF_TEST") continue ;; esac
  SCANNED=$((SCANNED + 1))

  # Trigger (a): a fixture table row carrying a literal id. Matched on the ROW SHAPE — a pipe, the
  # id in the first cell, a closing pipe — because that is what a map parser reads. `grep -q` and
  # not a pipeline into another matcher: a `printf | grep -q` here would be the SIGPIPE idiom this
  # project's own gate refuses.
  has_row=0
  if grep -qE '^[[:space:]]*\|[[:space:]]*~*SC-[0-9]{3,4}[a-z]?~*[[:space:]]*\|' "$f"; then has_row=1; fi
  # Trigger (b): already converted, and therefore still under the rule.
  has_helper=0
  if grep -q 'scenario-probe-ids\.sh' "$f"; then has_helper=1; fi

  [ "$has_row" -eq 1 ] || [ "$has_helper" -eq 1 ] || continue
  POPULATION=$((POPULATION + 1))

  # Every literal id in the file, with its line, filtered to the ones the map owns. Matching any
  # width and then comparing the number keeps a five-digit token from being read as its own first
  # four — the same reason validate-scenario-traceability.sh matches wide and narrows afterwards.
  awk -v file="$base" '
    FNR == NR { owned[$0 + 0] = 1; next }
    {
      line = $0
      while (match(line, /SC-[0-9]+[a-z]?/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        num = tok; sub(/^SC-/, "", num); sub(/[a-z]$/, "", num)
        if (length(num) < 3 || length(num) > 4) continue
        if ((num + 0) in owned) printf "%s:%d\t%s\n", file, FNR, tok
      }
    }
  ' "$TMP/owned" "$f" >> "$TMP/findings"
done

N=$(grep -c . "$TMP/findings" || true)

if [ "$N" -gt 0 ]; then
  echo "fixture-map-ids: $N literal scenario id(s) in $POPULATION fixture-map harness(es)"
  if [ "$QUIET" -eq 0 ]; then
    echo
    while IFS= read -r hit; do [ -n "$hit" ] && printf '  %s\n' "$hit"; done < "$TMP/findings"
    echo
    echo "  Each of these binds a real scenario to text that asserts nothing about it: the id-accounting"
    echo "  gate scans this directory and counts the mention as a reference. Derive the ids instead —"
    echo "  see scripts/scenario-probe-ids.sh — and describe an id in prose rather than spelling it."
  fi
  exit 1
fi

echo "fixture-map-ids: clean — $POPULATION fixture-map harness(es) of $SCANNED script(s), $OWNED_COUNT owned ids"
exit 0
