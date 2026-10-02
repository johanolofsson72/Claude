#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Self-test for row 075: where a heavy maintenance job runs, and how a cloud run's results come home.
#
#   bash scripts/test-workload-placement.sh
#
# Under test, in three layers:
#   P*  scripts/workload-placement.sh — the table: default, override, unknown place, CRLF, --here.
#   M*  project-maintenance.sh --placed and maintenance-due.sh — a cloud-placed job is not run or
#       stamped locally, runs in the cloud, an unknown place is a finding; the banner names the place.
#   C*  scripts/cloud-maintenance.sh against a bare remote — publish goes to claude/maintenance-results
#       and never to main; --pull imports once; a forged results file changes nothing it should not;
#       a stamp never moves backwards.
#
# Fixture-only: throwaway repos under mktemp, a bare repo as the remote. Nothing touches the network
# (cloud-setup.sh is stubbed; the real one is exercised in dry-run). bash 3.2-safe.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/workload-placement-test.$$")
PASS=0
FAIL=0
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
expect_contains() { if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "contains: $2" "$(printf '%s' "$3" | tr '\n' '|')"; fi; }
expect_absent()   { if grep -Fq -e "$2" <<< "$3"; then bad "$1" "absent: $2" "$(printf '%s' "$3" | tr '\n' '|')"; else ok "$1"; fi; }

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset CLAUDE_CODE_REMOTE

TAB=$(printf '\t')

# mkrepo NAME — a git repo with the real row-075 scripts and a register with 3 ticked rows.
mkrepo() {
  local r="$TMP/$1"; mkdir -p "$r/scripts" "$r/specs" "$r/.claude"
  ( cd "$r" && git init -q -b main . 2>/dev/null || { git init -q . && git checkout -q -b main; } )
  for f in workload-placement.sh maintenance-due.sh cloud-maintenance.sh maintenance_ledger.py; do
    cp "$DIR/$f" "$r/scripts/$f"
  done
  # An empty table, not the template's: these tests are about the mechanism, never the decision.
  printf '# fixture table\n' > "$r/scripts/workload-placement.tsv"
  printf '%s\n' '- [x] 001 — a' '- [x] 002 — b' '- [x] 003 — c' '- [ ] 004 — d' > "$r/specs/INDEX.md"
  chmod +x "$r"/scripts/*.sh
  printf '%s' "$r"
}

echo "workload-placement.sh"

R=$(mkrepo p)
WP() { ( cd "$R" && bash scripts/workload-placement.sh "$@" ); }

# P1: no line anywhere is local.
expect_eq "P1 a job with no line is local" "local" "$(WP --place mutation)"

# P2: the template table decides.
printf 'mutation\tcloud\tmeasured\n' >> "$R/scripts/workload-placement.tsv"
expect_eq "P2 template line places the job" "cloud" "$(WP --place mutation)"

# P3: the project override wins, line by line.
printf 'mutation\tlocal\tours is small\n' > "$R/.claude/workload-placement.tsv"
expect_eq "P3 project override wins" "local" "$(WP --place mutation)"
printf 'suite\tcloud\tx\n' >> "$R/scripts/workload-placement.tsv"
expect_eq "P3 an unoverridden job keeps the template's place" "cloud" "$(WP --place suite)"
rm -f "$R/.claude/workload-placement.tsv"

# P4: an unknown place is exit 3 and names the file, never a quiet local.
printf 'similarity\tclod\ttypo\n' >> "$R/scripts/workload-placement.tsv"
OUT=$(WP --place similarity 2>&1); RC=$?
expect_eq       "P4 unknown place exits 3" "3" "$RC"
expect_contains "P4 unknown place is named" "has place 'clod' in scripts/workload-placement.tsv" "$OUT"
expect_absent   "P4 unknown place does not print local" "local" "$(WP --place similarity 2>/dev/null)"

# P5: a CRLF table still reads `cloud`, not `cloud\r`.
printf 'traceability\tcloud\tcrlf\r\n' >> "$R/scripts/workload-placement.tsv"
expect_eq "P5 CRLF line reads cleanly" "cloud" "$(WP --place traceability)"
# P9 (spec 091 R7): secrets is local whatever a table says, and the table is told so.
printf 'secrets\tcloud\tplease\n' >> "$R/scripts/workload-placement.tsv"
expect_eq       "P9 secrets placed in the cloud reads local, exit 0" "local 0" "$(WP --place secrets 2>/dev/null) $?"
expect_contains "P9 the override is named" "secrets is always local" "$(WP --place secrets 2>&1 >/dev/null)"
printf 'secrets\tcloud\tproject\n' > "$R/.claude/workload-placement.tsv"
expect_eq       "P9 a project line cannot move it either" "local" "$(WP --place secrets 2>/dev/null)"
rm -f "$R/.claude/workload-placement.tsv"

# P10 (spec 091 mutation gate): a job with no line is local, exit 0.
OUT=$(WP --place no-such-job); expect_eq "P10 an unplaced job is local, exit 0" "local 0" "$OUT $?"

# P6: comments and blank lines are ignored; a commented-out line places nothing.
printf '# portability\tcloud\tno\n\n' >> "$R/scripts/workload-placement.tsv"
expect_eq "P6 a commented line places nothing" "local" "$(WP --place portability)"

# P7: --here follows CLAUDE_CODE_REMOTE exactly.
expect_eq "P7 here is local by default" "local" "$(WP --here)"
expect_eq "P7 here is cloud when CLAUDE_CODE_REMOTE=true" "cloud" "$( cd "$R" && CLAUDE_CODE_REMOTE=true bash scripts/workload-placement.sh --here)"
expect_eq "P7 any other value is local" "local" "$( cd "$R" && CLAUDE_CODE_REMOTE=1 bash scripts/workload-placement.sh --here)"

# P8: usage errors are exit 2.
( cd "$R" && bash scripts/workload-placement.sh --place >/dev/null 2>&1 ); expect_eq "P8 --place with no job exits 2" "2" "$?"
( cd "$R" && bash scripts/workload-placement.sh --bogus >/dev/null 2>&1 ); expect_eq "P8 unknown flag exits 2" "2" "$?"

# P9: --list is the effective table, override first.
printf 'mutation\tlocal\tours\n' > "$R/.claude/workload-placement.tsv"
LIST=$(WP --list)
expect_contains "P9 list shows the override's source" "mutation${TAB}local${TAB}project" "$LIST"
expect_eq "P9 list holds one line per job" "1" "$(printf '%s\n' "$LIST" | grep -c "^mutation$TAB")"
expect_absent "P9 a comment line is not a job" "#" "$LIST"

echo
echo "project-maintenance.sh --placed + maintenance-due.sh"

# mkmaint NAME — a fixture for the real project-maintenance.sh: every sibling stubbed silent, a
# mutation runner stub that leaves a marker and prints a passing score.
mkmaint() {
  local d; d=$(mkrepo "$1")
  cp "$DIR/project-maintenance.sh" "$d/scripts/"
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/project-freshness.sh"
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/prune-agent-worktrees.sh"
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/validate-portability.sh"
  : > "$d/scripts/portability_audit.py"
  printf '#!/bin/bash\ntouch "$(git rev-parse --show-toplevel)/.mutation-ran"\necho "mutation score 91%%"\n' > "$d/scripts/run-mutation-gate.sh"
  chmod +x "$d"/scripts/*.sh
  printf '%s' "$d"
}
MAINT() { local d=$1; shift; ( cd "$d" && env "$@" bash scripts/project-maintenance.sh --full --placed 2>&1 ); }

# M1: placed in the cloud, run locally with --placed → not run, not stamped, and said so.
M=$(mkmaint m1)
printf 'mutation\tcloud\tmeasured\n' >> "$M/scripts/workload-placement.tsv"
OUT=$(MAINT "$M")
expect_eq       "M1 cloud-placed mutation does not run locally" "no" "$([ -f "$M/.mutation-ran" ] && echo yes || echo no)"
expect_contains "M1 the pass says where it runs" "mutation runs in Claude cloud" "$OUT"
expect_absent   "M1 no 're-run with --full' advice for a job placed away" "re-run with --full" "$OUT"
expect_eq       "M1 not stamped" "" "$(cd "$M" && bash scripts/maintenance-due.sh --state | grep '^mutation')"

# M2: same table, in the cloud → runs and is stamped.
OUT=$(MAINT "$M" CLAUDE_CODE_REMOTE=true)
expect_eq "M2 cloud-placed mutation runs in the cloud" "yes" "$([ -f "$M/.mutation-ran" ] && echo yes || echo no)"
expect_contains "M2 stamped in the cloud" "mutation" "$(cd "$M" && bash scripts/maintenance-due.sh --state | cut -f1)"

# M3: without --placed nothing changes — an explicit --full runs everything.
M=$(mkmaint m3)
printf 'mutation\tcloud\tmeasured\n' >> "$M/scripts/workload-placement.tsv"
( cd "$M" && bash scripts/project-maintenance.sh --full >/dev/null 2>&1 )
expect_eq "M3 plain --full still runs a cloud-placed job" "yes" "$([ -f "$M/.mutation-ran" ] && echo yes || echo no)"

# M4: an unknown place is a finding and the job does not run.
M=$(mkmaint m4)
printf 'mutation\tcluod\ttypo\n' >> "$M/scripts/workload-placement.tsv"
OUT=$(MAINT "$M"); RC=$?
expect_eq       "M4 unknown place: job not run" "no" "$([ -f "$M/.mutation-ran" ] && echo yes || echo no)"
expect_contains "M4 unknown place is a finding" "[PLACEMENT] mutation NOT RUN" "$OUT"
expect_eq       "M4 the pass is red" "1" "$RC"
# The only difference from a pass with the job placed away is the bad line: exactly one more finding.
# Baseline: the same job placed away, so it does not run in either pass.
CLEAN=$(mkmaint m4clean); printf 'mutation\tcloud\tx\n' >> "$CLEAN/scripts/workload-placement.tsv"; CLEAN_OUT=$(MAINT "$CLEAN")
count_of() { sed -n 's/^project-maintenance: \([0-9][0-9]*\) finding(s).*/\1/p' <<< "$1" | sed -n 1p; }
expect_eq "M4 the unknown place adds exactly one finding" "$(( $(count_of "$CLEAN_OUT" | grep . || echo 0) + 1 ))" "$(count_of "$OUT")"

# M5: a local-placed job runs locally under --placed.
M=$(mkmaint m5)
printf 'mutation\tlocal\tsmall\n' >> "$M/scripts/workload-placement.tsv"
MAINT "$M" >/dev/null
expect_eq "M5 local-placed job runs locally" "yes" "$([ -f "$M/.mutation-ran" ] && echo yes || echo no)"

# M6: the due banner names the cloud and the two halves; with nothing cloud-placed it is unchanged.
M=$(mkmaint m6)
OUT=$(cd "$M" && bash scripts/maintenance-due.sh --brief)
expect_contains "M6 nothing placed: banner unchanged" "Run now: bash scripts/project-maintenance.sh --full" "$OUT"
expect_absent   "M6 nothing placed: no cloud line" "Claude cloud" "$OUT"
printf 'mutation\tcloud\tmeasured\n' >> "$M/scripts/workload-placement.tsv"
OUT=$(cd "$M" && bash scripts/maintenance-due.sh --brief)
expect_contains "M6 cloud job is marked" "mutation kill rate (Stryker) (Claude cloud) — never run in this project" "$OUT"
expect_contains "M6 cloud job names its place" "(Claude cloud)" "$OUT"
expect_contains "M6 local half uses --placed" "--full --placed" "$OUT"
expect_contains "M6 the pull is named" "cloud-maintenance.sh --pull" "$OUT"
printf 'suite\tclod\tx\n' >> "$M/scripts/workload-placement.tsv"
expect_contains "M6 unknown place is shown, not hidden" "place unknown" "$(cd "$M" && bash scripts/maintenance-due.sh --brief)"

# M7: --stamp-as keeps the run's own values and never goes backwards.
M=$(mkmaint m7)
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-09-01 2 4 )
expect_eq "M7 stamp-as writes the given values" "mutation${TAB}2026-09-01${TAB}2${TAB}4" "$(cd "$M" && bash scripts/maintenance-due.sh --state | grep '^mutation')"
( cd "$M" && bash scripts/maintenance-due.sh --stamp mutation )
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-08-01 1 4 2>/dev/null )
expect_eq "M7 an older import does not move the stamp back" "3" "$(cd "$M" && bash scripts/maintenance-due.sh --state | awk -F'\t' '$1=="mutation"{print $3}')"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation yesterday 5 9 >/dev/null 2>&1 ); expect_eq "M7 a bad date is exit 2" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-09-01 x 9 >/dev/null 2>&1 ); expect_eq "M7 a bad count is exit 2" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-09-01 >/dev/null 2>&1 ); expect_eq "M7 missing fields is exit 2" "2" "$?"
# The adversarial review's forgeries (finding 1): each is refused and leaves the stamp alone.
BEFORE=$(cd "$M" && bash scripts/maintenance-due.sh --state)
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as secrets "" "" "" >/dev/null 2>&1 ); expect_eq "M7 empty fields are exit 2, not a stamp for today" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as secrets 2099-12-31 3 4 >/dev/null 2>&1 ); expect_eq "M7 a future date is exit 2" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as secrets 2026-13-45 3 4 >/dev/null 2>&1 ); expect_eq "M7 an impossible date is exit 2" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-09-01 999999 4 >/dev/null 2>&1 ); expect_eq "M7 a done count above the register is exit 2" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-09-01 3 999999 >/dev/null 2>&1 ); expect_eq "M7 a row count above the register is exit 2" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-09-01 "" 4 >/dev/null 2>&1 ); expect_eq "M7 an empty done count is exit 2" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-09-01 99999999999999999999 1 >/dev/null 2>&1 ); expect_eq "M7 a count past int64 is exit 2, not an overflow that reads false" "2" "$?"
( cd "$M" && bash scripts/maintenance-due.sh --stamp-as mutation 2026-09-01 1 99999999999999999999 >/dev/null 2>&1 ); expect_eq "M7 a row count past int64 is exit 2" "2" "$?"
expect_eq "M7 no forgery changed the state" "$BEFORE" "$(cd "$M" && bash scripts/maintenance-due.sh --state)"
# A job name is matched whole: '.*' is not a job, and must not wipe the other stamps.
( cd "$M" && bash scripts/maintenance-due.sh --stamp '.*' >/dev/null 2>&1 ); expect_eq "M7 a regex job name is exit 2" "2" "$?"
expect_eq "M7 a regex job name wipes nothing" "$BEFORE" "$(cd "$M" && bash scripts/maintenance-due.sh --state)"

echo
echo "cloud-maintenance.sh"

BARE="$TMP/remote.git"
git init -q --bare "$BARE"
# The cloud checkout: real cloud-maintenance.sh, a stub pass that records one ledger line and one stamp.
C=$(mkrepo cloud)
printf '%s\n' '#!/bin/bash' 'cd "$(git rev-parse --show-toplevel)"' \
  'python3 scripts/maintenance_ledger.py run mutation -- true' \
  'bash scripts/maintenance-due.sh --stamp mutation' \
  'echo "pass: placed=$*"' > "$C/scripts/project-maintenance.sh"
printf '#!/bin/bash\necho "cloud-setup: stub" >&2\n' > "$C/scripts/cloud-setup.sh"
chmod +x "$C"/scripts/*.sh
( cd "$C" && git add -A && git commit -qm init && git remote add origin "$BARE" && git push -q origin main )
MAIN_BEFORE=$(git --git-dir="$BARE" rev-parse refs/heads/main)

# C1: outside the cloud, without --force-local, it refuses.
OUT=$(cd "$C" && bash scripts/cloud-maintenance.sh 2>&1); RC=$?
expect_eq       "C1 refuses outside the cloud" "2" "$RC"
expect_contains "C1 says what to run locally instead" "--full --placed" "$OUT"

# C2: a run publishes one results file to claude/maintenance-results, and main is untouched.
OUT=$(cd "$C" && bash scripts/cloud-maintenance.sh --force-local 2>&1); RC=$?
expect_eq       "C2 publish exit 0" "0" "$RC"
expect_contains "C2 the pass ran with --placed" "pass: placed=--full --suite --placed" "$OUT"
FILES=$(git --git-dir="$BARE" ls-tree --name-only refs/heads/claude/maintenance-results .claude/cloud-results/ 2>/dev/null)
expect_eq "C2 one results file on the branch" "1" "$(printf '%s\n' "$FILES" | grep -c .)"
expect_eq "C2 main is never written" "$MAIN_BEFORE" "$(git --git-dir="$BARE" rev-parse refs/heads/main)"
BODY=$(git --git-dir="$BARE" show "refs/heads/claude/maintenance-results:$(printf '%s\n' "$FILES" | head -1)")
expect_contains "C2 the file carries the ledger line, as cloud" "${TAB}cloud${TAB}mutation${TAB}" "$BODY"
expect_contains "C2 the file carries the stamp" "stamp${TAB}mutation${TAB}" "$BODY"
expect_eq "C2 nothing but ledger and stamp lines" "0" "$(printf '%s\n' "$BODY" | grep -cvE "^(ledger|stamp)$TAB")"
expect_eq "C2 the session's checkout is still on main" "main" "$(cd "$C" && git rev-parse --abbrev-ref HEAD)"
expect_eq "C2 the session's tree is clean" "" "$(cd "$C" && git status --porcelain -- . ':!.claude/state' ':!.claude/.maintenance-state')"

# C3: a second run appends a second file to the existing branch.
( cd "$C" && bash scripts/cloud-maintenance.sh --force-local >/dev/null 2>&1 )
expect_eq "C3 two runs, two files" "2" "$(git --git-dir="$BARE" ls-tree --name-only refs/heads/claude/maintenance-results .claude/cloud-results/ | grep -c .)"

# The laptop: a clone of main, with nothing stamped.
L="$TMP/laptop"; git clone -q "$BARE" "$L" 2>/dev/null; ( cd "$L" && git checkout -q main 2>/dev/null )

# 091-AC-4 / R7: before this laptop places anything in the cloud, a pull imports the history (ledger)
# and marks no job done: the run's mutation stamp is skipped and named.
A4=$(mktemp -d "$TMP/ac4.XXXXXX"); git clone -q "$BARE" "$A4/l" 2>/dev/null; ( cd "$A4/l" && git checkout -q main 2>/dev/null )
OUT=$(cd "$A4/l" && bash scripts/cloud-maintenance.sh --pull 2>&1)
expect_contains "091-AC-4 a stamp for a job placed locally is skipped and named" "stamp mutation — mutation runs locally here" "$OUT"
expect_eq       "091-AC-4 no mutation stamp" "" "$(cd "$A4/l" && bash scripts/maintenance-due.sh --state | grep '^mutation')"
expect_eq       "091-AC-4 the ledger still imports" "2" "$(grep -c "${TAB}cloud${TAB}mutation${TAB}" "$A4/l/.claude/state/maintenance-runs.tsv")"

# The laptop places mutation and suite in the cloud (its own decision), so their stamps count from here on.
printf 'mutation\tcloud\tx\nsuite\tcloud\tx\nsecrets\tcloud\tx\n' >> "$L/scripts/workload-placement.tsv"

# C4: pull imports both files: ledger lines appended, stamp applied with the run's own counts.
OUT=$(cd "$L" && bash scripts/cloud-maintenance.sh --pull 2>&1)
expect_contains "C4 pull reports what it imported" "imported 2 result file(s)" "$OUT"
expect_contains "C4 pull names each stamp" "stamped mutation from" "$OUT"
expect_eq "C4 two cloud ledger lines" "2" "$(grep -c "${TAB}cloud${TAB}mutation${TAB}" "$L/.claude/state/maintenance-runs.tsv")"
expect_eq "C4 the stamp carries the cloud's done count" "3" "$(cd "$L" && bash scripts/maintenance-due.sh --state | awk -F'\t' '$1=="mutation"{print $3}')"

# C5: a second pull is a no-op.
OUT=$(cd "$L" && bash scripts/cloud-maintenance.sh --pull 2>&1)
expect_contains "C5 second pull imports nothing" "imported 0 result file(s)" "$OUT"
expect_eq "C5 no duplicate ledger lines" "2" "$(grep -c "${TAB}cloud${TAB}mutation${TAB}" "$L/.claude/state/maintenance-runs.tsv")"

# C6: a forged results file — unknown stamp job, a shell payload, a local place, a short line.
F="$TMP/forge"; git clone -q -b claude/maintenance-results "$BARE" "$F" 2>/dev/null
printf 'stamp\tdeploy\t2026-10-01\t99\t99\nledger\t2026-10-01T00:00:00+00:00\tcloud\t$(touch pwned)\t1.0\t0\t1\t1\t1\t3\nledger\t2026-10-01T00:00:00+00:00\tlocal-darwin\tmutation\t1.0\t0\t1\t1\t1\t3\nledger\tshort\nexec\trm -rf /\n' > "$F/.claude/cloud-results/20261001T000000Z-f0f0.tsv"
( cd "$F" && git add -A && git commit -qm forge && git push -q origin HEAD:claude/maintenance-results )
BEFORE=$(cat "$L/.claude/state/maintenance-runs.tsv")
OUT=$(cd "$L" && bash scripts/cloud-maintenance.sh --pull 2>&1)
expect_contains "C6 the forged file is read" "imported 1 result file(s), 5 line(s) skipped" "$OUT"
expect_eq "C6 no ledger line imported from it" "$BEFORE" "$(cat "$L/.claude/state/maintenance-runs.tsv")"
expect_eq "C6 no unknown stamp" "" "$(cd "$L" && bash scripts/maintenance-due.sh --state | grep '^deploy')"
expect_eq "C6 nothing executed" "no" "$([ -e "$L/pwned" ] || [ -e "$L/scripts/pwned" ] && echo yes || echo no)"

# C7: an odd file name on the branch is skipped, not imported.
printf 'stamp\tsuite\t2026-10-01\t3\t4\n' > "$F/.claude/cloud-results/bad name.tsv"
( cd "$F" && git add -A && git commit -qm odd && git push -q origin HEAD:claude/maintenance-results )
OUT=$(cd "$L" && bash scripts/cloud-maintenance.sh --pull 2>&1)
expect_contains "C7 odd file name is skipped" "unexpected file name" "$OUT"
expect_eq "C7 its stamp is not applied" "" "$(cd "$L" && bash scripts/maintenance-due.sh --state | grep '^suite')"

# C11: the review's attacks on the pull, in one push — a file named `-v` (grep option injection), a
# symlink with a valid name, a file over the size cap, and stamps with an empty date, a future date and
# a huge count. A legitimate file sorted after them must still import.
printf 'x\n' > "$F/.claude/cloud-results/-v"
ln -s /etc/passwd "$F/.claude/cloud-results/20261001T000001Z-aa.tsv"
awk 'BEGIN { for (i = 0; i < 9000; i++) print "stamp\tsuite\t2026-10-01\t3\t4" }' > "$F/.claude/cloud-results/20261001T000002Z-bb.tsv"
printf 'stamp\tsecrets\nstamp\tsecrets\t2099-12-31\t3\t4\nstamp\tmutation\t2026-10-01\t999999\t999999\n' > "$F/.claude/cloud-results/20261001T000003Z-cc.tsv"
printf 'stamp\tsuite\t2026-10-01\t3\t4\n' > "$F/.claude/cloud-results/20261001T000004Z-dd.tsv"
( cd "$F" && git add -A && git commit -qm attacks && git push -q origin HEAD:claude/maintenance-results )
OUT=$(cd "$L" && bash scripts/cloud-maintenance.sh --pull 2>&1)
expect_contains "C11 -v is an unexpected name, not a grep flag" "-v — unexpected file name" "$OUT"
expect_contains "C11 a symlink is not a plain file" "20261001T000001Z-aa.tsv — not a plain file" "$OUT"
expect_contains "C11 an oversized file is skipped" "20261001T000002Z-bb.tsv — " "$OUT"
expect_contains "C11 the size cap is named" "byte cap" "$OUT"
expect_eq "C11 no forged secrets stamp" "" "$(cd "$L" && bash scripts/maintenance-due.sh --state | grep '^secrets')"
expect_contains "091-AC-4 a secrets stamp is skipped and named, even with secrets placed in the cloud" "stamp secrets — secrets runs locally here" "$OUT"
expect_eq "C11 the mutation stamp is not poisoned" "3" "$(cd "$L" && bash scripts/maintenance-due.sh --state | awk -F'\t' '$1=="mutation"{print $3}')"
expect_contains "C11 the legitimate file after them still imports" "stamped suite from 20261001T000004Z-dd.tsv" "$OUT"
expect_absent "C11 /etc/passwd never reaches the ledger" "root:" "$(cat "$L/.claude/state/maintenance-runs.tsv")"

# C12: a run publishes only the stamps it wrote, not ones already in the state file.
P=$(mkrepo cloud-prior)
cp "$C/scripts/project-maintenance.sh" "$C/scripts/cloud-setup.sh" "$P/scripts/"
( cd "$P" && bash scripts/maintenance-due.sh --stamp secrets && git add -A && git commit -qm init && git remote add origin "$BARE" )
( cd "$P" && bash scripts/cloud-maintenance.sh --force-local >/dev/null 2>&1 )
NEWEST=$(git --git-dir="$BARE" ls-tree --name-only refs/heads/claude/maintenance-results .claude/cloud-results/ | grep -E '^.claude/cloud-results/[0-9]{8}T' | sort | tail -1)
BODY=$(git --git-dir="$BARE" show "refs/heads/claude/maintenance-results:$NEWEST")
expect_contains "C12 this run's stamp is published" "stamp${TAB}mutation${TAB}" "$BODY"
expect_absent   "C12 an older stamp is not republished" "stamp${TAB}secrets${TAB}" "$BODY"

# C13 (spec 091 mutation gate): an unknown argument is exit 2 and named.
OUT=$(cd "$L" && bash scripts/cloud-maintenance.sh --bogus 2>&1); expect_eq "C13 an unknown argument exits 2" "2" "$?"
expect_contains "C13 and is named" "unknown argument '--bogus'" "$OUT"

# C8: no results branch yet → a plain sentence and exit 0.
E="$TMP/empty-remote.git"; git init -q --bare "$E"
L2=$(mkrepo laptop2); ( cd "$L2" && git remote add origin "$E" )
OUT=$(cd "$L2" && bash scripts/cloud-maintenance.sh --pull 2>&1); RC=$?
expect_eq       "C8 no branch: exit 0" "0" "$RC"
expect_contains "C8 no branch: says so" "no cloud results yet" "$OUT"

# C9: a failed setup is published as a failed run, so the laptop sees a failure, not silence.
S=$(mkrepo cloud-setup-fails)
cp "$C/scripts/project-maintenance.sh" "$S/scripts/"
printf '#!/bin/bash\nexit 1\n' > "$S/scripts/cloud-setup.sh"; chmod +x "$S"/scripts/*.sh
( cd "$S" && git add -A && git commit -qm init && git remote add origin "$BARE" )
( cd "$S" && bash scripts/cloud-maintenance.sh --force-local >/dev/null 2>&1 ); RC=$?
expect_eq "C9 setup failure exits 2" "2" "$RC"
OUT=$(cd "$L" && bash scripts/cloud-maintenance.sh --pull 2>&1)
expect_eq "C9 the failure arrives as a setup ledger line with rc 1" "1" "$(awk -F'\t' '$2=="cloud" && $3=="setup" && $5=="1"' "$L/.claude/state/maintenance-runs.tsv" | grep -c .)"

# C10: cloud-setup.sh does nothing without a .NET project, and plans the install with one (dry run).
N=$(mkrepo setup-none); cp "$DIR/cloud-setup.sh" "$N/scripts/"
OUT=$(cd "$N" && bash scripts/cloud-setup.sh 2>&1); RC=$?
expect_eq       "C10 no .NET project: exit 0" "0" "$RC"
expect_contains "C10 no .NET project: says so" "nothing to install" "$OUT"
: > "$N/App.sln"; printf '{ "sdk": { "version": "9.0.100" } }\n' > "$N/global.json"
OUT=$(cd "$N" && PATH="/usr/bin:/bin" DOTNET_INSTALL_DIR="$TMP/no-dotnet" CLOUD_SETUP_DRY_RUN=1 bash scripts/cloud-setup.sh 2>&1); RC=$?
expect_eq       "C10 dry run exits 0" "0" "$RC"
expect_contains "C10 the channel comes from global.json" "--channel 9.0" "$OUT"
expect_contains "C10 prints the PATH line" "export PATH=\"$TMP/no-dotnet:" "$OUT"

echo
echo "workload-placement: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
