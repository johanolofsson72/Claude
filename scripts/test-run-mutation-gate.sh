#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Self-test for scripts/run-mutation-gate.sh (spec 085).
#
#   bash scripts/test-run-mutation-gate.sh              # the arms against the real runner
#   bash scripts/test-run-mutation-gate.sh --sabotage   # every arm against its mutant of the runner
#
# Every case runs the runner inside a throwaway git repo with a two-line module, a test that kills
# one mutant and misses the other, a module whose mutant sleeps past its limit, and a red test. The
# real target table is never used (MUTATION_TARGETS), so this stays under a minute.
# RUNNER_UNDER_TEST selects the runner (the sabotage mode sets it per mutant). bash 3.2-safe.

set -u
cd "$(dirname "$0")/.." || exit 1
RUNNER="${RUNNER_UNDER_TEST:-$PWD/scripts/run-mutation-gate.sh}"
REPO=$PWD
[ -f "$RUNNER" ] || { echo "FAIL: runner not found at $RUNNER"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------- sabotage mode
# id@@exact text in the runner (must occur once)@@replacement@@arm that must go red
MUTANTS='S1@@      elif [ "$3" -eq 1 ]; then _v=timeout@@      elif [ "$3" -eq 1 ]; then _v=killed; break@@arm_timeout_is_not_a_kill
S2@@if [ -n "$RED" ]; then@@if false; then@@arm_red_baseline_is_unmeasured
S3@@    rm -rf "$RUN"
  fi@@    :
  fi@@arm_leaves_nothing
S4@@            elif c == "#" and@@            elif False and@@arm_only_live_code
S5@@        if "# mutant-equivalent:" in line:@@        if False:@@arm_only_live_code
S6@@  export GIT_INDEX_FILE="$RUN/index" GIT_OBJECT_DIRECTORY="$RUN/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$OBJ"@@  export GIT_INDEX_FILE="$RUN/index"@@arm_leaves_nothing
S7@@    sys.exit(0 if score >= brk else 1)@@    sys.exit(0)@@arm_score_and_report
S8@@safe_path() { case "$1" in /*|*..*|@@safe_path() { case "$1" in *.never-a-path|@@arm_arguments
S9@@    [ -L "$1/$_p" ] && return 1@@    false && return 1@@arm_hostile_paths
S10@@  //|"$HOME_P/"|"$ROOT"/*) die@@  //) die@@arm_hostile_paths
S12@@  //|"$HOME_P/"|"$ROOT"/*) die@@  "$HOME_P/"|"$ROOT"/*) die@@arm_hostile_paths
S11@@  [ -d "$1" ] && [ -f "$1/$3" ] || { echo "0 0 2"; return; }@@  :@@arm_infra_is_not_a_kill'

if [ "${1:-}" = "--sabotage" ]; then
  RED=0; STILL=""; STALE=""
  MUTANTS="$MUTANTS" python3 - "$RUNNER" "$TMP" <<'PYEOF' > "$TMP/plan" || { echo "FAIL: sabotage plan"; exit 1; }
import os, re, sys
src, tmp = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
for rec in re.split(r'\n(?=S\d+@@)', os.environ["MUTANTS"]):
    mid, old, new, arm = rec.split("@@")
    n = text.count(old)
    if n != 1:
        print(f"{mid} STALE {arm} {n}"); continue
    out = f"{tmp}/{mid}.sh"
    open(out, "w", encoding="utf-8").write(text.replace(old, new, 1))
    print(f"{mid} OK {arm} {out}")
PYEOF
  while read -r mid state arm path; do
    if [ "$state" = STALE ]; then STALE="$STALE $mid(matches:$path)"; continue; fi
    if RUNNER_UNDER_TEST="$path" ARMS_ONLY="$arm" bash "$0" >"$TMP/$mid.out" 2>&1; then
      STILL="$STILL $mid($arm)"
    else
      RED=$((RED + 1)); echo "  red  $mid ($arm)"
    fi
  done < "$TMP/plan"
  [ -n "$STALE" ] && echo "FAIL: stale sabotage anchors:$STALE"
  [ -n "$STILL" ] && echo "FAIL: arms still green against their mutant:$STILL"
  echo "sabotage: $RED killed"
  [ -z "$STALE" ] && [ -z "$STILL" ]
  exit $?
fi

# ---------------------------------------------------------------------------- fixture
FIX="$TMP/repo"
mkdir -p "$FIX/scripts"
cd "$FIX" || exit 1
git init -q . && git config user.email t@t && git config user.name t
cat > scripts/calc.sh <<'EOF'
#!/bin/bash
# a comment that says [ "$1" -eq 0 ] && exit 0
if [ "$1" -eq 0 ]; then echo zero; else echo other; fi
if [ "$1" -gt 5 ]; then echo big; fi
cat <<'DOC'
[ "$1" -eq 1 ] && echo heredoc
DOC
echo "quoted -eq text"
[ -n "$1" ] || exit 3  # mutant-equivalent: fixture marker
EOF
cat > scripts/slow.sh <<'EOF'
#!/bin/bash
if [ "${1:-0}" -eq 0 ]; then echo ok; else sleep 30; fi
EOF
cat > scripts/red.sh <<'EOF'
#!/bin/bash
[ "${1:-0}" -eq 0 ] && echo red
EOF
cat > scripts/test-slow.sh <<'EOF'
[ "$(bash scripts/slow.sh 0)" = ok ]
EOF
cat > scripts/test-red.sh <<'EOF'
exit 1
EOF
cat > scripts/test-hang.sh <<'EOF'
sleep 30
EOF
cat > targets <<'EOF'
# fixture table
scripts/calc.sh scripts/test-calc.sh
scripts/slow.sh scripts/test-slow.sh
scripts/red.sh scripts/test-red.sh
EOF
git add scripts/calc.sh scripts/slow.sh scripts/red.sh scripts/test-slow.sh scripts/test-red.sh scripts/test-hang.sh targets
git commit -qm fixture
# The killing test is untracked on purpose: the snapshot must carry it (Q17).
cat > scripts/test-calc.sh <<'EOF'
[ "$(bash scripts/calc.sh 0 | head -1)" = zero ]
EOF

WORK="$TMP/work"
run() { MUTATION_TARGETS="$FIX/targets" MUTATION_WORKDIR="$WORK" MUTATION_MIN_LIMIT=3 MUTATION_LIMIT_FACTOR=1 \
          bash "$RUNNER" --jobs 2 "$@"; }
# HEAD, the index, the status and the object store: the snapshot writes none of them (security review).
state() { printf '%s|%s|%s|%s' "$(git rev-parse HEAD)" "$(git ls-files -s | shasum)" "$(git status --porcelain | shasum)" \
            "$(git count-objects | cut -d' ' -f1)"; }
leftovers() { printf 'wt=%s runs=%s' "$(git worktree list | grep -c .)" "$(find "$WORK" -mindepth 1 -maxdepth 1 2>/dev/null | grep -c .)"; }
want() { [ -z "${ARMS_ONLY:-}" ] || [ "$ARMS_ONLY" = "$1" ]; }

# ---------------------------------------------------------------------------- arms
arm_score_and_report() {
  echo "-- 085-AC-1 shape: score line, survivors, JSON report"
  out=$(run --lines scripts/calc.sh:3,4 2>/dev/null); rc=$?
  has  "a module line with killed/valid" "$out" "scripts/calc.sh: 1/2 killed (50.0%)"
  has  "the survivor is named with its operator" "$out" "survived scripts/calc.sh:4 arith_compare '-gt' -> '-le'"
  has  "the contract phrase project-maintenance greps" "$out" "mutation score 50.0%"
  same "below the default break 80 exits 1" "$rc" 1
  out=$(MUTATION_BREAK=50 run --lines scripts/calc.sh:3,4 2>/dev/null); rc=$?
  same "at the break exits 0" "$rc" 0
  J="$FIX/.claude/state/mutation/mutation-report.json"
  js=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); f=d["files"]["scripts/calc.sh"]; print(d["schemaVersion"], sorted(m["status"] for m in f["mutants"]), f["mutants"][0]["location"]["start"])' "$J" 2>&1)
  has "the report is Stryker schema 1 with per-mutant status" "$js" "1 ['Killed', 'Survived'] {'line': 3, 'column': 11}"
}

arm_timeout_is_not_a_kill() {
  echo "-- 085-AC-2: a timeout is reported and is not a kill"
  out=$(run --lines scripts/slow.sh:2 2>/dev/null); rc=$?
  has  "the mutant is reported as a timeout" "$out" "timeout scripts/slow.sh:2 arith_compare '-eq' -> '-ne'"
  has  "and counted as not killed" "$out" "mutation score 0.0%"
  same "exit 1, not a pass" "$rc" 1
  js=$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["files"]["scripts/slow.sh"]["mutants"][0]; print(m["status"], m.get("statusReason",""))' "$FIX/.claude/state/mutation/mutation-report.json" 2>&1)
  has "the JSON writes it as Survived with the reason" "$js" "Survived timeout"
}

arm_red_baseline_is_unmeasured() {
  echo "-- 085-AC-2: a red baseline is not a score"
  out=$(run --module scripts/red.sh 2>&1); rc=$?
  same  "exit 2" "$rc" 2
  has   "the red test is named" "$out" "baseline red — scripts/red.sh: scripts/test-red.sh exit 1"
  hasnt "no score line" "$out" "mutation score"
  printf 'scripts/slow.sh scripts/test-hang.sh\n' > "$TMP/hang-targets"
  out=$(MUTATION_TARGETS="$TMP/hang-targets" MUTATION_WORKDIR="$WORK" MUTATION_BASELINE_LIMIT=2 bash "$RUNNER" --jobs 1 2>&1); rc=$?
  same "a timed-out baseline is exit 2 too" "$rc" 2
  has  "and says it timed out" "$out" "timed out after"
}

arm_leaves_nothing() {
  echo "-- 085-AC-4: nothing left behind, index and HEAD untouched"
  before=$(state)
  run --lines scripts/calc.sh:3 >/dev/null 2>&1
  same "after a finished run" "$(leftovers)|$(state)" "wt=1 runs=0|$before"
  run --module scripts/red.sh >/dev/null 2>&1
  same "after a red baseline" "$(leftovers)|$(state)" "wt=1 runs=0|$before"
  printf 'scripts/slow.sh scripts/test-hang.sh\n' > "$TMP/hang-targets"
  # Job control on: a non-interactive shell starts a background job with SIGINT ignored.
  set -m
  MUTATION_TARGETS="$TMP/hang-targets" MUTATION_WORKDIR="$WORK" bash "$RUNNER" --jobs 2 >/dev/null 2>&1 &
  pid=$!
  set +m
  i=0; while [ "$i" -lt 50 ] && [ "$(git worktree list | grep -c .)" -lt 3 ]; do sleep 0.2; i=$((i + 1)); done
  sleep 1
  kill -INT "$pid"; wait "$pid"; rc=$?
  same "an interrupted run exits 130" "$rc" 130
  same "after SIGINT" "$(leftovers)|$(state)" "wt=1 runs=0|$before"
  pgrep -f "$FIX" >/dev/null 2>&1 && bad "a test process outlived the interrupt" || ok "no test process outlived the interrupt"
}

arm_only_live_code() {
  echo "-- R1: comments, heredocs, quoted text and marked lines are not mutated"
  for l in 2 6 8 9; do
    out=$(run --lines scripts/calc.sh:$l 2>&1); rc=$?
    same "line $l has no mutable site (exit 2)" "$rc" 2
    has  "and says so" "$out" "no mutable site on line(s) $l"
  done
}

arm_arguments() {
  echo "-- arguments"
  for a in "--module scripts/nope.sh" "--jobs 0" "--sample x" "--seed -1" "--lines scripts/calc.sh" "--bogus"; do
    run $a >/dev/null 2>&1; same "$a is exit 2" "$?" 2
  done
  out=$(run --help); has "--help prints the header" "$out" "The template's own mutation gate"
  # Threat model: a table cannot point the runner outside the repository.
  printf 'exit 0\n' > "$TMP/escape.sh"     # it exists, so only the path rule can refuse it
  printf '../escape.sh scripts/test-slow.sh\n' > "$TMP/evil-targets"
  out=$(MUTATION_TARGETS="$TMP/evil-targets" MUTATION_WORKDIR="$WORK" bash "$RUNNER" 2>&1); rc=$?
  same "a module outside the repository is exit 2" "$rc" 2
  has  "and is named" "$out" "not a relative path to a file in the repository: ../escape.sh"
  printf 'scripts/slow.sh /bin/true\n' > "$TMP/evil-targets"
  out=$(MUTATION_TARGETS="$TMP/evil-targets" MUTATION_WORKDIR="$WORK" bash "$RUNNER" 2>&1); rc=$?
  same "an absolute test path is exit 2" "$rc" 2
}

arm_hostile_paths() {
  echo "-- threat model: symlinks, the work dir, empty tables"
  mkdir -p "$TMP/outside"; printf 'if [ "$1" -eq 0 ]; then :; fi\n' > "$TMP/outside/victim.sh"
  ln -s "$TMP/outside/victim.sh" scripts/link.sh
  printf 'scripts/link.sh scripts/test-slow.sh\n' > "$TMP/link-targets"
  out=$(MUTATION_TARGETS="$TMP/link-targets" MUTATION_WORKDIR="$WORK" bash "$RUNNER" 2>&1); rc=$?
  rm -f scripts/link.sh
  same "a symlinked module is exit 2" "$rc" 2
  has  "and named" "$out" "module is a symlink or under one: scripts/link.sh"
  same "the file behind it is untouched" "$(cat "$TMP/outside/victim.sh")" 'if [ "$1" -eq 0 ]; then :; fi'
  out=$(MUTATION_WORKDIR="$HOME" MUTATION_TARGETS="$FIX/targets" bash "$RUNNER" --module scripts/calc.sh 2>&1); rc=$?
  same "MUTATION_WORKDIR=\$HOME is exit 2" "$rc" 2
  out=$(MUTATION_WORKDIR=/ MUTATION_TARGETS="$FIX/targets" bash "$RUNNER" --module scripts/calc.sh 2>&1); rc=$?
  same "MUTATION_WORKDIR=/ is exit 2" "$rc" 2
  has  "and is refused as /, not by a failed mkdir" "$out" "may not be /, \$HOME or inside the repository: /"
  out=$(MUTATION_WORKDIR="$FIX/inside" MUTATION_TARGETS="$FIX/targets" bash "$RUNNER" --module scripts/calc.sh 2>&1); rc=$?
  same "a work dir inside the repository is exit 2" "$rc" 2
  rm -rf "$FIX/inside"
  out=$(MUTATION_WORKDIR=relative MUTATION_TARGETS="$FIX/targets" bash "$RUNNER" --module scripts/calc.sh 2>&1); rc=$?
  same "a relative work dir is exit 2" "$rc" 2
  printf '# nothing\n' > "$TMP/empty-targets"
  out=$(MUTATION_TARGETS="$TMP/empty-targets" MUTATION_WORKDIR="$WORK" bash "$RUNNER" 2>&1); rc=$?
  same "an empty table is exit 2" "$rc" 2
  printf 'scripts/calc.sh\n' > "$TMP/notest-targets"
  out=$(MUTATION_TARGETS="$TMP/notest-targets" MUTATION_WORKDIR="$WORK" bash "$RUNNER" 2>&1); rc=$?
  same "a module with no test is exit 2" "$rc" 2
  mkdir -p "$WORK/run.AAAAAA"; touch "$WORK/run.AAAAAA/keep"
  run --lines scripts/calc.sh:3 >/dev/null 2>&1
  [ -f "$WORK/run.AAAAAA/keep" ] && ok "a run.* dir without the marker is never deleted" || bad "a foreign run.* dir was deleted"
  rm -rf "$WORK/run.AAAAAA"
}

arm_infra_is_not_a_kill() {
  echo "-- review #3: a test that is gone is an infrastructure failure, not a kill"
  printf '[ "$(bash scripts/calc.sh 0 | head -1)" = zero ]; rc=$?; rm -f "$0"; exit $rc\n' > scripts/test-vanish.sh
  printf 'scripts/calc.sh scripts/test-vanish.sh\n' > "$TMP/vanish-targets"
  out=$(MUTATION_TARGETS="$TMP/vanish-targets" MUTATION_WORKDIR="$WORK" bash "$RUNNER" --jobs 1 --lines scripts/calc.sh:4 2>&1); rc=$?
  rm -f scripts/test-vanish.sh
  same  "exit 2" "$rc" 2
  hasnt "no score" "$out" "mutation score"
  has   "the missing verdict is said" "$out" "no verdict"
}

arm_maintenance_stamps() {
  echo "-- 085-AC-1: project-maintenance.sh --full measures through this runner and stamps the job"
  P="$TMP/maint"; mkdir -p "$P/scripts"
  for f in project-maintenance.sh maintenance_ledger.py maintenance-due.sh stryker_guard.py bash_write_targets.py; do
    cp "$REPO/scripts/$f" "$P/scripts/"
  done
  cp "$RUNNER" "$P/scripts/run-mutation-gate.sh"; chmod +x "$P/scripts/run-mutation-gate.sh"
  cp "$FIX/scripts/calc.sh" "$FIX/scripts/test-calc.sh" "$P/scripts/"
  printf 'scripts/calc.sh scripts/test-calc.sh\n' > "$P/targets"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm f )
  out=$(cd "$P" && MUTATION_TARGETS="$P/targets" MUTATION_WORKDIR="$WORK" MUTATION_BREAK=50 \
          bash scripts/project-maintenance.sh --full 2>&1)
  hasnt "the mutation job is not reported as unrun" "$out" "no mutation runner for this stack"
  same  "the ledger recorded a mutation run" "$(cut -f3 "$P/.claude/state/maintenance-runs.tsv" 2>/dev/null | grep -c '^mutation$')" 1
  due=$(cd "$P" && bash scripts/maintenance-due.sh --brief 2>&1)
  hasnt "maintenance-due no longer lists the mutation job" "$due" "mutation kill rate"
  echo "-- /tla GAP-1: a runner without the exec bit is a finding, and nothing runs in its place"
  chmod -x "$P/scripts/run-mutation-gate.sh"
  out=$(cd "$P" && MUTATION_TARGETS="$P/targets" MUTATION_WORKDIR="$WORK" bash scripts/project-maintenance.sh --full 2>&1)
  has   "it is named with the fix" "$out" "exists but is not executable"
  hasnt "and not called 'no runner'" "$out" "no mutation runner for this stack"
  same  "no second mutation run was recorded" "$(cut -f3 "$P/.claude/state/maintenance-runs.tsv" | grep -c '^mutation$')" 1
}

arm_seed_reproduces() {
  echo "-- O2: a seed reproduces its sample"
  a=$(run --module scripts/calc.sh --sample 1 --seed 7 2>/dev/null | grep -E 'survived|killed')
  b=$(run --module scripts/calc.sh --sample 1 --seed 7 2>/dev/null | grep -E 'survived|killed')
  same "two runs with one seed agree" "$a" "$b"
}

for a in arm_score_and_report arm_timeout_is_not_a_kill arm_red_baseline_is_unmeasured arm_leaves_nothing \
         arm_only_live_code arm_arguments arm_hostile_paths arm_infra_is_not_a_kill arm_maintenance_stamps arm_seed_reproduces; do
  want "$a" && "$a"
done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
