#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-guard-root-anchor.sh — a .git planted below the project does not move the root (spec 088 R1).
#
#   088-AC-1  spec-interview and pipeline-state deny src/app/main.py with an empty src/app/.git;
#             core-machinery denies a CORE script with scripts/.git; core-owed-tick denies a tick with
#             specs/.git; spec-register denies with no register and src/app/.git
#
# Every guard is run twice per plant: with CLAUDE_PROJECT_DIR set to the project (the harness always
# sets it) the verdict must equal the one without the plant; with it unset the old walk is kept, which
# is what a self-test or an older harness gets. A sabotage arm runs a copy of the scripts whose
# guard_git_boundary is the old `[ -e "$1/.git" ]` and requires it to ALLOW, so the arms above cannot
# pass for a reason other than the anchor.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
BASH_BIN=$(command -v bash)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t guardanchor)
WORK=$(cd -P "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"
unset ALLOW_CORE_MACHINERY_EDIT ALLOW_TICK_WITH_CORE_OWED

# verdict <scripts-dir> <guard> <payload> [anchor] -> deny | none | ...
verdict() {
  local dir="$1" guard="$2" payload="$3" anchor="${4:-}" out
  if [ -n "$anchor" ]; then
    out=$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$anchor" "$BASH_BIN" "$dir/$guard" 2>/dev/null)
  else
    out=$(printf '%s' "$payload" | "$BASH_BIN" "$dir/$guard" 2>/dev/null)
  fi
  hook_verdict "$out"
}
edit_payload() { jq -cn --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}'; }
tick_payload() { jq -cn --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"- [/] 001",new_string:"- [x] 001"}}'; }

# A code project: package.json, a register whose active full-track spec has spec.md only, a .claude/,
# and a stub sync that calls scripts/guarded.sh CORE and reports one owed file. The stub is the
# fixture's own; the real CORE lists are not under test here, the root is.
make_project() {
  local p="$WORK/$1" reg="${2:-yes}"
  mkdir -p "$p/src/app" "$p/scripts" "$p/specs/001-x" "$p/.claude/rules"
  git init -q "$p"
  echo '{}' > "$p/package.json"
  if [ "$reg" = yes ]; then
    printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$p/specs/INDEX.md"
    echo "# x" > "$p/specs/001-x/spec.md"
  fi
  cat > "$p/scripts/template-autosync.sh" <<'STUB'
#!/bin/bash
case "$1" in
  --is-core) [ "$2" = scripts/guarded.sh ] && { echo "scripts/guarded.sh is CORE"; exit 0; }; exit 1 ;;
  --owed) echo "scripts/guarded.sh"; exit 0 ;;
  --unlisted) exit 1 ;;
esac
exit 1
STUB
  echo '#!/bin/bash' > "$p/scripts/guarded.sh"
  printf '%s' "$p"
}

# expect <label> <want> <got>
expect() { [ "$3" = "$2" ] && ok "$1" || bad "$1 (want $2, got $3)"; }

P=$(make_project web)
N=$(make_project noreg no)

printf '\n[R1] baselines, nothing planted\n'
expect "spec-interview denies src/app/main.py" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$P")"
expect "pipeline-state denies src/app/main.py" deny "$(verdict "$SELF_DIR" pipeline-state-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$P")"
expect "spec-register denies with no register" deny "$(verdict "$SELF_DIR" spec-register-guard-hook.sh "$(edit_payload "$N/src/app/main.py")" "$N")"
expect "core-machinery denies scripts/guarded.sh" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$P/scripts/guarded.sh")" "$P")"
expect "core-owed-tick denies a tick" deny "$(verdict "$SELF_DIR" core-owed-tick-guard-hook.sh "$(tick_payload "$P/specs/INDEX.md")" "$P")"

printf '\n[R1] an empty .git file planted below the project  (088-AC-1)\n'
: > "$P/src/app/.git"; : > "$P/scripts/.git"; : > "$P/specs/.git"; : > "$N/src/app/.git"
expect "088-AC-1 spec-interview still denies src/app/main.py" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$P")"
expect "088-AC-1 pipeline-state still denies src/app/main.py" deny "$(verdict "$SELF_DIR" pipeline-state-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$P")"
expect "088-AC-1 spec-register still denies with no register" deny "$(verdict "$SELF_DIR" spec-register-guard-hook.sh "$(edit_payload "$N/src/app/main.py")" "$N")"
expect "088-AC-1 core-machinery still denies with scripts/.git" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$P/scripts/guarded.sh")" "$P")"
expect "088-AC-1 core-owed-tick still denies with specs/.git" deny "$(verdict "$SELF_DIR" core-owed-tick-guard-hook.sh "$(tick_payload "$P/specs/INDEX.md")" "$P")"

printf '\n[R1] a real nested repository (git init) is no boundary either  (O1)\n'
rm -f "$P/src/app/.git"; git init -q "$P/src/app"
expect "git init src/app: spec-interview denies" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$P")"
expect "git init src/app: pipeline-state denies" deny "$(verdict "$SELF_DIR" pipeline-state-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$P")"

printf '\n[R1] the anchor is resolved physically and must hold the file\n'
ln -s "$P" "$WORK/link"
expect "anchor given through a symlink: still denies" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$WORK/link")"
expect "relative anchor (from the project's parent): still denies" deny "$(cd "$WORK" && verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "web")"
O=$(make_project other)
expect "a file outside the anchor walks as before (stops at its nested .git)" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$O")"
expect "anchor that does not exist: old walk" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$WORK/missing")"
expect "anchor of / is ignored: old walk" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "/")"
W2=$(make_project web2); git init -q "$W2/src/app"
expect "a sibling sharing the anchor's prefix (web2 vs web) is outside it: old walk" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$W2/src/app/main.py")" "$P")"

printf '\n[R1] a linked worktree below the project is still a root (adversarial review #4)\n'
WT=$(make_project wt)
( cd "$WT" && git add -A && git -c user.name=t -c user.email=t@t commit -qm init && git worktree add -q .claude/worktrees/w ) >/dev/null 2>&1
expect "a file in .claude/worktrees/w is judged by the worktree's own register (denied, not exempt)" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$WT/.claude/worktrees/w/src/app/main.py")" "$WT")"
mkdir -p "$WT/src/fake"; printf 'gitdir: %s/.git/worktrees/w\n' "$WT" > "$WT/src/fake/.git"
expect "a .git file copying a real worktree's gitdir line, without the back-link, is no root" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$WT/src/fake/main.py")" "$WT")"
mkdir -p "$WORK/elsewhere/worktrees"
git init -q --separate-git-dir="$WORK/elsewhere/worktrees/x" "$WT/src/sep" 2>/dev/null
printf '%s/src/sep/.git\n' "$WT" > "$WORK/elsewhere/worktrees/x/gitdir"
expect "/security-review: a back-link outside the project's git dir makes no root" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$WT/src/sep/main.py")" "$WT")"
: > "$WT/src/app/.git"
expect "a plant beside the worktree is still ignored" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$WT/src/app/main.py")" "$WT")"

printf '\n[R1] case-insensitive file systems fold case (adversarial review #5)\n'
UP=$(printf '%s' "$P" | tr '[:lower:]' '[:upper:]')
if [ "$(uname -s)" = Darwin ] && [ -d "$UP" ]; then
  : > "$P/src/app/.git"
  expect "the file spelled in upper case is inside the anchor" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$UP/src/app/main.py")" "$P")"
  expect "the anchor spelled in upper case holds the file" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$UP")"
else
  echo "  skip  case folding: this file system is case-sensitive"
fi

printf '\n[R1] no CLAUDE_PROJECT_DIR: the old walk, unchanged\n'
expect "unset: the nested repo ends the walk (allowed, as before 088)" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/app/main.py")")"
expect "unset: core-machinery with scripts/.git allows, as before 088" none "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$P/scripts/guarded.sh")")"

printf '\n[R1] sabotage: guard_git_boundary without the anchor must let the plant through\n'
MUT="$WORK/mut"; mkdir -p "$MUT"
cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MUT"/ 2>/dev/null
python3 - "$MUT/guard-lib.sh" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s2 = s.replace('  if _guard_under "$1" "$GUARD_ANCHOR"; then\n    _guard_linked_worktree "$1" || return 1', '  if false; then')
assert s2 != s, "sabotage target not found"
open(p, "w").write(s2)
PY
for g in spec-interview pipeline-state; do
  expect "sabotage: $g allows src/app/main.py" none "$(verdict "$MUT" $g-guard-hook.sh "$(edit_payload "$P/src/app/main.py")" "$P")"
done
expect "sabotage: core-machinery allows with scripts/.git" none "$(verdict "$MUT" core-machinery-guard-hook.sh "$(edit_payload "$P/scripts/guarded.sh")" "$P")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
