#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-maintenance-due.sh — the due engine must be right about what is owed, and honest about what
# it has never seen.
#
# The two failures this guards against are the ones the mechanism exists to remove:
#   1. a job reported as not-due when it is (silence that looks like health), and
#   2. "never run" rendering the same as "run and clean" — trap 4 in mutation-timeouts.md.
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$SCRIPT_DIR/maintenance-due.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

[ -f "$SUT" ] || { echo "maintenance-due.sh not found — this harness would be vacuous"; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkfix() {
  d="$WORK/$1"; mkdir -p "$d/specs" "$d/.claude" "$d/scripts"
  ( cd "$d" && git init -q . >/dev/null 2>&1 )
  cp "$SUT" "$d/scripts/"
  { echo "# Spec register"; echo; echo "## Specs"; echo; } > "$d/specs/INDEX.md"
  shift
  for r in "$@"; do echo "$r" >> "$d/specs/INDEX.md"; done
  printf '%s' "$d"
}
run() { ( cd "$1" && shift; bash scripts/maintenance-due.sh "$@" 2>&1 ); }
rc_of() { ( cd "$1" && shift; bash scripts/maintenance-due.sh "$@" >/dev/null 2>&1; echo $? ); }

# 1. A virgin project owes everything, and says "never run" rather than a zero.
D=$(mkfix v "- [x] 001 — a — spec-only — x" "- [ ] 002 — b — spec-only — y")
OUT=$(run "$D")
grep -q 'never run' <<< "$OUT" && ok "never-run is named as such, not reported as 0 days" \
  || bad "never-run is not distinguished from a clean run"
[ "$(rc_of "$D" --any)" = 0 ] && ok "--any exits 0 when something is due" || bad "--any wrong on a virgin project"

# 2. Stamping clears exactly one job and nothing else.
run "$D" --stamp secrets >/dev/null
OUT=$(run "$D" --brief)
grep -q 'secrets' <<< "$OUT" && bad "a stamped job is still reported due" || ok "a stamped job stops being due"
grep -q 'mutation' <<< "$OUT" && ok "the other jobs are untouched by one stamp" \
  || bad "stamping one job cleared others"

# 3. The spec trigger is the register, not the clock. Stamp everything, then tick a spec.
for j in secrets suite mutation similarity; do run "$D" --stamp "$j" >/dev/null; done
[ "$(rc_of "$D" --any)" = 1 ] && ok "fully stamped project owes nothing" || bad "still due after stamping all four"
echo "- [x] 003 — c — spec-only — z" >> "$D/specs/INDEX.md"
OUT=$(run "$D" --brief)
grep -q 'full test suite' <<< "$OUT" && ok "one ticked spec makes the suite due again" \
  || bad "a ticked spec did not make the suite due"
grep -q 'mutation' <<< "$OUT" && bad "one spec should not reach the mutation threshold of 5" \
  || ok "mutation stays undue at 1 of 5 specs"

# 4. Five specs reaches the mutation cadence — the same 5 as the hardening checkpoint.
for n in 004 005 006 007; do echo "- [x] $n — c$n — spec-only — z" >> "$D/specs/INDEX.md"; done
grep -q 'mutation' <<< "$(run "$D" --brief)" && ok "five ticked specs makes the mutation gate due" \
  || bad "mutation gate not due after 5 specs"

# 5. A project with no register still answers rather than crashing.
D2=$(mkfix noreg); rm -f "$D2/specs/INDEX.md"
[ "$(rc_of "$D2" --any)" = 0 ] && ok "a project with no register still reports (never-run)" \
  || bad "no register broke the engine"

# 6. An unknown job is refused, not silently stamped.
[ "$(rc_of "$D" --stamp bogus)" = 2 ] && ok "an unknown job name is refused (exit 2)" \
  || bad "an unknown job name was accepted"

# 7. The state file holds one line per job, not an append-only log.
run "$D" --stamp secrets >/dev/null; run "$D" --stamp secrets >/dev/null
N=$(grep -c '^secrets' "$D/.claude/.maintenance-state" 2>/dev/null || echo 0)
[ "$N" = 1 ] && ok "re-stamping rewrites the row rather than appending" \
  || bad "state file grew to $N rows for one job"

# 8. Spec 093 (F110, R3): the banner names what the due heavy jobs cost here, from the ledger, and a due
# suite puts --suite on the command (--full alone never runs it).
D=$(mkfix e "- [x] 001 — a — spec-only — x")
cp "$SCRIPT_DIR/maintenance_ledger.py" "$D/scripts/"
OUT=$(run "$D" --brief)
grep -q 'Expected: .*mutation, suite unmeasured' <<< "$OUT" && ok "093-SC-B an empty ledger says unmeasured, never silent" \
  || bad "093-SC-B empty ledger: '$(grep Expected <<< "$OUT")'"
grep -q 'Run now: bash scripts/project-maintenance.sh --full --suite' <<< "$OUT" && ok "093 R3 a due suite puts --suite on the command" \
  || bad "093 R3 banner command lacks --suite"
PLACE=$(python3 -c 'import os; print("local-" + os.uname().sysname.lower())')
mkdir -p "$D/.claude/state"
{ printf '2026-10-01T00:00:00Z\t%s\tmutation\t3600\t0\t300\t4\t1.0\t1\n' "$PLACE"
  printf '2026-10-01T00:00:00Z\t%s\tsuite\t1200\t0\t300\t4\t1.0\t1\n' "$PLACE"
  printf '2026-10-01T00:00:00Z\t%s\tsuite\t1800\t1\t300\t4\t1.0\t1\n' "$PLACE"
  printf '2026-10-01T00:00:00Z\tcloud\tsuite\t9999\t0\t300\t4\t1.0\t1\n'; } > "$D/.claude/state/maintenance-runs.tsv"
OUT=$(run "$D" --brief)
grep -qF "Expected: ~1h25m by this machine's ledger — mutation ~60m (1 run), suite ~25m (2 runs)" <<< "$OUT" \
  && ok "093-SC-B the ledger's medians at this place, red runs counted, cloud runs not" \
  || bad "093-SC-B with a ledger: '$(grep Expected <<< "$OUT")'"
run "$D" --stamp suite >/dev/null; run "$D" --stamp mutation >/dev/null
OUT=$(run "$D" --brief)
grep -q 'Expected' <<< "$OUT" && bad "093 no heavy job due, yet an Expected line" || ok "093 no heavy job due — no Expected line"
grep -q -- '--suite' <<< "$OUT" && bad "093 R3 --suite printed with the suite not due" || ok "093 R3 suite not due — no --suite"

echo "maintenance-due: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
