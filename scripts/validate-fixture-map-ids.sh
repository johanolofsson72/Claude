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
# WHAT IT CHECKS — FIXTURE CONTENT, and nothing else.
#
#   fixture row  a line that is a scenario-map table row: a pipe, an id or an @IDn@ placeholder in
#                the first cell, a closing pipe. The placeholder half matters — it is what keeps a
#                CONVERTED harness's fixtures recognisable, so the gate does not stop watching a file
#                the moment it is fixed.
#   R1           a fixture row whose id is spelled out and owned by the map.
#   R2           any owned id anywhere in ANY heredoc body of a file that writes a fixture row. This
#                is the live case: the id sat in a SENTENCE inside the probe map, and that sentence
#                exists to prove that sentences are not rows. Scoped per FILE and not per heredoc,
#                because a map fixture is written in several pieces — the split layout's index lists
#                its features and links their ids in a table whose first cell is a feature name, so a
#                per-heredoc rule reads that piece as "not a map" and walks past two live bindings.
#
# WHAT IT DELIBERATELY LEAVES ALONE, because getting this wrong is worse than the defect:
#
#   - AN ID IN AN ASSERTION LABEL. `echo "  ok  the thing works (<id>)"` is how a test binds to the
#     map; refusing it would refuse the mechanism. The first draft of this gate was file-scoped —
#     any owned id anywhere in a harness that embeds a map — and it condemned 60 such labels in one
#     harness on its first real run. A gate whose first honest run says "your tracing scheme is the
#     bug" has misidentified the bug.
#   - AN ID IN PROSE OUTSIDE A FIXTURE. Whether a comment naming an id should count as a reference at
#     all is a real question — the id-accounting gate excludes src/ for exactly that reason, and the
#     same argument reaches comments in scripts/. It is a wider class with a different answer and it
#     needs its own measurement, not a silent extension of this one. Write ids in prose sparingly and
#     describe them where you can; that is discipline here, not enforcement.
#   - ANYTHING OUTSIDE THE SCAN ROOT. Every map-embedding harness in these trees is a shell script
#     under scripts/; widening to a population with no known members would add a branch with no red
#     case.
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

  # Is this a fixture-map harness at all? A file with no map row in it — literal or placeholder —
  # has no fixture content to police, and the ids it names are assertion labels. `grep -q` on the
  # file rather than a pipeline: a `printf | grep -q` here would be the SIGPIPE idiom this project's
  # own gate refuses in these files.
  grep -qE '^[[:space:]]*\|[[:space:]]*~*(SC-[0-9]{3,4}[a-z]?|@ID[0-9]+@)~*[[:space:]]*\|' "$f" || continue
  POPULATION=$((POPULATION + 1))

  # R1 and R2 in one pass.
  #
  # The heredoc tracking is deliberately crude — an opener sets a terminator, a line equal to that
  # terminator closes it — because the alternative is parsing shell, and a gate that needs a shell
  # parser to decide what it refuses is a gate nobody can reason about. Crude is fine here: a missed
  # heredoc costs an R2 finding that R1 usually catches anyway, and a spurious one costs nothing
  # because the id still has to be owned to be reported.
  #
  # Matching ids at any width and comparing the NUMBER keeps a five-digit token from being read as
  # its own first four — the same reason the coverage gate matches wide and narrows afterwards.
  awk -v file="$base" '
    FNR == NR { owned[$0 + 0] = 1; next }

    function report(line, lineno,   tok, num) {
      while (match(line, /SC-[0-9]+[a-z]?/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        num = tok; sub(/^SC-/, "", num); sub(/[a-z]$/, "", num)
        if (length(num) < 3 || length(num) > 4) continue
        if ((num + 0) in owned) printf "%s:%d\t%s\n", file, lineno, tok
      }
    }

    # Heredoc bodies are COLLECTED here and judged in END, because whether a body counts is decided
    # by a row that may appear anywhere inside it — including after the line being judged. Collecting
    # is why the file is read once and not twice; reading it twice emitted every finding twice, which
    # is a report that overstates the damage and undermines its own count.
    {
      if (inhd) {
        if ($0 == term) { inhd = 0; next }
        body[hd] = body[hd] $0 "\n"
        bline[hd] = bline[hd] FNR "\n"
        if ($0 ~ /^[[:space:]]*\|[[:space:]]*~*(SC-[0-9][0-9][0-9][0-9]?[a-z]?|@ID[0-9]+@)~*[[:space:]]*\|/) hasrow = 1
        next
      }
      # R1: a fixture row outside any heredoc (a printf-written map, a here-string, a plain file).
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*~*SC-[0-9][0-9][0-9][0-9]?[a-z]?~*[[:space:]]*\|/) report($0, FNR)
      if (match($0, /<<-?[[:space:]]*[\x27"]?[A-Za-z_][A-Za-z0-9_]*[\x27"]?/)) {
        term = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", term); gsub(/[\x27"]/, "", term)
        hd++; inhd = 1
      }
    }

    END {
      # R2: every owned id in every heredoc of a file that writes a map. This is where the live
      # defect lived — an id in a sentence inside the probe map, not in a cell — and where two more
      # sat, in the index heredoc of the split layout, whose rows are feature names rather than ids.
      # (No apostrophes in here: this awk program lives in a single-quoted shell string, so one ends
      # the string and the gate dies with a syntax error. Observed, while writing this very comment.)
      if (!hasrow) exit
      for (h = 1; h <= hd; h++) {
        n = split(body[h], lines, "\n")
        split(bline[h], nums, "\n")
        for (i = 1; i <= n; i++) if (lines[i] != "") report(lines[i], nums[i] + 0)
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
