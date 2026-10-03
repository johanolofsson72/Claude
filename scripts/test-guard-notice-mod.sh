#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Self-test for the guard-notice mod (spec 096): its logic, its staged layout and its installer.
#
#   096-R1  the staged source loads nothing: no .claude-plugin component, no hooks/hooks.json
#   096-R2..R4  mods/guard-notice/lib.test.ts under node (skipped, and said so, without node 22.6+)
#   096-R5  install, re-install, a foreign folder refused, uninstall own and foreign, a target with a
#           space, a missing staged file, claude plugin validate on the result (when claude is on PATH)
#
# Every install goes to a temporary CLAUDE_CONFIG_DIR. R6 (the agent may not run the installer) is
# tested in test-settings-edit-guard.sh, where the guard lives.

set -u
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/scripts/install-guard-notice-mod.sh"
SRC="$ROOT/mods/guard-notice"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
WORK=$(mktemp -d); trap 'rm -r -- "$WORK"' EXIT
export CLAUDE_CONFIG_DIR="$WORK/conf"

printf '[096-R1] the staged source loads nothing\n'
if [ -e "$SRC/.claude-plugin" ] || [ -e "$SRC/hooks/hooks.json" ]; then bad "a load marker in mods/guard-notice"; else ok "no .claude-plugin, no hooks/hooks.json"; fi
for f in plugin.json.staged hooks.json.staged register.tsx lib.ts types/index.d.ts lib.test.ts; do
  [ -f "$SRC/$f" ] && ok "staged: $f" || bad "missing: $f"
done

printf '\n[096-R2..R4] the mod'"'"'s logic\n'
if node -e 'process.exit(process.features?.typescript ? 0 : 1)' 2>/dev/null \
   || node --experimental-strip-types -e '' 2>/dev/null; then
  if OUT=$(node --experimental-strip-types --no-warnings --test "$SRC/lib.test.ts" 2>&1); then
    ok "lib.test.ts: $(printf '%s\n' "$OUT" | sed -n 's/^# pass /pass /p')"
  else
    bad "lib.test.ts"; printf '%s\n' "$OUT" | grep -E 'not ok|Error' | head -10
  fi
else
  ok "lib.test.ts SKIPPED: no node with type stripping (22.6+) on PATH"
fi

printf '\n[096-R5] the installer\n'
export GUARD_NOTICE_SKIP_VALIDATE=1
T="$CLAUDE_CONFIG_DIR/skills/guard-notice"
bash "$INSTALL" >/dev/null 2>&1 && ok "a fresh install exits 0" || bad "a fresh install failed"
for f in .claude-plugin/plugin.json hooks/hooks.json hooks/register.tsx hooks/lib.ts types/index.d.ts .guard-notice-installed; do
  [ -f "$T/$f" ] && ok "  installed: $f" || bad "  not installed: $f"
done
cmp -s "$SRC/plugin.json.staged" "$T/.claude-plugin/plugin.json" && ok "  the manifest is the staged one" || bad "  manifest differs"
printf '// edited\n' >> "$T/hooks/lib.ts"
bash "$INSTALL" >/dev/null 2>&1 && cmp -s "$SRC/lib.ts" "$T/hooks/lib.ts" && ok "a re-install updates its own folder" || bad "re-install"
F="$WORK/foreign"; mkdir -p "$F"; printf 'mine\n' > "$F/keep.txt"
bash "$INSTALL" --target "$F" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && [ -f "$F/keep.txt" ] && [ ! -e "$F/.claude-plugin" ] && ok "a foreign folder is refused (exit 1) and untouched" || bad "foreign folder: rc $rc"
bash "$INSTALL" --uninstall --target "$F" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && [ -f "$F/keep.txt" ] && ok "uninstall of a foreign folder is refused" || bad "foreign uninstall: rc $rc"
S="$WORK/with space/gn"
bash "$INSTALL" --target "$S" >/dev/null 2>&1 && [ -f "$S/hooks/hooks.json" ] && ok "a --target with a space" || bad "--target with a space"
bash "$INSTALL" --uninstall --target="$S" >/dev/null 2>&1 && [ ! -e "$S" ] && ok "uninstall of its own folder (--target=)" || bad "uninstall own"
bash "$INSTALL" --uninstall --target "$S" >/dev/null 2>&1 && ok "uninstall of nothing exits 0" || bad "uninstall of nothing"
bash "$INSTALL" --bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "an unknown argument exits 2" || bad "unknown argument"
bash "$INSTALL" --target >/dev/null 2>&1; [ $? -eq 2 ] && ok "--target without a folder exits 2" || bad "--target without a folder"
M="$WORK/repo"; mkdir -p "$M/scripts" "$M/mods"; cp "$INSTALL" "$M/scripts/"; cp -R "$SRC" "$M/mods/"
rm -- "$M/mods/guard-notice/lib.ts"
OUT=$(bash "$M/scripts/install-guard-notice-mod.sh" --target "$WORK/m" 2>&1); rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$WORK/m" ] && case "$OUT" in *lib.ts*) true ;; *) false ;; esac && ok "a missing staged file is named, nothing installed" || bad "missing staged file: rc $rc"

unset GUARD_NOTICE_SKIP_VALIDATE
if command -v claude >/dev/null 2>&1; then
  V="$WORK/validated"
  if OUT=$(bash "$INSTALL" --target "$V" 2>&1); then ok "claude plugin validate accepts the installed mod"
  else bad "claude plugin validate: $(printf '%s\n' "$OUT" | tail -5)"; fi
else
  ok "claude plugin validate SKIPPED: no claude on PATH"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
