#!/bin/bash
# test-validate-scenario-traceability.sh — harness for scripts/validate-scenario-traceability.sh.
#
# WHY THIS EXISTS: the gate it tests was, for months, a name in four comments and nothing else —
# cited as a tool that "reported 100% and exit 0 the whole time" while no such file had ever been
# written. A gate that is only described is worse than no gate, because the description is quoted as
# evidence. So the gate built by spec 007bs ships with a harness that has been watched failing.
#
# It runs the gate against generated fixtures in a temp dir — never against the repo's real specs/ —
# and it checks its own teeth: the final step sabotages a COPY of the gate, one marked region at a
# time, and requires the named cases to go red. A gate nobody has watched fail is a report, not a
# gate — the H5b lesson, restated by H5g, where a harness sat green and unrun for months. (That
# sentence is quoted from the sibling harness with its id removed; the id is exactly what must not
# appear here.)
#
# ------------------------------------------------------------------------------------------------
# THE LITERAL ID TOKEN DOES NOT APPEAR IN THIS FILE. Fixture ids are composed at runtime from $P.
#
# The sibling harness (test-archive-spec-history.sh:55) solves the same problem by prefixing its
# fixture ids `ID-`, because a real id written into a file under scripts/ would be picked up as a
# reference and would bind a real scenario to a fixture that never exercises it — the false-binding
# trap H5c and H5g each spent a row unpicking.
#
# That trick is unavailable here: scenario-map-rows.sh hardcodes the real prefix in its row pattern,
# so a fixture row using any other prefix extracts to NOTHING and every case below would be quietly
# testing an empty map. Verified 2026-08-28 — a fixture holding one row of each yields only the
# real-prefixed one, silently, exit 0.
#
# So this file goes one better: the ids are built by concatenation at runtime, which removes the
# literal token from the source altogether rather than choosing a prefix nothing matches. Case 15
# greps this file for the literal and fails if it finds one, so the property cannot rot. Do not
# "tidy" the concatenation back into literals.
# ------------------------------------------------------------------------------------------------
#
# Usage:
#   bash scripts/test-validate-scenario-traceability.sh              # test the shipped script
#   bash scripts/test-validate-scenario-traceability.sh --script X   # test some other copy
#   bash scripts/test-validate-scenario-traceability.sh --no-sabotage
#
# Exit: 0 all cases passed · 1 one or more failed · 2 a case could not be run (inconclusive).
#
# INCONCLUSIVE IS NOT PASS. Case 14 needs a Swedish UTF-8 locale to exist on the host. Where it does
# not, the case reports itself by name and this harness exits 2 — the 007br precedent: a precondition
# nobody can meet is a third state, and collapsing it into PASS is exactly how a gate becomes
# decorative.

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/scripts/validate-scenario-traceability.sh"
RUN_SABOTAGE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --script) SCRIPT="$2"; shift 2 ;;
    --no-sabotage) RUN_SABOTAGE=0; shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -f "$SCRIPT" ] || { echo "script under test not found: $SCRIPT" >&2; exit 2; }

PASS=0; FAIL=0; INCONCL=0; FAILED_CASES=""
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_CASES="$FAILED_CASES $1"; printf '  FAIL  %s — %s\n' "$1" "$2"; }
skip() { INCONCL=$((INCONCL+1)); printf '  INCONCLUSIVE  %s — %s\n' "$1" "$2"; }

# The prefix, never written as part of an id literal. See the header.
P="SC"
V='✓'   # validated
T='◐'   # tested
M='☐'   # mapped, not yet tested

id() { printf '%s-%s' "$P" "$1"; }

# ---------------------------------------------------------------- fixtures --

new_project() { # → echoes a project root with specs/ and tests/ under it
  d=$(mktemp -d)
  mkdir -p "$d/specs" "$d/tests"
  echo "$d"
}

map_header() {
  printf '# Scenario map\n\n## Actor: Someone\n\n### Feature: Something   (spec: 001-something)\n\n'
  printf '| ID     | Type  | Scenario        | Expected outcome | Status |\n'
  printf '|--------|-------|-----------------|------------------|--------|\n'
}

# row <num> <status> [struck]
row() {
  if [ "${3:-}" = "struck" ]; then
    printf '| ~~%s~~ | happy | A thing happens | It works | %s |\n' "$(id "$1")" "$2"
  else
    printf '| %s | happy | A thing happens | It works | %s |\n' "$(id "$1")" "$2"
  fi
}

# write_test <project> <name> <num>...
write_test() {
  proj="$1"; name="$2"; shift 2
  {
    printf 'test file %s\n' "$name"
    for n in "$@"; do printf 'it covers %s\n' "$(id "$n")"; done
  } > "$proj/tests/$name"
}

# Run the gate; capture output and exit code without tripping anything.
run_gate() { # <project> [extra args...]
  proj="$1"; shift
  OUT=$(bash "$SCRIPT" --dir "$proj/specs" "$@" 2>&1)
  RC=$?
  return 0
}

echo "Testing: $SCRIPT"
echo

# -------------------------------------------------------------------- cases --

# case1 — a clean map: every claimed row is referenced, nothing dangles.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$T"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 902
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case1-clean"; else bad "case1-clean" "expected exit 0, got $RC: $OUT"; fi

# case2 — a validated row nothing references. The gate's primary job.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 902)" <<< "$OUT" && grep -q 'uncovered' <<< "$OUT"; then
  ok "case2-uncovered-validated"
else
  bad "case2-uncovered-validated" "expected exit 1 naming the id under uncovered, got $RC: $OUT"
fi

# case3 — a test naming an id the map does not have.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 907
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q 'dangling' <<< "$OUT" && grep -q "$(id 907)" <<< "$OUT"; then
  ok "case3-dangling"
else
  bad "case3-dangling" "expected exit 1 naming the id under dangling, got $RC: $OUT"
fi

# case4 — both directions at once; both sections must appear.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 907
run_gate "$proj"
if [ "$RC" -eq 1 ] \
   && grep -q 'uncovered' <<< "$OUT" && grep -q "$(id 902)" <<< "$OUT" \
   && grep -q 'dangling' <<< "$OUT"  && grep -q "$(id 907)" <<< "$OUT"; then
  ok "case4-both-directions"
else
  bad "case4-both-directions" "expected both sections populated, got $RC: $OUT"
fi

# case5 — a mapped-but-untested row with no test is EXEMPT. This is the case that keeps the gate
# usable on a project with a roadmap; without it the gate is permanently red and gets switched off.
proj=$(new_project)
{ map_header; row 901 "$V"; row 902 "$M"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case5-mapped-exempt"; else bad "case5-mapped-exempt" "expected exit 0, got $RC: $OUT"; fi

# case6 — a retired row with no test is exempt. Nothing is expected to test a retired scenario.
proj=$(new_project)
{ map_header; row 901 "$V"; row 903 "$V" struck; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case6-struck-exempt"; else bad "case6-struck-exempt" "expected exit 0, got $RC: $OUT"; fi

# case7 — a validated row carrying a footnote marker is still a claim. Classification is by
# containment for exactly this reason; an enumerated list of exact statuses would exempt it silently.
proj=$(new_project)
{ map_header; row 901 "$V"; printf '| %s | happy | A thing happens | It works | %s * |\n' "$(id 902)" "$V"; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q "$(id 902)" <<< "$OUT"; then
  ok "case7-footnoted-validated-is-claimed"
else
  bad "case7-footnoted-validated-is-claimed" "expected the footnoted row to be uncovered, got $RC: $OUT"
fi

# case8 — a test still naming a RETIRED id is not dangling. The id is a permanent handle; reporting
# it would push the developer toward deleting a reference to a reserved name.
proj=$(new_project)
{ map_header; row 901 "$V"; row 903 "$V" struck; } > "$proj/specs/SCENARIOS.md"
write_test "$proj" "a.test.ts" 901 903
run_gate "$proj"
if [ "$RC" -eq 0 ]; then ok "case8-struck-reference-not-dangling"; else bad "case8-struck-reference-not-dangling" "expected exit 0, got $RC: $OUT"; fi

# case9 — a configured reference root that does not exist. Zero references would render as "every
# claimed scenario is uncovered": a catastrophic report with a trivial cause.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
run_gate "$proj" --roots nosuchdir
if [ "$RC" -eq 4 ] && grep -q 'nosuchdir' <<< "$OUT"; then
  ok "case9-missing-root"
else
  bad "case9-missing-root" "expected exit 4 naming the root, got $RC: $OUT"
fi

# case10 — the map file is absent.
proj=$(new_project)
run_gate "$proj"
if [ "$RC" -eq 3 ]; then ok "case10-absent-map"; else bad "case10-absent-map" "expected exit 3, got $RC: $OUT"; fi

# case11 — a map with no rows. "0 of 0, all clear" is arithmetically clean and semantically empty;
# reporting it as success is the failure this whole script is named after.
proj=$(new_project)
printf '# Scenario map\n\nNo rows yet.\n' > "$proj/specs/SCENARIOS.md"
run_gate "$proj"
if [ "$RC" -eq 3 ]; then ok "case11-zero-rows-is-not-a-pass"; else bad "case11-zero-rows-is-not-a-pass" "expected exit 3, got $RC: $OUT"; fi

# case12 — usage error is its own code, so a test asserting a refusal cannot pass because the script
# died of something unrelated.
proj=$(new_project)
{ map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
run_gate "$proj" --not-a-flag
if [ "$RC" -eq 2 ]; then ok "case12-usage-error"; else bad "case12-usage-error" "expected exit 2, got $RC: $OUT"; fi

# case13 — the split layout classifies identically to the single-file one. Same rows, different
# shape; the answer must not depend on where the rows live.
proj=$(new_project)
mkdir -p "$proj/specs/scenarios"
{ map_header; } > "$proj/specs/SCENARIOS.md"
{ map_header; row 901 "$V"; row 902 "$V"; } > "$proj/specs/scenarios/001-feature.md"
write_test "$proj" "a.test.ts" 901
run_gate "$proj"
if [ "$RC" -eq 1 ] && grep -q 'split' <<< "$OUT" && grep -q "$(id 902)" <<< "$OUT"; then
  ok "case13-split-layout"
else
  bad "case13-split-layout" "expected the split layout to report the same uncovered id, got $RC: $OUT"
fi

# case14 — THE LOCALE CASE. The point of this harness.
#
# macOS awk's string equality goes through the locale's collation table, and under a Swedish UTF-8
# locale the validated / tested / mapped symbols all compare EQUAL. A gate that classified with
# `awk ==` would therefore count every row as claimed, compute coverage over a denominator the map
# does not support, and report a clean run over a live gap — which is precisely the sentence
# ("100% and exit 0 the whole time") this gate was built to retire.
#
# So the gate must be immune under the locale the developer actually runs, not only under the one it
# pins for itself. The oracle is grep -c, which is byte-oriented and unaffected.
SVLOC=$(locale -a 2>/dev/null | grep -ix 'sv_SE.UTF-8' | head -1)
if [ -z "$SVLOC" ]; then
  skip "case14-locale-immunity" "no Swedish UTF-8 locale on this host — the immunity is untested here, which is not the same as proven"
else
  proj=$(new_project)
  { map_header; row 901 "$V"; row 902 "$T"; row 903 "$M"; row 904 "$V"; } > "$proj/specs/SCENARIOS.md"
  write_test "$proj" "a.test.ts" 901 902 904

  # The assertion is on the COVERAGE DENOMINATOR, not on the per-status tallies printed beside it.
  # Those tallies are counted with grep, which is byte-oriented and would survive a broken
  # classification untouched — an earlier draft of this case asserted on them and stayed green
  # through the sabotage that removes both defences, i.e. it tested grep rather than the gate.
  # The denominator is `is_claimed` counting rows, and it is the number the trap actually corrupts:
  # correct is 3 of 3 (the mapped row exempt); with the symbols collapsed it becomes 3 of 4.
  rows_out=$("$REPO_ROOT/scripts/scenario-map-rows.sh" "$proj/specs/SCENARIOS.md")
  o_claimed=$(printf '%s\n' "$rows_out" | grep -cE "\|($V|$T)\|0$")

  # LC_ALL is unset deliberately: with it set, the caller's environment would mask whether the gate
  # pins the locale itself, and the case would pass for the wrong reason.
  OUT=$(env -u LC_ALL LANG="$SVLOC" bash "$SCRIPT" --dir "$proj/specs" --quiet 2>&1)
  RC=$?
  g_claimed=$(printf '%s\n' "$OUT" | sed -n 's/^coverage: [0-9]* of \([0-9]*\) .*/\1/p')

  if [ "$g_claimed" = "$o_claimed" ] && [ "$RC" -eq 0 ]; then
    ok "case14-locale-immunity (denominator $o_claimed under $SVLOC)"
  else
    bad "case14-locale-immunity" "under $SVLOC the gate claimed ${g_claimed:-?} rows (exit $RC), oracle says $o_claimed — the status distinction collapsed"
  fi
fi

# case15 — this file must not contain a literal id token. See the header: the fixture ids are built
# at runtime precisely so that greping the repo for a real scenario id can never land here.
if grep -qE "$P-[0-9]" "$0"; then
  bad "case15-no-literal-id-in-source" "a literal id token appears in this harness — it would bind a real scenario to a fixture"
else
  ok "case15-no-literal-id-in-source"
fi

# ------------------------------------------------------------- sabotage ----
#
# One marked region at a time, on a COPY. Asserting only "the sabotaged run exits non-zero" would be
# satisfied by a copy that died of a syntax error, which is the false-green shape this row exists to
# remove — so every entry names the cases it must turn red, and the clean cases must stay green.
#
# GREEN BASELINE FIRST. With the shipped gate already red, every entry below would report "live" on
# breakage it did not cause. That is the defect 007br's FR-08 found in the register-ids falsification
# arm, and it is cheap to not repeat.
#
# TWO of the entries are "must stay GREEN". The gate carries two independent defences against the
# collation trap — the LC_ALL pin and the shell classification — and removing either one alone must
# still leave case14 passing. That is what defence in depth means, and asserting it is the only way
# to know the second defence is not decorative. Only removing BOTH may turn case14 red.

# The replacement texts passed to this are SINGLE-quoted on purpose: they are source code for the
# sabotaged copy, so `$1` and `$TMP` must reach that copy unexpanded. shellcheck's SC2016 is exactly
# backwards at those call sites, which each carry a disable directive.
replace_region() { # <src> <dst> <marker> <replacement-text>
  awk -v m="$3" -v rep="$4" '
    $0 ~ ("^[[:space:]]*# >>> " m "$") { print rep; skip = 1; next }
    $0 ~ ("^[[:space:]]*# <<< " m "$") { skip = 0; next }
    !skip { print }
  ' "$1" > "$2"
}

sab_run() { # <sabotaged-script> → SAB_OUT
  SAB_OUT=$(bash "$0" --script "$1" --no-sabotage 2>&1)
  return 0
}

expect_red() { # <label> <output> <case>...
  lbl="$1"; out="$2"; shift 2
  missing=""
  for c in "$@"; do
    grep -q "FAIL  $c" <<< "$out" || missing="$missing $c"
  done
  if [ -n "$missing" ]; then
    echo "  FAIL  sabotage/$lbl — these cases stayed GREEN:$missing"
    echo "        They therefore prove nothing about the shipped gate."
    return 1
  fi
  echo "  PASS  sabotage/$lbl — $* went red"
  return 0
}

expect_green() { # <label> <output> <case>...
  lbl="$1"; out="$2"; shift 2
  broke=""
  for c in "$@"; do
    grep -q "FAIL  $c" <<< "$out" && broke="$broke $c"
  done
  if [ -n "$broke" ]; then
    echo "  FAIL  sabotage/$lbl — these cases broke when they should not have:$broke"
    return 1
  fi
  echo "  PASS  sabotage/$lbl — $* stayed green, as defence in depth requires"
  return 0
}

if [ "$RUN_SABOTAGE" -eq 1 ] && [ "$FAIL" -eq 0 ]; then
  echo
  echo "Sabotage check — every defence must be load-bearing:"

  proj=$(new_project)
  { map_header; row 901 "$V"; } > "$proj/specs/SCENARIOS.md"
  write_test "$proj" "a.test.ts" 901
  if ! bash "$SCRIPT" --dir "$proj/specs" >/dev/null 2>&1; then
    echo "  FAIL  sabotage/baseline — the shipped gate is not green on a clean fixture."
    echo "        Without a green baseline every entry below would report breakage it did not cause."
    exit 1
  fi
  echo "  PASS  sabotage/baseline — the shipped gate is green on a clean fixture"

  SABDIR=$(mktemp -d)
  SAB_FAIL=0

  # The gate resolves its two dependencies relative to its own directory, so a copy dropped in a bare
  # temp dir dies before it classifies anything — and every entry below would then report "red" on a
  # missing file rather than on the defence it removed. That is the same false attribution the green
  # baseline above exists to prevent, one level down. Link the dependencies in; the sabotage targets
  # the gate, not its neighbours.
  ln -s "$REPO_ROOT/scripts/scenario-map-layout.sh" "$SABDIR/scenario-map-layout.sh"
  ln -s "$REPO_ROOT/scripts/scenario-map-rows.sh"   "$SABDIR/scenario-map-rows.sh"

  # (a) the classification rewritten with awk's equality operator, pin intact.
  # shellcheck disable=SC2016
  replace_region "$SCRIPT" "$SABDIR/a.sh" classify \
'is_claimed() { awk -v s="$1" -v v="✓" -v t="◐" "BEGIN { exit !(s == v || s == t) }"; }'
  sab_run "$SABDIR/a.sh"
  expect_green "awk-equality-with-pin" "$SAB_OUT" case14-locale-immunity case5-mapped-exempt || SAB_FAIL=1

  # (b) the pin removed, shell classification intact.
  replace_region "$SCRIPT" "$SABDIR/b.sh" locale-pin ':'
  sab_run "$SABDIR/b.sh"
  expect_green "pin-removed-shell-intact" "$SAB_OUT" case14-locale-immunity case5-mapped-exempt || SAB_FAIL=1

  # (c) BOTH defences removed — the collation trap is live and case14 must catch it.
  replace_region "$SCRIPT" "$SABDIR/c0.sh" locale-pin ':'
  # shellcheck disable=SC2016
  replace_region "$SABDIR/c0.sh" "$SABDIR/c.sh" classify \
'is_claimed() { awk -v s="$1" -v v="✓" -v t="◐" "BEGIN { exit !(s == v || s == t) }"; }'
  sab_run "$SABDIR/c.sh"
  if [ -z "$SVLOC" ]; then
    skip "sabotage/both-defences-removed" "no Swedish UTF-8 locale — the one entry that proves the trap is real cannot run here"
  else
    expect_red "both-defences-removed" "$SAB_OUT" case14-locale-immunity || SAB_FAIL=1
  fi

  # (d) the dangling comparison deleted.
  # shellcheck disable=SC2016
  replace_region "$SCRIPT" "$SABDIR/d.sh" dangling ': > "$TMP/dangling"'
  sab_run "$SABDIR/d.sh"
  expect_red "dangling-check-deleted" "$SAB_OUT" case3-dangling case4-both-directions || SAB_FAIL=1

  # (e) the struck exemption deleted — a retired row starts demanding a test.
  replace_region "$SCRIPT" "$SABDIR/e.sh" struck-exempt ':'
  sab_run "$SABDIR/e.sh"
  expect_red "struck-exemption-deleted" "$SAB_OUT" case6-struck-exempt || SAB_FAIL=1

  # (f) the missing-root guard removed — a typo'd root reports every scenario as uncovered.
  replace_region "$SCRIPT" "$SABDIR/f.sh" root-guard ':'
  sab_run "$SABDIR/f.sh"
  expect_red "root-guard-removed" "$SAB_OUT" case9-missing-root || SAB_FAIL=1

  # The clean case must survive every surgical sabotage. If it broke, the sabotage was wholesale and
  # the reds above would be meaningless.
  for s in a b c d e f; do
    sab_run "$SABDIR/$s.sh"
    if grep -q "FAIL  case1-clean" <<< "$SAB_OUT"; then
      echo "  FAIL  sabotage/$s — case1-clean also broke, so the sabotage was not surgical"
      SAB_FAIL=1
    fi
  done
  [ "$SAB_FAIL" -eq 0 ] && echo "  PASS  sabotage — every sabotage was surgical (case1-clean survived all six)"

  rm -rf "$SABDIR"
  [ "$SAB_FAIL" -eq 0 ] || FAIL=$((FAIL+1))
fi

echo
echo "$PASS passed, $FAIL failed, $INCONCL inconclusive"
[ "$FAIL" -gt 0 ] && { echo "failed:$FAILED_CASES"; exit 1; }
[ "$INCONCL" -gt 0 ] && exit 2
exit 0
