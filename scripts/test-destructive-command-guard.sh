#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-destructive-command-guard.sh — scripts/destructive-command-guard-hook.sh (spec 083, R9, F038).
#
# The deny list in .claude/settings.json matches by prefix, so `rm -r -f`, `/bin/rm -rf` and
# `git push -f` walked past it. This proves the guard reads the spelling the shell will run: a deny
# matrix (every spelling H1 named, plus the wrappers), an allow matrix (quoted data, near misses,
# the everyday commands this must never cost anything on), the fail-closed arm, and sabotage.
#
# Every arm runs the real hook with the payload Claude Code sends and reads the verdict the way the
# CLI does: stdout JSON only on exit 0.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
HOOK="$SELF_DIR/destructive-command-guard-hook.sh"
BASH_BIN=$(command -v bash)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

[ -f "$HOOK" ] || { echo "missing: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t destr); trap 'rm -rf "$WORK"' EXIT

verdict() {           # $1 = command, [$2 = hook]
  local out rc
  out=$(jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | "$BASH_BIN" "${2:-$HOOK}" 2>/dev/null); rc=$?
  LAST_OUT="$out"
  [ "$rc" -eq 0 ] || { echo "exit-$rc"; return; }
  hook_verdict "$out"
}

printf '\n[deny] every spelling of a listed command  (083-AC-5)\n'
while IFS= read -r c; do
  [ -z "$c" ] && continue
  v=$(verdict "$c")
  [ "$v" = deny ] && ok "deny: $c" || bad "$v: $c"
done <<'EOF'
rm -r -f build
/bin/rm -rf build
git push -f origin main
git clean -fd
rm -rf build
rm -fr build
rm -Rf build
\rm -rf build
command rm -rf build
rm --recursive --force build
rm build -rf
sudo ls
sudo -u root ls
FOO=1 rm -rf build
env -i PATH=/bin rm -rf build
nohup rm -rf build &
timeout 5 rm -rf build
nice -n 5 rm -rf build
find . -name '*.o' | xargs rm -rf
find . -print0 | xargs -0 -I{} rm -rf {}
ls && rm -rf build
ls; rm -rf build
(cd x && rm -rf y)
bash -c 'rm -rf build'
sh -c "git push --force"
zsh -c 'git reset --hard'
eval 'rm -rf build'
echo "$(rm -rf build)"
echo `rm -rf build`
git push --force
git push --force-with-lease
git push --force-with-lease=main:abc
git push --force-if-includes
git push -uf origin main
git push origin +main
git -C . push -f
git -c core.x=1 --no-pager push -f
git reset --hard
git reset --hard HEAD~3
git clean -f
git clean -xdf
git clean --force
find . -name '*.tmp' -delete
find . -type f -exec rm {} \;
find . -execdir /bin/rm -f {} +
EOF
# The adversarial review's spellings (spec 083): each one ran under the first version.
while IFS= read -r c; do
  [ -z "$c" ] && continue
  v=$(verdict "$c")
  [ "$v" = deny ] && ok "deny (review): $c" || bad "$v (review): $c"
done <<'EOF'
echo a#b; rm -rf /tmp/x
echo ${#PATH}; rm -rf x
for f in a; do rm -rf "$f"; done
if true; then rm -rf x; fi
while :; do git reset --hard; done
r""m -rf x
'r'm -rf x
r\m -rf x
g""it push -f
su""do ls
$'rm' -rf x
/bin/RM -rf x
echo 'rm -rf x' | bash
bash <<< 'rm -rf x'
doas -u root ls
su -c ls
setsid rm -rf x
busybox rm -rf x
rm --rec --fo x
git reset --har
find . -exec sh -c 'rm -rf {}' \;
EOF
v=$(verdict $'echo \'<<EOF\'\nrm -rf x'); [ "$v" = deny ] && ok "deny (review): a quoted '<<EOF' does not swallow the next line" || bad "$v: quoted <<EOF"
v=$(verdict $'cat <<EOF | bash\nrm -rf x\nEOF'); [ "$v" = deny ] && ok "deny (review): cat <<EOF | bash" || bad "$v: cat heredoc into bash"
v=$(verdict $'rm -r \\\n-f x'); [ "$v" = deny ] && ok "deny (review): a line continuation between the flags" || bad "$v: line continuation"
v=$(verdict 'git clean -nf'); [ "$v" = none ] && ok "allow (review): git clean -nf is a dry run" || bad "$v: git clean -nf"
# A multi-line command: a heredoc that FEEDS a shell is a program.
v=$(verdict $'bash <<\'X\'\nrm -rf build\nX'); [ "$v" = deny ] && ok "deny: bash <<X with rm -rf in the body" || bad "$v: bash heredoc body"
v=$(verdict $'ls\nrm -rf build'); [ "$v" = deny ] && ok "deny: a second line" || bad "$v: second line"
v=$(verdict $'true &&\trm -rf x'); [ "$v" = deny ] && ok "deny: after an escaped tab" || bad "$v: after a tab"

printf '\n[allow] data, near misses, everyday commands  (083-AC-5)\n'
while IFS= read -r c; do
  [ -z "$c" ] && continue
  v=$(verdict "$c")
  [ "$v" = none ] && ok "allow: $c" || { bad "$v: $c"; info "$LAST_OUT"; }
done <<'EOF'
git commit -m "drop rm -rf from docs"
rm -r build
rm -f build.log
rm build.log
echo rm -rf build
printf '%s\n' 'git push -f'
git push origin main
git push -u origin main
git reset --soft HEAD~1
git reset HEAD file
git clean -n
git status
git log --oneline -5
find . -name '*.tmp'
find . -type f -exec grep -l x {} \;
grep -rf patterns.txt .
command -v rm
rmdir build
npm run format
ls -la
cat README.md
git log --format='%h rm -rf' -- src
EOF
v=$(verdict $'cat <<\'X\'\nrm -rf /\nX'); [ "$v" = none ] && ok "allow: a heredoc fed to cat is data" || bad "$v: cat heredoc"

printf '\n[deny] a push that deletes or mirrors a remote ref  (090-AC-4, R5)\n'
while IFS= read -r c; do
  [ -z "$c" ] && continue
  v=$(verdict "$c")
  [ "$v" = deny ] && ok "090-AC-4 deny: $c" || { bad "$v: $c"; info "$LAST_OUT"; }
done <<'EOF'
git push --mirror origin
git push origin --delete main
git push -d origin main
git push origin :main
git push --prune origin
git push --m origin
git push --del origin x
git push -ud origin x
git push origin -- :x
git -C . push --mirror
git send-pack --mirror origin
git config remote.origin.mirror true
git config set remote.origin.push :main
git config remote.origin.push +HEAD:main
git -c remote.origin.mirror=true push
sh -c 'git push --delete origin x'
X=true git --config-env=remote.origin.mirror=X push
git remote add --mirror=push bak https://example.com/r.git
git config --type bool remote.origin.mirror true
git config --type string remote.origin.push :refs/heads/main
git config -f .git/config remote.origin.mirror true
git push origin $'\x3amain'
git push origin $'\x2bmain'
EOF
while IFS= read -r c; do
  [ -z "$c" ] && continue
  v=$(verdict "$c")
  [ "$v" = none ] && ok "090-AC-4 allow: $c" || { bad "$v: $c"; info "$LAST_OUT"; }
done <<'EOF'
git push origin :
git push origin main:main
git push --dry-run origin main
git push -o ci.skip origin main
git config --get remote.origin.mirror
git config --unset remote.origin.mirror
git config remote.origin.url git@example.com:a/b.git
git remote -v
EOF
verdict 'git push origin --delete secret-branch-abc123' >/dev/null
R=$(printf '%s' "$LAST_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
case "$R" in *secret-branch-abc123*) bad "090-AC-4 the reason echoes the command" ;; *) ok "090-AC-4 the reason does not echo the command" ;; esac
case "$R" in *"deletes a remote ref"*) ok "the reason names the delete form" ;; *) bad "the reason does not name the delete form" ;; esac

printf '\n[reason] names the form, never the command\n'
verdict 'rm -rf /tmp/secret-token-abc123' >/dev/null
R=$(printf '%s' "$LAST_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
case "$R" in *secret-token-abc123*) bad "the reason echoes the command" ;; *) ok "the reason does not echo the command" ;; esac
case "$R" in *"recursive, forced rm"*) ok "the reason names the form" ;; *) bad "the reason does not name the form" ;; esac
case "$R" in *"!"*) ok "the reason names the ! escape" ;; *) bad "no ! escape in the reason" ;; esac

printf '\n[fail-closed] cannot read, names a trigger word -> deny; names none -> allow\n'
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ "$(hook_verdict "$OUT")" = deny ] && [ "$RC" -eq 0 ] && ok "a truncated payload naming rm: deny, exit 0" || bad "truncated rm: $(hook_verdict "$OUT") rc=$RC"
# Exit 0 on every path (spec 090 mutation gate): exit 1 is a non-blocking error the CLI lets through.
OUT=$(printf '' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "an empty payload: silent, exit 0" || bad "empty payload: rc=$RC [$OUT]"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":""}}' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "an empty command: silent, exit 0" || bad "empty command: rc=$RC [$OUT]"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git status && git push origin --delete x"}}' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ "$(hook_verdict "$OUT")" = deny ] && [ "$RC" -eq 0 ] && ok "a deny exits 0 (the CLI reads JSON only then)" || bad "deny rc=$RC"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "an allow after the classifier ran: silent, exit 0" || bad "allow rc=$RC [$OUT]"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls src"}}' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "an allow at the precheck: silent, exit 0" || bad "precheck allow rc=$RC [$OUT]"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "a truncated payload naming nothing: allow, exit 0" || bad "truncated ls: rc=$RC $OUT"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"l'"''"'s src"' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "a truncated payload past the split precheck, naming no trigger: allow, exit 0" || bad "truncated split: rc=$RC $OUT"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"","description":"rm the build"}}' | "$BASH_BIN" "$HOOK" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && ok "an empty command past the precheck (rm in another field): allow, exit 0" || bad "empty command past precheck: rc=$RC $OUT"
mkdir -p "$WORK/nopy"; cp "$HOOK" "$SELF_DIR/guard-lib.sh" "$SELF_DIR/hook-notice.sh" "$WORK/nopy/"
printf 'import sys\nsys.exit(3)\n' > "$WORK/nopy/destructive_command.py"
v=$(verdict 'rm -rf x' "$WORK/nopy/destructive-command-guard-hook.sh")
[ "$v" = deny ] && ok "a classifier that does not answer: deny" || bad "broken classifier: $v"

printf '\n[cost] the everyday command starts no process\n'
T0=$(python3 -c 'import time; print(time.time())')
for _ in 1 2 3 4 5 6 7 8 9 10; do printf '{"tool_name":"Bash","tool_input":{"command":"ls -la src"}}' | "$BASH_BIN" "$HOOK" >/dev/null; done
T1=$(python3 -c 'import time; print(time.time())')
MS=$(python3 -c "print(int(($T1-$T0)*100))")
[ "$MS" -lt 40 ] && ok "ls -la src: ${MS} ms per call (precheck exit)" || bad "ls -la src: ${MS} ms per call"

printf '\n[sabotage] the matrix bites\n'
SAB="$WORK/sab"; mkdir -p "$SAB"; cp "$HOOK" "$SELF_DIR/guard-lib.sh" "$SELF_DIR/hook-notice.sh" "$SELF_DIR/shell_glob.py" "$SAB/"
sed 's/recursive |= "r" in c or "R" in c/recursive |= "r" in c/' "$SELF_DIR/destructive_command.py" > "$SAB/destructive_command.py"
v=$(verdict 'rm -Rf build' "$SAB/destructive-command-guard-hook.sh")
[ "$v" != deny ] && ok "a classifier blind to -R lets rm -Rf through — the matrix would see it" || bad "sabotage -R not observable"
sed 's/if a.startswith("+") and len(a) > 1:/if False:/' "$SELF_DIR/destructive_command.py" > "$SAB/destructive_command.py"
v=$(verdict 'git push origin +main' "$SAB/destructive-command-guard-hook.sh")
[ "$v" != deny ] && ok "a classifier blind to +refspec lets it through — the matrix would see it" || bad "sabotage +refspec not observable"
sed 's/body = " ".join(args) if w == "eval" else shell_body(args)/body = ""/' "$SELF_DIR/destructive_command.py" > "$SAB/destructive_command.py"
v=$(verdict "bash -c 'rm -rf x'" "$SAB/destructive-command-guard-hook.sh")
[ "$v" != deny ] && ok "a classifier that does not read -c lets it through — the matrix would see it" || bad "sabotage -c not observable"
sed 's/            if long_is(a, "--delete", 4) or long_is(a, "--prune", 4):/            if False:/' "$SELF_DIR/destructive_command.py" > "$SAB/destructive_command.py"
v=$(verdict 'git push origin --delete main' "$SAB/destructive-command-guard-hook.sh")
[ "$v" != deny ] && ok "a classifier blind to --delete lets it through — the 090 arm would see it" || bad "sabotage --delete not observable"
sed 's/        if a.startswith(":") and len(a) > 1:/        if False:/' "$SELF_DIR/destructive_command.py" > "$SAB/destructive_command.py"
v=$(verdict 'git push origin :main' "$SAB/destructive-command-guard-hook.sh")
[ "$v" != deny ] && ok "a classifier blind to :ref lets it through — the 090 arm would see it" || bad "sabotage :ref not observable"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
