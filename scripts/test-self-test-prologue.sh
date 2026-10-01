#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-self-test-prologue.sh — every self-test starts by clearing what it must not inherit
# (spec 084, R4, F016 F020).
#
#   P1  every scripts/test-*.sh sources self-test-env.sh as its first statement (only `set` lines
#       may come before it), so no cd, pwd or $(dirname …) resolution runs on an inherited
#       CDPATH or CLAUDE_PROJECT_DIR. 084-AC-4.
#   P2  self-test-env.sh unsets every name spec 084 lists, and a sourcing shell really loses them.
#   P3  the checker catches a file without the line and a file with it after its first cd
#       (sabotage arms, on fixtures).
#   P4  decoys: CDPATH and CLAUDE_PROJECT_DIR aimed at a decoy clone, three real suites run from
#       this repository stay green and the decoy stays byte-identical. 084-AC-4.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

ROOT=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
ENVF="$ROOT/scripts/self-test-env.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }

[ -f "$ENVF" ] || { echo "missing: $ENVF"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t prologue)
WORK=$(cd -P -- "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT

# The one accepted spelling, and what may precede it.
PROLOGUE='. "$(dirname -- "$0")/self-test-env.sh" || exit 1'

# Prints nothing when <file> is compliant, else one reason.
check_file() {
  awk -v want="$PROLOGUE" '
    /^[[:space:]]*(#|$)/ { next }
    $0 == want { found = 1; exit }
    # Only a `set` that sets options. `set -u; cd …`, `set -- "$(cd …)"` and a continued line resolve
    # a path before the reset (adversarial review, 084).
    /^[[:space:]]*set([[:space:]]+([-+][A-Za-z]+|[a-z]+))+[[:space:]]*$/ { next }
    { first = $0; exit }
    END {
      if (found) exit 0
      if (first != "") print "first statement is not the prologue: " substr(first, 1, 70)
      else print "no prologue line"
    }' "$1"
}

printf '\n[P1] every scripts/test-*.sh opens with the prologue (084-AC-4)\n'
N=0; BADN=0
for f in "$ROOT"/scripts/test-*.sh; do
  N=$((N+1))
  why=$(check_file "$f")
  if [ -n "$why" ]; then BADN=$((BADN+1)); bad "${f#$ROOT/}: $why"; fi
done
[ "$N" -gt 0 ] || bad "no scripts/test-*.sh found — an empty population is not a clean one"
[ "$BADN" -eq 0 ] && [ "$N" -gt 0 ] && ok "all $N test files source self-test-env.sh first"

printf '\n[P2] self-test-env.sh clears every listed name\n'
NAMES="CDPATH BASH_ENV CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CEILING_DIRECTORIES GIT_CONFIG_PARAMETERS
GIT_CONFIG_COUNT CLAUDE_TEMPLATE_DIR CLAUDE_TEMPLATE_PIN CLAUDE_TEMPLATE_ALLOW_DIRTY
CLAUDE_TEMPLATE_SYNC_SANDBOX CLAUDE_TEMPLATE_AUTOSYNC CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS
TEMPLATE_AUTOSYNC_INTERVAL TEMPLATE_AUTOSYNC_LIMIT TEMPLATE_AUTOSYNC_NAME_LIMIT
TEMPLATE_AUTOSYNC_TIMEOUT_BACKOFF GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GIT_SSH_COMMAND
GIT_EXEC_PATH GIT_NAMESPACE DRIVE_SYNC_SCRIPT DRIVE_HOOK_SCRIPT DRIVE_SYNC_CWD DRIVE_SYNC_PATH DRIVE_SYNC_TIMEOUT"
SET_ALL=""; for n in $NAMES; do SET_ALL="$SET_ALL $n=decoy"; done
LEFT=$(env $SET_ALL bash -c '. "$1"; for n in $2; do [ "${!n+set}" = set ] && printf "%s " "$n"; done; :' _ "$ENVF" "$NAMES")
[ -z "$LEFT" ] && ok "a sourcing shell has none of the $(echo $NAMES | wc -w | tr -d ' ') names left" || bad "still set after sourcing: $LEFT"
KEEP=$(HOME=/h PATH="$PATH" bash -c '. "$1"; printf "%s|%s" "$HOME" "${PATH:+p}"' _ "$ENVF")
[ "$KEEP" = "/h|p" ] && ok "HOME and PATH are left alone (named residuals)" || bad "HOME/PATH changed: $KEEP"

printf '\n[P3] the checker bites (sabotage arms)\n'
printf '#!/bin/bash\n# header\nset -u\ncd "$(dirname "$0")/.." || exit 1\n' > "$WORK/test-missing.sh"
printf '#!/bin/bash\nset -u\nROOT=$(cd "$(dirname "$0")/.." && pwd)\n%s\n' "$PROLOGUE" > "$WORK/test-late.sh"
printf '#!/bin/bash\n# header\n\nset -euo pipefail\n%s\ncd "$(dirname "$0")/.."\n' "$PROLOGUE" > "$WORK/test-good.sh"
printf '#!/bin/bash\n. "$(dirname "$0")/self-test-env.sh"\n' > "$WORK/test-respelled.sh"
[ -n "$(check_file "$WORK/test-missing.sh")" ]   && ok "a file without the prologue is caught"            || bad "missing prologue passed"
[ -n "$(check_file "$WORK/test-late.sh")" ]      && ok "a prologue after the first cd is caught"           || bad "late prologue passed"
[ -z "$(check_file "$WORK/test-good.sh")" ]      && ok "a prologue after comments and set is accepted"     || bad "good file refused: $(check_file "$WORK/test-good.sh")"
[ -n "$(check_file "$WORK/test-respelled.sh")" ] && ok "a respelled source without || exit 1 is caught"   || bad "respelled prologue passed"
printf '#!/bin/bash\nset -u; cd "$(dirname "$0")/.."\n%s\n' "$PROLOGUE" > "$WORK/test-setcd.sh"
printf '#!/bin/bash\nset -- "$(cd "$(dirname "$0")" && pwd)"\n%s\n' "$PROLOGUE" > "$WORK/test-setargs.sh"
[ -n "$(check_file "$WORK/test-setcd.sh")" ]     && ok "set -u; cd … before the prologue is caught"         || bad "set -u; cd passed"
[ -n "$(check_file "$WORK/test-setargs.sh")" ]   && ok "set -- \"\$(cd …)\" before the prologue is caught" || bad "set -- cd passed"

printf '\n[P4] decoy CDPATH and CLAUDE_PROJECT_DIR leave a decoy clone untouched (084-AC-4)\n'
DECOY="$WORK/decoy"
mkdir -p "$DECOY/scripts" "$DECOY/specs" "$DECOY/.claude"
cp -R "$ROOT/scripts/." "$DECOY/scripts/" 2>/dev/null
git -C "$DECOY" init -q . 2>/dev/null
snap() { (cd "$DECOY" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done); }
BEFORE=$(snap)
# Three suites that resolve their root with a relative cd, a project from CLAUDE_PROJECT_DIR, and
# the sandbox gate. Started the way the suite runner starts them — from the repository root with a
# RELATIVE path — because that is when `cd "$(dirname "$0")/.."` is `cd scripts/..`, and a relative
# cd consults CDPATH first: the decoy's scripts/.. wins, which is F020 exactly.
for t in test-guard-lib.sh test-drive-sync.sh test-validate-sync-sandbox-declarations.sh; do
  OUT=$(cd "$ROOT" && CDPATH="$DECOY" CLAUDE_PROJECT_DIR="$DECOY" timeout 600 bash "scripts/$t" 2>&1); RC=$?
  [ "$RC" -eq 0 ] && ok "$t green under the decoys" || { bad "$t rc=$RC under the decoys"; printf '%s\n' "$OUT" | awk '/FAIL/ && n++ < 5 { print "        " $0 }'; }
done
AFTER=$(snap)
[ "$BEFORE" = "$AFTER" ] && ok "the decoy is byte-identical afterwards" || bad "the decoy changed"
# Control: the decoy is a real threat. Without the prologue, the same relative cd from the same cwd
# lands in the decoy, not here.
STEER=$(cd "$ROOT" && CDPATH="$DECOY" bash -c 'cd "$(dirname "$1")/.." >/dev/null 2>&1 && pwd -P' _ scripts/test-guard-lib.sh)
[ "$STEER" = "$DECOY" ] && ok "control: without the prologue CDPATH sends scripts/.. to the decoy" || bad "control: CDPATH did not redirect ($STEER)"

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
