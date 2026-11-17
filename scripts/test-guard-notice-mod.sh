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
export GUARD_NOTICE_PIN_STORE="$WORK/pins"     # never this repository's own git dir
T="$CLAUDE_CONFIG_DIR/skills/guard-notice"

printf '\n[105-R8] the source is pinned by a digest the developer names\n'
D=$(bash "$INSTALL" --digest)
case "$D" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) [ "${#D}" -eq 16 ] && ok "105-R8 --digest prints a 16-hex digest" || bad "105-R8 digest [$D]" ;; *) bad "105-R8 digest [$D]" ;; esac
OUT=$(bash "$INSTALL" 2>&1); rc=$?
[ "$rc" -eq 4 ] && [ ! -e "$T" ] && ok "105-R8 an unaccepted source exits 4 and installs nothing" || bad "105-R8 unaccepted: rc $rc"
case "$OUT" in *"--accept $D"*) ok "  and names the command with its digest" ;; *) bad "  the refusal does not name --accept $D" ;; esac
bash "$INSTALL" --accept 0000000000000000 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ] && [ ! -e "$T" ] && ok "105-R8 a wrong --accept exits 4" || bad "105-R8 wrong accept: rc $rc"
bash "$INSTALL" --accept "$D" >/dev/null 2>&1 && ok "a fresh install with --accept exits 0" || bad "a fresh install failed"
grep -qx "guard-notice $D" "$GUARD_NOTICE_PIN_STORE" && ok "105-R8 the accepted digest is recorded in the store" || bad "105-R8 nothing recorded"
grep -qx "digest $D" "$T/.guard-notice-installed" && ok "  and in the marker, for the developer to read" || bad "  the marker lacks the digest"
M2="$WORK/repo2"; mkdir -p "$M2/scripts" "$M2/mods"; cp "$INSTALL" "$M2/scripts/"; cp -R "$SRC" "$M2/mods/"
printf '// changed by the agent\n' >> "$M2/mods/guard-notice/lib.ts"
D2=$(bash "$M2/scripts/install-guard-notice-mod.sh" --digest)
[ "$D2" != "$D" ] && ok "105-R8 a changed source digests differently" || bad "105-R8 the digest ignored a change"
printf 'installed by x\ndigest %s\n' "$D2" > "$T/.guard-notice-installed"     # threat #30: a marker the agent wrote
bash "$M2/scripts/install-guard-notice-mod.sh" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ] && ! grep -q 'changed by the agent' "$T/hooks/lib.ts" && ok "105-R8 a changed source is refused, a planted marker digest notwithstanding" || bad "105-R8 changed source installed: rc $rc"
SABI="$WORK/sabinst"; mkdir -p "$SABI/scripts" "$SABI/mods"; cp -R "$M2/mods/guard-notice" "$SABI/mods/"
sed 's/^if \[ "\$ACCEPT" != "\$DIGEST" \] && ! accepted; then$/if false; then/' "$INSTALL" > "$SABI/scripts/install-guard-notice-mod.sh"
if cmp -s "$INSTALL" "$SABI/scripts/install-guard-notice-mod.sh"; then bad "105-R8 sabotage target not found"; else
  GUARD_NOTICE_PIN_STORE="$WORK/sabpins" bash "$SABI/scripts/install-guard-notice-mod.sh" --target "$WORK/sabt" >/dev/null 2>&1 && ok "105-R8 sabotage: without the pin a changed source installs" || bad "105-R8 sabotage: the mutant refused"
fi
printf 'installed by scripts/install-guard-notice-mod.sh\n' > "$T/.guard-notice-installed"
bash "$INSTALL" >/dev/null 2>&1 && ok "105-R8 a recorded digest reinstalls with no --accept" || bad "105-R8 a recorded digest was refused"
[ "$(grep -c "^guard-notice $D\$" "$GUARD_NOTICE_PIN_STORE")" = 1 ] && ok "  and is recorded once, not again" || bad "  the store holds the digest $(grep -c "$D" "$GUARD_NOTICE_PIN_STORE") times"
bash "$INSTALL" --digest >/dev/null 2>&1 && ok "105-R8 --digest exits 0" || bad "105-R8 --digest failed"
bash "$INSTALL" --accept >/dev/null 2>&1; [ $? -eq 2 ] && ok "105-R8 --accept without a digest exits 2" || bad "105-R8 --accept alone"
OUT=$(bash "$INSTALL" --help 2>&1); rc=$?
[ "$rc" -eq 0 ] && case "$OUT" in *"--accept <digest>"*) true ;; *) false ;; esac && ok "--help exits 0 and documents --accept" || bad "--help: rc $rc"
OUT=$(bash "$M2/scripts/install-guard-notice-mod.sh" 2>&1); rc=$?
[ "$rc" -eq 4 ] && ok "105-R8 the changed source is still refused (exit 4)" || bad "105-R8 the changed source: rc $rc"
case "$OUT" in *"does not match"*) bad "105-R8 a refusal with no --accept claims a mismatch" ;; *) ok "105-R8 a refusal with no --accept names no mismatch" ;; esac
case "$OUT" in *"--target"*) bad "  and names no --target for the default target" ;; *) ok "  and names no --target for the default target" ;; esac
OUT=$(bash "$M2/scripts/install-guard-notice-mod.sh" --accept 0000000000000000 --target "$WORK/t2" 2>&1); rc=$?
[ "$rc" -eq 4 ] && [ ! -e "$WORK/t2" ] && ok "105-R8 a wrong --accept installs nothing (exit 4)" || bad "105-R8 wrong --accept: rc $rc"
case "$OUT" in *"does not match"*) ok "105-R8 a wrong --accept says it does not match" ;; *) bad "105-R8 a wrong --accept was not named" ;; esac
case "$OUT" in *"--target \"$WORK/t2\""*) ok "  and the command it prints keeps the --target" ;; *) bad "  the printed command lost the --target" ;; esac
M3="$WORK/repo3"; mkdir -p "$M3/scripts" "$M3/mods"; cp "$INSTALL" "$M3/scripts/"; cp -R "$SRC" "$M3/mods/"
ln -sf /etc/hosts "$M3/mods/guard-notice/lib.ts"
bash "$M3/scripts/install-guard-notice-mod.sh" --digest >/dev/null 2>&1; [ $? -eq 1 ] && ok "105-R8 a staged file that is a link is refused" || bad "105-R8 a linked staged file was hashed"
cp "$SRC/lib.ts" "$M3/mods/guard-notice/lib.ts.real"; rm "$M3/mods/guard-notice/lib.ts"; mv "$M3/mods/guard-notice/lib.ts.real" "$M3/mods/guard-notice/lib.ts"
chmod 000 "$M3/mods/guard-notice/lib.ts"
bash "$M3/scripts/install-guard-notice-mod.sh" --digest >/dev/null 2>&1; rc=$?; chmod 644 "$M3/mods/guard-notice/lib.ts"
[ "$rc" -eq 1 ] && ok "105-R8 an unreadable staged file stops it (exit 1)" || bad "105-R8 an unreadable staged file: rc $rc"
git init -q "$M3"; D3=$(bash "$M3/scripts/install-guard-notice-mod.sh" --digest)
env -u GUARD_NOTICE_PIN_STORE bash "$M3/scripts/install-guard-notice-mod.sh" --accept "$D3" --target "$WORK/t3" >/dev/null 2>&1
grep -qx "guard-notice $D3" "$M3/.git/claude-mod-accepted" 2>/dev/null && ok "105-R8 with no seam the accepted digest lands in the project's git dir" || bad "105-R8 nothing recorded in the git dir"
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
