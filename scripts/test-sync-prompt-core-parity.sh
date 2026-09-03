#!/bin/bash
# test-sync-prompt-core-parity.sh — /project-update must mirror the SAME set of
# scripts the autosync calls CORE, and must not keep its own copy of the list.
#
# WHY. sync-prompt.md carried a hardcoded list of 27 script names. CORE_SCRIPTS
# in template-autosync.sh is 96. Measured 2026-09-03, 70 CORE scripts were never
# copied by /project-update at all: every PreToolUse guard, every test harness,
# the row archiver, the convergence check. It went unreported for months because
# an INCOMPLETE list looks exactly like a finished one — there is no error state
# for "you forgot to add it here too".
#
# So the second list is gone and this is what keeps it gone. A list is not a
# thing to keep in sync; it is a thing to have once.
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SP="$SCRIPT_DIR/sync-prompt.md"
TA="$SCRIPT_DIR/template-autosync.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

# 1. The query modes exist and answer without a clone, a network or a stamp.
N_S=$(bash "$TA" --list-core-scripts 2>/dev/null | wc -l | tr -d ' ')
N_R=$(bash "$TA" --list-core-rules   2>/dev/null | wc -l | tr -d ' ')
[ "${N_S:-0}" -gt 50 ] && ok "--list-core-scripts answers ($N_S scripts)" \
  || bad "--list-core-scripts returned $N_S — the query mode is the whole mechanism"
[ "${N_R:-0}" -gt 5 ] && ok "--list-core-rules answers ($N_R rules)" \
  || bad "--list-core-rules returned $N_R"

# 2. Every name it returns is a real file, so a typo in CORE_SCRIPTS is a red test
#    rather than a script that silently never ships.
GHOST=""
while IFS= read -r s; do
  [ -n "$s" ] || continue
  [ -f "$SCRIPT_DIR/$s" ] || GHOST="$GHOST $s"
done < <(bash "$TA" --list-core-scripts 2>/dev/null)
[ -z "$GHOST" ] && ok "every CORE_SCRIPTS entry exists on disk" \
  || bad "CORE_SCRIPTS names files that do not exist:$GHOST"

# 3. sync-prompt.md must ASK, not carry its own list.
grep -q -- '--list-core-scripts' "$SP" \
  && ok "sync-prompt.md derives the list from the template" \
  || bad "sync-prompt.md does not call --list-core-scripts — the second list is back"

# The specific shape of the old defect: a `for s in` loop over literal .sh names.
if grep -qE 'for s in .*[a-z-]+\.sh [a-z-]+\.sh' "$SP"; then
  bad "sync-prompt.md still iterates a hardcoded script list"
else
  ok "no hardcoded script list remains in sync-prompt.md"
fi

# 4. The copy must carry the mode. `cp` over an EXISTING file keeps the
#    DESTINATION's mode, so without this a script that was once non-executable
#    stays non-executable through every future sync — which is exactly what had
#    happened to template-autosync.sh in all six projects.
grep -q 'chmod +x "scripts/\$s"' "$SP" \
  && ok "the copy loop sets the executable bit from the source" \
  || bad "the copy loop does not carry the mode — cp keeps the destination's"

# 5. And the template's own modes have to be right, or there is nothing to carry.
NOEXEC=""
while IFS= read -r s; do
  case "$s" in *.sh) ;; *) continue ;; esac
  [ -f "$SCRIPT_DIR/$s" ] || continue
  [ -x "$SCRIPT_DIR/$s" ] || NOEXEC="$NOEXEC $s"
done < <(bash "$TA" --list-core-scripts 2>/dev/null)
[ -z "$NOEXEC" ] && ok "every CORE .sh in the template is executable" \
  || bad "CORE .sh without the executable bit:$NOEXEC"

# 6. Refuses rather than falling back. A silent fallback to a stale list is the
#    defect wearing a different hat.
grep -q 'Refusing to fall back to a hardcoded list' "$SP" \
  && ok "an unreadable template is a failure, not a quiet fallback" \
  || bad "sync-prompt.md has no explicit refusal when the list cannot be read"

echo "sync-prompt-core-parity: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
