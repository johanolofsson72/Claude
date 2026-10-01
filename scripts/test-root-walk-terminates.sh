#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-root-walk-terminates.sh — a relative CLAUDE_PROJECT_DIR no longer hangs a hook (spec 084,
# R1, F015).
#
# `dirname .` is `.`, so a walk from a relative directory toward `/` never got there. Measured at
# 82b28d2: seven of these twelve scripts were killed by `timeout 5` on CLAUDE_PROJECT_DIR=a/b, five
# of them from SessionStart or Stop.
#
#   W1  every walker returns within 5 s on a relative start with no repository above it. 084-AC-1.
#   W2  inside a project, the relative spelling and the absolute one give the same answer. 084-AC-1.
#   W3  `.`, `./x`, `..` and a name with a space terminate too.
#   W4  sabotage: a walker with the R1 lines removed still hangs, so W1 can fail.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

ROOT=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/scripts/drive-sync.sh"   # the sync and its hook are reached through the helper (specs 011, 084)
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }

TO=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null)
[ -n "$TO" ] || { echo "SKIP: neither timeout nor gtimeout is installed — this suite measures termination with one"; exit 0; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t rootwalk)
WORK=$(cd -P -- "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
# A temp directory can sit under a repository on some machines; then "no repository above" is false.
if git -C "$WORK" rev-parse --git-dir >/dev/null 2>&1; then echo "SKIP: $WORK is inside a git repository"; exit 0; fi

# The scripts that walk from ${CLAUDE_PROJECT_DIR:-$PWD} (or $PWD) with no `.` guard. The sync and
# its hook are driven through the helper; the rest are run directly.
WALKERS="lane-orientation-hook.sh template-sync-verify-hook.sh template-sync-verify.sh
stack-marker-canary-hook.sh harness-state-gc.sh spec-register-orientation-hook.sh
scenario-map-orientation-hook.sh sync-feature-json-hook.sh repeat-failure-guard-hook.sh
spec-run-log-hook.sh"

# run <script-path> <cwd> <project-dir> [args…] → stdout+stderr; rc in $RC. Bounded at 5 s.
run() {
  _s="$1"; _cwd="$2"; _p="$3"; shift 3
  case "${_s##*/}" in
    *-autosync.sh)
      OUT=$(cd "$_cwd" && DRIVE_SYNC_CWD="$_cwd" DRIVE_SYNC_TIMEOUT=5 DRIVE_SYNC_SCRIPT="$_s" drive_sync "$_p" "$WORK" "$@" 2>&1 </dev/null); RC=$? ;;
    *-autosync-hook.sh)
      OUT=$(cd "$_cwd" && DRIVE_SYNC_CWD="$_cwd" DRIVE_SYNC_TIMEOUT=5 DRIVE_HOOK_SCRIPT="$_s" drive_hook "$_p" "$WORK" "$@" 2>&1 </dev/null); RC=$? ;;
    *)
      OUT=$(cd "$_cwd" && CLAUDE_PROJECT_DIR="$_p" "$TO" 5 bash "$_s" "$@" 2>&1 </dev/null); RC=$? ;;
  esac
}
# Returned on its own: not killed at the bound, and not refused by the helper (64), which would mean
# the walker never ran and the "return" measured nothing.
returned() { [ "$RC" -ne 124 ] && [ "$RC" -ne 137 ] && [ "$RC" -ne 64 ]; }

printf '\n[W1] a relative start with no repository above it returns (084-AC-1)\n'
mkdir -p "$WORK/out/a/b"
for w in template-autosync.sh template-autosync-hook.sh $WALKERS; do
  run "$ROOT/scripts/$w" "$WORK/out" a/b
  returned && ok "$w returns (rc=$RC)" || bad "$w did not return on its own on CLAUDE_PROJECT_DIR=a/b (rc=$RC) $(printf '%s' "$OUT" | head -1)"
done
run "$ROOT/scripts/template-autosync.sh" "$WORK/out" a/b --check
case "$OUT" in *"not inside a git repository"*) ok "the sync says it is not inside a git repository" ;; *) bad "sync said: $(printf '%s' "$OUT" | head -2)" ;; esac

printf '\n[W2] inside a project, relative and absolute agree (084-AC-1)\n'
P="$WORK/proj"; mkdir -p "$P/.claude" "$P/a/b" "$P/scripts" "$P/specs"
git -C "$P" init -q . && git -C "$P" commit -q --allow-empty -m init
printf '# Spec register\n\n## Specs\n\n- [ ] 001 — x — light track — goal\n' > "$P/specs/INDEX.md"
# The sync's --unlisted answers from the root walk and the manifest alone (no template, no network).
run "$ROOT/scripts/template-autosync.sh" "$P" "$P/a/b" --unlisted; ABS_OUT=$OUT; ABS_RC=$RC
run "$ROOT/scripts/template-autosync.sh" "$P" a/b --unlisted;       REL_OUT=$OUT; REL_RC=$RC
[ "$ABS_RC" = "$REL_RC" ] && [ "$ABS_OUT" = "$REL_OUT" ] \
  && ok "template-autosync.sh --unlisted: same answer (rc=$REL_RC)" \
  || bad "template-autosync.sh --unlisted: absolute rc=$ABS_RC [$ABS_OUT] vs relative rc=$REL_RC [$REL_OUT]"
for w in spec-register-orientation-hook.sh template-sync-verify.sh lane-orientation-hook.sh; do
  run "$ROOT/scripts/$w" "$P" "$P/a/b"; A_OUT=$(printf '%s' "$OUT" | sed "s#$P#<P>#g"); A_RC=$RC
  run "$ROOT/scripts/$w" "$P" a/b;      R_OUT=$(printf '%s' "$OUT" | sed "s#$P#<P>#g"); R_RC=$RC
  [ "$A_RC" = "$R_RC" ] && [ "$A_OUT" = "$R_OUT" ] && ok "$w: same answer (rc=$R_RC)" || bad "$w: absolute rc=$A_RC vs relative rc=$R_RC"
done
# The register orientation hook names the register it found, so "same answer" is not two empties.
run "$ROOT/scripts/spec-register-orientation-hook.sh" "$P" a/b
case "$OUT" in *"INDEX.md"*|*"001"*) ok "…and the relative run found the project's register" ;; *) bad "relative run found no register: $(printf '%s' "$OUT" | head -2)" ;; esac

# `..` resolves to where it points, not to the child it was spelled from (adversarial review, 084).
mkdir -p "$WORK/dd/sub"; git -C "$WORK/dd/sub" init -q .; mkdir -p "$WORK/dd/sub/.claude"
run "$ROOT/scripts/template-autosync.sh" "$WORK/dd/sub" .. --unlisted
case "$OUT" in *"not inside a git repository"*) ok "CLAUDE_PROJECT_DIR=.. from inside a repo does not pick that repo" ;; *) bad "'..' picked a root: $(printf '%s' "$OUT" | head -1)" ;; esac

printf '\n[W3] other relative spellings terminate\n'
mkdir -p "$WORK/out/sp ace/x"
for d in . ./a "sp ace/x" ..; do
  for w in template-autosync.sh template-sync-verify-hook.sh harness-state-gc.sh; do
    run "$ROOT/scripts/$w" "$WORK/out" "$d"
    returned && ok "$w on '$d' returns" || bad "$w did not return on its own on '$d' (rc=$RC)"
  done
done

printf '\n[W4] sabotage: the old loop hangs, so W1 can fail\n'
SAB="$WORK/sab"; mkdir -p "$SAB/scripts"
cp "$ROOT/scripts/harness-state-gc.sh" "$SAB/scripts/"
grep -v 'spec 084 (F015)' "$ROOT/scripts/harness-state-gc.sh" \
  | sed 's/_walk_up=$(dirname "$DIR"); \[ "$_walk_up" = "$DIR" \] \&\& break; DIR=$_walk_up/DIR=$(dirname "$DIR")/' \
  > "$SAB/scripts/harness-state-gc.sh"
if grep -q '_walk_up' "$SAB/scripts/harness-state-gc.sh"; then
  bad "sabotage did not apply — the R1 lines were not found where this test expects them"
else
  run "$SAB/scripts/harness-state-gc.sh" "$WORK/out" a/b
  [ "$RC" -eq 124 ] && ok "harness-state-gc.sh without R1 is killed at the bound" || bad "the sabotaged walker returned rc=$RC — W1 could not have failed"
fi

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
