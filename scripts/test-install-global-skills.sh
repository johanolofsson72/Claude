#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
#
# test-install-global-skills.sh — install-global-skills.sh against a throwaway HOME.
#
# WHY THIS EXISTS. The installer writes into the user's own ~/.claude, where a
# mistake is not a red test but a broken /project-wizard in every repo on the
# machine. So every behaviour it promises is pinned here, against a temp HOME,
# never against the real one: first install, a rerun that changes nothing, a
# refresh after drift, --check in both directions, and the promise that a file
# which exists only in the global copy survives a refresh.

set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SUT="$SELF_DIR/install-global-skills.sh"
TEMPLATE="$(cd "$SELF_DIR/.." && pwd)"
TMP="${TMPDIR:-/tmp}/install-global-skills-selftest.$$"
PASS=0; FAIL=0
mkdir -p "$TMP/home"

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n         expected: %s\n         actual:   %s\n' "$1" "$2" "$3"; }

# Runs the SUT with the temp HOME. CLAUDE_CONFIG_DIR is cleared so a developer
# who sets it cannot make this test write into their real config.
run() { OUT=$(env -u CLAUDE_CONFIG_DIR HOME="$TMP/home" bash "$SUT" "$@" 2>&1); RC=$?; }
has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
G="$TMP/home/.claude/skills"

printf 'install-global-skills.sh self-test\n'

# ------------------------------------------------------------ C1 — fresh install
printf '\n  -- C1  a clean HOME gets both skills, whole directories\n'
run --check
[ "$RC" -eq 1 ] && has "not installed" && ok "--check before install exits 1 and says why" \
  || bad "--check before install" "rc 1 + 'not installed'" "rc=$RC $OUT"
[ -d "$G" ] && bad "--check writes nothing" "no $G" "it exists" || ok "--check writes nothing"

run
[ "$RC" -eq 0 ] && ok "install exits 0" || bad "install exits 0" "0" "rc=$RC $OUT"
has "project-wizard: installed" && has "project-update: installed" && ok "…and reports both as installed" \
  || bad "…reports installed" "both 'installed'" "$OUT"
if diff -r "$TEMPLATE/.claude/skills/project-wizard" "$G/project-wizard" >/dev/null 2>&1 \
   && diff -r "$TEMPLATE/.claude/skills/project-update" "$G/project-update" >/dev/null 2>&1; then
  ok "…and the global copies are byte-identical, every file"
else
  bad "…byte-identical" "no diff" "$(diff -rq "$TEMPLATE/.claude/skills/project-wizard" "$G/project-wizard" 2>&1)"
fi
[ -f "$G/project-wizard/install.sh" ] && ok "…including files beside SKILL.md" \
  || bad "…files beside SKILL.md" "install.sh copied" "missing"
if ls "$G"/project-*/*.install-tmp.* >/dev/null 2>&1; then
  bad "no temp files left behind" "none" "$(ls "$G"/project-*/*.install-tmp.*)"
else
  ok "no temp files left behind"
fi

# ------------------------------------------------------------ C2 — idempotent
printf '\n  -- C2  a rerun changes nothing\n'
run
[ "$RC" -eq 0 ] && has "project-wizard: unchanged" && has "project-update: unchanged" \
  && ok "both unchanged" || bad "both unchanged" "rc 0 + 'unchanged' x2" "rc=$RC $OUT"
run --check
[ "$RC" -eq 0 ] && ok "--check exits 0 when in sync" || bad "--check in sync" "0" "rc=$RC $OUT"

# ------------------------------------------------------------ C3 — drift, then refresh
printf '\n  -- C3  a drifted copy is detected and refreshed\n'
printf 'stale local edit\n' >> "$G/project-update/SKILL.md"
mkdir -p "$G/project-wizard/templates"
printf 'mine\n' > "$G/project-wizard/templates/local.md"
run --check
[ "$RC" -eq 1 ] && has "project-update: differs" && has "SKILL.md" \
  && ok "--check exits 1 and names the drifted file" || bad "--check on drift" "rc 1, differs, SKILL.md" "rc=$RC $OUT"
has "project-wizard: unchanged" && ok "…and does not blame the skill that is in sync" \
  || bad "…in-sync skill" "project-wizard: unchanged" "$OUT"
cmp -s "$TEMPLATE/.claude/skills/project-update/SKILL.md" "$G/project-update/SKILL.md" \
  && bad "--check is read-only" "file still drifted" "it was refreshed" || ok "--check is read-only"

run
[ "$RC" -eq 0 ] && has "project-update: updated — 1 file(s)" && ok "refresh reports exactly one updated file" \
  || bad "refresh" "project-update: updated — 1 file(s)" "rc=$RC $OUT"
cmp -s "$TEMPLATE/.claude/skills/project-update/SKILL.md" "$G/project-update/SKILL.md" \
  && ok "…and the file matches the template again" || bad "…matches template" "identical" "differs"

# ------------------------------------------------------------ C4 — never deletes
printf '\n  -- C4  a file only the global copy has is kept and named\n'
[ -f "$G/project-wizard/templates/local.md" ] && ok "local-only file survives the refresh" \
  || bad "local-only file survives" "present" "deleted"
has "templates/local.md" && ok "…and the run names it" || bad "…named" "templates/local.md" "$OUT"
run --check
[ "$RC" -eq 0 ] && ok "a local-only file alone does not fail --check" || bad "--check with extras" "0" "rc=$RC $OUT"

# ------------------------------------------------------------ C5 — config dir + args
printf '\n  -- C5  CLAUDE_CONFIG_DIR wins over HOME; bad arguments are refused\n'
OUT=$(HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$SUT" 2>&1); RC=$?
[ "$RC" -eq 0 ] && [ -f "$TMP/cfg/skills/project-wizard/SKILL.md" ] && ok "installs under CLAUDE_CONFIG_DIR/skills" \
  || bad "CLAUDE_CONFIG_DIR" "$TMP/cfg/skills/project-wizard/SKILL.md" "rc=$RC $OUT"
run --bogus
[ "$RC" -eq 2 ] && ok "an unknown argument exits 2" || bad "unknown argument" "2" "rc=$RC"

printf '\n%s\n' "----------------------------------------------------------"
printf 'install-global-skills.sh self-test: %d passed, %d failed\n' "$PASS" "$FAIL"
rm -rf "$TMP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
