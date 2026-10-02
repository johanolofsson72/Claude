#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-guard-fail-closed.sh — the Edit-path guards under the conditions H1 broke them with (spec 083).
#
#   R2  fail-closed guards deny what they cannot read          083-AC-1
#   R3  fail-open guards say so instead of allowing in silence
#   R4  a crooked path reaches the same verdict as a clean one 083-AC-2
#   R5  only the ROOT scripts/ is exempt                        083-AC-3
#   R6  a tick is a row that becomes [x], however it is split   083-AC-4
#   R7  a byte-identical `cp` into a CORE path passes
#
# Every arm runs the real hook against a throwaway git repository with the payload Claude Code sends,
# and reads the verdict the way the CLI does: stdout JSON counts only on exit 0 (F029). Missing tools
# are simulated with a PATH of symlinks that leaves jq and/or python3 out.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
STATE="$SELF_DIR/pipeline-state-guard-hook.sh"
INTERVIEW="$SELF_DIR/spec-interview-guard-hook.sh"
REGGUARD="$SELF_DIR/spec-register-guard-hook.sh"
CORE="$SELF_DIR/core-machinery-guard-hook.sh"
TICK="$SELF_DIR/core-owed-tick-guard-hook.sh"
BASHGUARD="$SELF_DIR/bash-write-guard-hook.sh"
SYNC="$SELF_DIR/template-autosync.sh"
BASH_BIN=$(command -v bash)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t guardfc)
WORK=$(cd -P "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"     # no real ~/repos/Claude clone leaks into a verdict
unset CLAUDE_PROJECT_DIR CLAUDE_TEMPLATE_DIR ALLOW_CORE_MACHINERY_EDIT ALLOW_TICK_WITH_CORE_OWED

# A PATH holding every executable of the real one except the named tools.
path_without() {      # $1 = dir name, rest = tools to leave out
  local dir="$WORK/path-$1"; shift
  [ -d "$dir" ] && { printf '%s' "$dir"; return; }
  mkdir -p "$dir"
  local d f n h skip IFS=:
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      n=${f##*/}; [ -e "$dir/$n" ] && continue; [ -x "$f" ] || continue
      skip=0
      for h in "$@"; do case "$n" in "$h"|"$h".*) skip=1 ;; esac; done
      [ "$skip" -eq 1 ] || ln -s "$f" "$dir/$n" 2>/dev/null
    done
  done
  printf '%s' "$dir"
}
NOJQ=$(path_without nojq jq)
NOPY=$(path_without nopy python3)
NONE=$(path_without none jq python3)

# run <hook> <payload> [PATH] -> sets OUT and RC; VERDICT is what the CLI would act on.
run() {
  local hook="$1" payload="$2" p="${3:-$PATH}"
  OUT=$(printf '%s' "$payload" | PATH="$p" "$BASH_BIN" "$hook" 2>/dev/null); RC=$?
  if [ "$RC" -ne 0 ]; then VERDICT="exit-$RC"; else VERDICT=$(hook_verdict "$OUT"); fi
}
edit_payload() { printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":"a","new_string":"b"}}' "$(jq -Rn --arg p "$1" '$p')"; }
reason() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
context() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# A code project whose active spec has spec.md and nothing else.
make_code_project() {
  local p="$WORK/$1"
  mkdir -p "$p/src/scripts" "$p/scripts" "$p/specs/001-x"
  git init -q "$p"
  echo '{}' > "$p/package.json"
  printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$p/specs/INDEX.md"
  echo "# x" > "$p/specs/001-x/spec.md"
  printf '%s' "$p"
}

P=$(make_code_project web)

printf '\n[R2] fail-closed: a payload the guard cannot read is not a free pass  (083-AC-1)\n'
run "$STATE" "$(edit_payload "$P/src/App.cs")"
[ "$VERDICT" = deny ] && ok "baseline: pipeline-state denies src/App.cs with plan.md missing" || bad "baseline verdict $VERDICT"
run "$STATE" "$(edit_payload "$P/src/App.cs")" "$NOJQ"
[ "$VERDICT" = deny ] && ok "083-AC-1 no jq: python3 fallback still denies, exit 0" || { bad "083-AC-1 no jq: $VERDICT"; info "$OUT"; }
run "$STATE" "$(edit_payload "$P/src/App.cs")" "$NONE"
if [ "$VERDICT" = deny ]; then
  ok "083-AC-1 no jq, no python3: denies, exit 0"
  case "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])' 2>/dev/null)" in
    *jq*) ok "  the reason names the missing tool" ;; *) bad "  the reason does not name jq" ;; esac
else bad "083-AC-1 neither parser: $VERDICT"; info "$OUT"; fi
run "$STATE" "$(edit_payload "$P/src/App.cs")" "$NOPY"
[ "$VERDICT" = deny ] && ok "no python3 (resolver cannot start, rc 127): denies" || { bad "no python3: $VERDICT"; info "$OUT"; }
run "$STATE" '{"tool_name":"Edit","tool_input":{"file_path":"'"$P"'/src/App.cs",'
[ "$VERDICT" = deny ] && ok "a truncated payload naming a source file: denies" || { bad "truncated payload: $VERDICT"; info "$OUT"; }
run "$STATE" "$(edit_payload "$P/README.md")" "$NONE"
[ "$VERDICT" = none ] && ok "no parser, non-source file: allowed (the precheck already answers)" || bad "README with no parser: $VERDICT"
run "$INTERVIEW" "$(edit_payload "$P/src/App.cs")" "$NONE"
[ "$VERDICT" = deny ] && ok "spec-interview, neither parser: denies" || { bad "spec-interview neither parser: $VERDICT"; info "$OUT"; }

printf '\n[092 R3] every spec-interview deny route exits 0  (092-AC-2)\n'
# run() maps a non-zero exit to exit-N, so VERDICT=deny here means a deny on exit 0. One case per route;
# the reason text proves the route, since a deny from the wrong branch would pass the verdict alone.
unset SPEC_ACCEPTANCE SPEC_INTERVIEW_MODE SPEC_INTERVIEW_MIN
# 96: interview complete (15 auto answers), full track, no acceptance.md. tasks.md has no ticked task,
# so the "begun before 080" exemption cannot apply.
AC=$(make_code_project ac96)
for i in $(seq 1 15); do printf '## Q%d — t\n**Q:** q?\n**A (auto):** answer %d\n\n' "$i" "$i"; done > "$AC/specs/001-x/interview.md"
printf '# x\n\n## Clarifications\n\n- none\n' > "$AC/specs/001-x/spec.md"
echo 'rule X {}' > "$AC/specs/001-x/spec.allium"; echo '# plan' > "$AC/specs/001-x/plan.md"
printf '# tasks\n\n- [ ] T001 do it\n' > "$AC/specs/001-x/tasks.md"
run "$INTERVIEW" "$(edit_payload "$AC/src/App.cs")"
case "$VERDICT:$(reason)" in deny:*"acceptance cases for active spec 001"*"no acceptance.md"*) ok "092-AC-2 route 96 (acceptance cases owed): deny, exit 0" ;;
  *) bad "092-AC-2 route 96: $VERDICT"; info "$(reason | head -3)" ;; esac
# 97: the active row's id is outside the id grammar.
U=$(make_code_project id97)
printf '# Spec register\n\n## Specs\n\n- [/] X-1 — x — full track — goal\n' > "$U/specs/INDEX.md"
run "$INTERVIEW" "$(edit_payload "$U/src/App.cs")"
case "$VERDICT:$(reason)" in deny:*"id this parser does not recognise"*'"X-1"'*) ok "092-AC-2 route 97 (row id outside the grammar): deny, exit 0" ;;
  *) bad "092-AC-2 route 97: $VERDICT"; info "$(reason | head -3)" ;; esac
# 98: the guard runs from a scripts/ copy that has no spec_active.py.
R98="$WORK/noresolver"; mkdir -p "$R98"
cp "$INTERVIEW" "$SELF_DIR/guard-lib.sh" "$SELF_DIR/guard-precheck.sh" "$R98/"
run "$R98/spec-interview-guard-hook.sh" "$(edit_payload "$P/src/App.cs")"
case "$VERDICT:$(reason)" in deny:*"cannot determine which spec is active"*) ok "092-AC-2 route 98 (resolver not importable): deny, exit 0" ;;
  *) bad "092-AC-2 route 98: $VERDICT"; info "$(reason | head -3)" ;; esac
# The resolver cannot start: python3 is off PATH, jq is still on it.
run "$INTERVIEW" "$(edit_payload "$P/src/App.cs")" "$NOPY"
case "$VERDICT:$(reason)" in deny:*"python3 is not on PATH"*) ok "092-AC-2 resolver failed to start (no python3, jq present): deny, exit 0" ;;
  *) bad "092-AC-2 no python3: $VERDICT"; info "$(reason | head -3)" ;; esac
NOREG="$WORK/noreg"; mkdir -p "$NOREG/src"; git init -q "$NOREG"; echo '{}' > "$NOREG/package.json"
run "$REGGUARD" "$(edit_payload "$NOREG/src/App.cs")"
[ "$VERDICT" = deny ] && ok "baseline: spec-register denies with no register" || bad "spec-register baseline: $VERDICT"
run "$REGGUARD" "$(edit_payload "$NOREG/src/App.cs")" "$NONE"
[ "$VERDICT" = deny ] && ok "spec-register, neither parser: denies" || { bad "spec-register neither parser: $VERDICT"; info "$OUT"; }

# A big payload skips the 4096-byte precheck; with no parser it must still be judged on the raw text.
BIG=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":"x"*9000}}))' "$P/src/Big.cs")
run "$STATE" "$BIG" "$NONE"
[ "$VERDICT" = deny ] && ok "a 9 KB Write, no parser: denies" || bad "big payload no parser: $VERDICT"

printf '\n[R5] only the root scripts/ is exempt  (083-AC-3)\n'
run "$STATE" "$(edit_payload "$P/src/scripts/app.js")"
[ "$VERDICT" = deny ] && ok "083-AC-3 src/scripts/app.js is gated" || { bad "083-AC-3 src/scripts/app.js: $VERDICT"; }
run "$STATE" "$(edit_payload "$P/scripts/tool.sh")"
[ "$VERDICT" = none ] && ok "083-AC-3 <root>/scripts/tool.sh is exempt" || bad "083-AC-3 root scripts: $VERDICT"
for g in "$INTERVIEW" "$REGGUARD"; do
  run "$g" "$(edit_payload "$NOREG/src/scripts/app.js")"
  if [ "$g" = "$REGGUARD" ]; then
    [ "$VERDICT" = deny ] && ok "spec-register gates src/scripts/app.js too" || bad "spec-register nested scripts: $VERDICT"
  fi
done
run "$STATE" "$(edit_payload "$P/src/specs/thing.ts")"
[ "$VERDICT" = deny ] && ok "src/specs/thing.ts is gated" || bad "nested specs: $VERDICT"
run "$STATE" "$(edit_payload "$P/lib/.claude/x.js")"
[ "$VERDICT" = deny ] && ok "lib/.claude/x.js is gated" || bad "nested .claude: $VERDICT"
# Monorepo: the register lives in app/, the git root above it; app/scripts is the register root's.
M="$WORK/mono"; mkdir -p "$M/app/scripts" "$M/app/src" "$M/app/specs/001-x"; git init -q "$M"
echo '{}' > "$M/app/package.json"
printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$M/app/specs/INDEX.md"
run "$STATE" "$(edit_payload "$M/app/scripts/build.js")"
[ "$VERDICT" = none ] && ok "monorepo: <register-root>/scripts/build.js is exempt" || bad "monorepo register-root scripts: $VERDICT"
run "$STATE" "$(edit_payload "$M/app/src/a.js")"
[ "$VERDICT" = deny ] && ok "monorepo: app/src/a.js is gated" || bad "monorepo src: $VERDICT"

printf '\n[R4] a crooked path is judged like the clean one\n'
for c in "$P/src/x/../App.cs" "$P//src/App.cs" "$P/./src/App.cs"; do
  mkdir -p "$P/src/x"
  run "$STATE" "$(edit_payload "$c")"
  [ "$VERDICT" = deny ] && ok "pipeline-state: ${c#$WORK}" || bad "pipeline-state crooked ${c#$WORK}: $VERDICT"
done
run "$STATE" "$(edit_payload "$P/src/../scripts/../src/scripts/app.js")"
[ "$VERDICT" = deny ] && ok "pipeline-state: a path that walks through scripts/ but ends in src/scripts is gated" || bad "walk-through: $VERDICT"
run "$STATE" "{\"tool_name\":\"Edit\",\"cwd\":\"$P\",\"tool_input\":{\"file_path\":\"src/App.cs\"}}"
[ "$VERDICT" = deny ] && ok "pipeline-state: a relative path is resolved against .cwd" || bad "relative path: $VERDICT"

# core-machinery: a project with its own copy of the sync and an origin that is not the template.
CP="$WORK/coreproj"; mkdir -p "$CP/scripts" "$CP/.claude/rules" "$CP/x"
git init -q "$CP"; git -C "$CP" remote add origin https://github.com/someone/not-the-template.git
cp "$SYNC" "$CP/scripts/template-autosync.sh"; : > "$CP/scripts/spec_active.py"
ln -s "$CP/scripts" "$CP/linked-scripts"
run "$CORE" "$(edit_payload "$CP/scripts/spec_active.py")"
[ "$VERDICT" = deny ] && ok "baseline: core-machinery denies scripts/spec_active.py" || bad "core baseline: $VERDICT"
for c in "$CP/x/../scripts/spec_active.py" "$CP//scripts/spec_active.py" "$CP/linked-scripts/spec_active.py"; do
  run "$CORE" "$(edit_payload "$c")"
  [ "$VERDICT" = deny ] && ok "083-AC-2 core-machinery: ${c#$WORK}" || { bad "083-AC-2 core-machinery ${c#$WORK}: $VERDICT"; info "$OUT"; }
done
run "$CORE" "{\"tool_name\":\"Edit\",\"cwd\":\"$CP\",\"tool_input\":{\"file_path\":\"scripts/spec_active.py\"}}"
[ "$VERDICT" = deny ] && ok "083-AC-2 core-machinery: the relative scripts/spec_active.py" || bad "083-AC-2 relative: $VERDICT"

printf '\n[R3] fail-open guards announce instead of allowing in silence\n'
run "$CORE" "$(edit_payload "$CP/scripts/spec_active.py")" "$NONE"
if [ "$VERDICT" = none ] && [ "$RC" -eq 0 ]; then
  case "$(context)" in *core-machinery*"ALLOWED"*) ok "core-machinery, neither parser: allows and says so" ;;
    *) bad "core-machinery, neither parser: silent"; info "$OUT" ;; esac
else bad "core-machinery, neither parser: $VERDICT"; info "$OUT"; fi
run "$CORE" "$(edit_payload "$CP/scripts/spec_active.py")" "$NOJQ"
[ "$VERDICT" = deny ] && ok "core-machinery, python3 only: still denies (the deny no longer needs jq)" || { bad "core-machinery python3-only: $VERDICT"; info "$OUT"; }
run "$BASHGUARD" '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ src/App.cs"}}' "$NONE"
if [ "$RC" -eq 0 ]; then
  case "$(context)" in *bash-write-guard*"ALLOWED"*) ok "bash-write-guard, neither parser: allows and says so" ;;
    *) bad "bash-write-guard, neither parser: silent"; info "$OUT" ;; esac
else bad "bash-write-guard, neither parser: exit $RC"; fi

printf '\n[R6] a tick is a row that becomes [x]  (083-AC-4)\n'
# A project that owes CORE work: its sync answers --owed with one path. The guard only asks.
TP="$WORK/tickproj"; mkdir -p "$TP/scripts" "$TP/.claude" "$TP/specs"; git init -q "$TP"
git -C "$TP" remote add origin https://github.com/someone/not-the-template.git
cat > "$TP/scripts/template-autosync.sh" <<'SH'
#!/bin/bash
case "$1" in --owed) echo "scripts/spec_active.py"; exit 0 ;; *) exit 1 ;; esac
SH
REG="$TP/specs/INDEX.md"
printf '# Spec register\n\n## Specs\n\n- [x] 004 — done-thing — light track — an old goal\n- [ ] 005 — x — light track — goal\n' > "$REG"
tick_edit() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]}}))' "$REG" "$1" "$2"; }
run "$TICK" "$(tick_edit '- [ ] 005' '- [x] 005')"
[ "$VERDICT" = deny ] && ok "baseline: '- [ ] 005' -> '- [x] 005' is denied" || bad "tick baseline: $VERDICT"
run "$TICK" "$(tick_edit '[ ] 005' '[x] 005')"
[ "$VERDICT" = deny ] && ok "083-AC-4 '[ ] 005' -> '[x] 005' (the '- ' outside both strings) is denied" || { bad "083-AC-4 split tick: $VERDICT"; info "$OUT"; }
run "$TICK" "$(tick_edit ' ] 005' 'x] 005')"
[ "$VERDICT" = deny ] && ok "' ] 005' -> 'x] 005' is denied" || bad "split tick 2: $VERDICT"
run "$TICK" "$(tick_edit 'an old goal' 'a shorter goal')"
[ "$VERDICT" = none ] && ok "083-AC-4 rewording an already-ticked row is not a tick" || { bad "083-AC-4 reword ticked: $VERDICT"; info "$OUT"; }
run "$TICK" "$(tick_edit '- [ ] 005' '- [/] 005')"
[ "$VERDICT" = none ] && ok "marking a row [/] is not a tick" || bad "[/] mark: $VERDICT"
MULTI=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":sys.argv[1],"edits":[{"old_string":"goal\n","new_string":"goal!\n"},{"old_string":"[ ]","new_string":"[x]"}]}}))' "$REG")
run "$TICK" "$MULTI"
[ "$VERDICT" = deny ] && ok "a MultiEdit whose second edit ticks is denied" || bad "multiedit tick: $VERDICT"
WRITE=$(python3 -c 'import json,sys; t=open(sys.argv[1]).read().replace("- [ ] 005","- [X] 005"); print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":t}}))' "$REG")
run "$TICK" "$WRITE"
[ "$VERDICT" = deny ] && ok "a Write that rewrites the file with 005 ticked (capital X) is denied" || bad "write tick: $VERDICT"
run "$TICK" "$(tick_edit 'not in the file' '[x] 005')"
[ "$VERDICT" = deny ] && ok "an old_string that is not there: the written [x] counts (conservative)" || bad "unapplicable edit: $VERDICT"
run "$TICK" "$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1]}}))' "$REG")"
[ "$VERDICT" = deny ] && ok "a path with no bytes (the Bash route) answers about the file" || bad "bytes-free: $VERDICT"
run "$TICK" "$(tick_edit '[ ] 005' '[x] 005')" "$NOPY"
[ "$VERDICT" = deny ] && ok "no python3: the split tick still counts through the [x] fallback" || bad "no python3 split tick: $VERDICT"
run "$TICK" "$(tick_edit '- [ ] 005' '- [x] 005')" "$NONE"
case "$VERDICT:$(context)" in none:*core-owed-tick*ALLOWED*) ok "neither parser: allows and says so" ;;
  *) bad "tick guard, neither parser: $VERDICT"; info "$OUT" ;; esac
run "$TICK" "$(tick_edit '[ ] 005' '[x] 005' | sed "s#$TP/specs/INDEX.md#$TP/specs/../specs/INDEX.md#")"
[ "$VERDICT" = deny ] && ok "a crooked path to the register is still the register" || bad "crooked register path: $VERDICT"

printf '\n[R7] a byte-identical cp into a CORE path passes\n'
TPL="$WORK/tpl"; mkdir -p "$TPL/scripts" "$TPL/.claude/rules"; : > "$TPL/scripts/sync-prompt.md"
printf 'print("template")\n' > "$TPL/scripts/spec_active.py"
printf 'print("different")\n' > "$WORK/other.py"
cpcmd() { jq -nc --arg w "$CP" --arg c "$1" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}'; }
OUT=$(printf '%s' "$(cpcmd "cp $TPL/scripts/spec_active.py scripts/spec_active.py")" | CLAUDE_TEMPLATE_DIR="$TPL" "$BASH_BIN" "$BASHGUARD" 2>/dev/null); RC=$?
[ "$RC" -eq 0 ] && [ "$(hook_verdict "$OUT")" = none ] && ok "cp <template copy> scripts/spec_active.py: allowed" || { bad "byte-identical cp: rc=$RC $(hook_verdict "$OUT")"; info "$OUT"; }
OUT=$(printf '%s' "$(cpcmd "cp $WORK/other.py scripts/spec_active.py")" | CLAUDE_TEMPLATE_DIR="$TPL" "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "cp <different bytes> scripts/spec_active.py: denied" || bad "different cp: $(hook_verdict "$OUT")"
OUT=$(printf '%s' "$(cpcmd "cp -r $TPL/scripts scripts/spec_active.py")" | CLAUDE_TEMPLATE_DIR="$TPL" "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "cp -r: path-only, still denied" || bad "cp -r: $(hook_verdict "$OUT")"
OUT=$(printf '%s' "$(cpcmd "cp $TPL/scripts/spec_active.py $WORK/other.py scripts/")" | CLAUDE_TEMPLATE_DIR="$TPL" "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "two sources: path-only, still denied" || bad "two-source cp: $(hook_verdict "$OUT")"

printf '\n[review] the adversarial review'"'"'s bypasses stay closed\n'
# #1: the template's bytes cannot vouch for a second write to the same path in the same command.
OUT=$(printf '%s' "$(cpcmd "cp $TPL/scripts/spec_active.py scripts/spec_active.py && echo x >> scripts/spec_active.py")" | CLAUDE_TEMPLATE_DIR="$TPL" "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "#1 cp <template copy> && append: denied" || bad "#1 cp then append: $(hook_verdict "$OUT")"
OUT=$(printf '%s' "$(cpcmd "cp -s $TPL/scripts/spec_active.py scripts/spec_active.py")" | CLAUDE_TEMPLATE_DIR="$TPL" "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "#2 cp -s (a link, not bytes): denied" || bad "#2 cp -s: $(hook_verdict "$OUT")"
OUT=$(printf '%s' "$(cpcmd "/bin/cp $WORK/other.py scripts/spec_active.py")" | CLAUDE_TEMPLATE_DIR="$TPL" "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "#12 /bin/cp <different bytes>: denied" || bad "#12 /bin/cp: $(hook_verdict "$OUT")"
OUT=$(printf '%s' "$(cpcmd "cp -t scripts $WORK/x/spec_active.py")" | CLAUDE_TEMPLATE_DIR="$TPL" "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "#12 cp -t scripts <file named like CORE>: denied" || bad "#12 cp -t: $(hook_verdict "$OUT")"
# #3: a planted nested register, every row ticked, does not stand in for the real one.
mkdir -p "$P/src/specs" "$P/src/lib"
printf '# Spec register\n\n## Specs\n\n- [x] 001 — x — full track — goal\n' > "$P/src/specs/INDEX.md"
run "$STATE" "$(edit_payload "$P/src/lib/a.ts")"
[ "$VERDICT" = deny ] && ok "#3 a planted src/specs/INDEX.md: still denied" || bad "#3 nested register: $VERDICT"
run "$STATE" "$(edit_payload "$P/src/scripts/app.js")"
[ "$VERDICT" = deny ] && ok "#3 and src/scripts/ stays gated" || bad "#3 nested register exempts src/scripts: $VERDICT"
rm -rf "$P/src/specs"
# #10: a worktree's .git is a file, and it is still a root.
WT="$WORK/wt"; mkdir -p "$WT/src" "$WT/specs/001-x"; echo "gitdir: $P/.git/worktrees/wt" > "$WT/.git"
echo '{}' > "$WT/package.json"; cp "$P/specs/INDEX.md" "$WT/specs/"
run "$STATE" "$(edit_payload "$WT/src/App.cs")"
[ "$VERDICT" = deny ] && ok "#10 a worktree (.git file) is gated" || bad "#10 worktree: $VERDICT"
# #11: a link is a write to what it points at. Making one through the shell is judged as its target,
# and a path that does reach a guard's parser is followed through an existing link.
OUT=$(jq -nc --arg w "$P" '{tool_name:"Bash",cwd:$w,tool_input:{command:"ln -s ../src/App.cs docs/x.txt"}}' | "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "#11 ln -s ../src/App.cs docs/x.txt: denied as App.cs" || bad "#11 ln -s to source: $(hook_verdict "$OUT")"
OUT=$(printf '%s' "$(cpcmd "ln -sf ../scripts/spec_active.py x/notes.md")" | "$BASH_BIN" "$BASHGUARD" 2>/dev/null)
[ "$(hook_verdict "$OUT")" = deny ] && ok "#11 ln -sf ../scripts/spec_active.py x/notes.md: denied as CORE" || bad "#11 ln to CORE: $(hook_verdict "$OUT")"
mkdir -p "$P/docs"; ln -sf ../src/App.cs "$P/docs/y.cs"
run "$STATE" "$(edit_payload "$P/docs/y.cs")"
[ "$VERDICT" = deny ] && ok "#11 an existing link that reaches the parser is followed" || bad "#11 existing link: $VERDICT"
# /security-review: `..` after a symlinked directory is textual for the CLI, so it must be for the
# guards: <proj>/lnk/../src/App.cs is written as <proj>/src/App.cs, whatever lnk points at.
ln -s /var/empty "$P/lnk"
run "$STATE" "$(edit_payload "$P/lnk/../src/App.cs")"
[ "$VERDICT" = deny ] && ok "security-review: lnk/../src/App.cs (lnk -> /var/empty) is denied" || bad "lnk/.. bypass: $VERDICT"
ln -s /var/empty "$CP/lnk"
run "$CORE" "$(edit_payload "$CP/lnk/../scripts/spec_active.py")"
[ "$VERDICT" = deny ] && ok "security-review: lnk/../scripts/<core> is denied" || bad "lnk/.. CORE bypass: $VERDICT"
# #15: a source extension behind an exempt-looking name is source.
for n in README.sh LICENSE.js .env.ts; do
  run "$STATE" "$(edit_payload "$P/src/$n")"
  [ "$VERDICT" = deny ] && ok "#15 src/$n is gated" || bad "#15 $n: $VERDICT"
done
run "$STATE" "$(edit_payload "$P/src/a.mts")"
[ "$VERDICT" = deny ] && ok "#15 .mts is a source extension" || bad "#15 mts: $VERDICT"
# #9: a bold id and a non-breaking space are rows to the tick guard as they are to the resolver.
printf '# Spec register\n\n## Specs\n\n- [ ] **006** — b — light track — goal\n' > "$REG"
run "$TICK" "$(tick_edit '- [ ] **006**' '- [x] **006**')"
[ "$VERDICT" = deny ] && ok "#9 a bold id ticked: denied" || bad "#9 bold id: $VERDICT"

printf '\n[GAP-1] a sync that cannot answer is announced, not silent (/tla)\n'
GP="$WORK/gap1"; mkdir -p "$GP/scripts" "$GP/.claude" "$GP/specs"; git init -q "$GP"
git -C "$GP" remote add origin https://github.com/someone/not-the-template.git
printf '#!/bin/bash\nexit 2\n' > "$GP/scripts/template-autosync.sh"; : > "$GP/scripts/x.sh"
printf '# Spec register\n\n## Specs\n\n- [ ] 007 — x — light track — goal\n' > "$GP/specs/INDEX.md"
run "$CORE" "$(edit_payload "$GP/scripts/x.sh")"
case "$VERDICT:$(context)" in none:*core-machinery*"did not answer"*) ok "GAP-1 core-machinery: classifier exit 2 -> allow, announced" ;;
  *) bad "GAP-1 core-machinery: $VERDICT"; info "$OUT" ;; esac
run "$TICK" "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":"[ ] 007","new_string":"[x] 007"}}))' "$GP/specs/INDEX.md")"
case "$VERDICT:$(context)" in none:*core-owed-tick*"did not answer"*) ok "GAP-1 core-owed-tick: sync exit 2 -> allow, announced" ;;
  *) bad "GAP-1 core-owed-tick: $VERDICT"; info "$OUT" ;; esac
printf '#!/bin/bash\nexit 1\n' > "$GP/scripts/template-autosync.sh"
run "$CORE" "$(edit_payload "$GP/scripts/x.sh")"
[ -z "$OUT" ] && ok "GAP-1 control: exit 1 is an answer, and stays silent" || bad "GAP-1 control spoke: $OUT"

printf '\n[R11] a machine without a parser hears about it at session start\n'
ORIENT="$SELF_DIR/spec-register-orientation-hook.sh"
SCRATCH="$WORK/scratch"; mkdir -p "$SCRATCH"           # no register, no .git: the hook's silent case
for arm in "nojq:$NOJQ:python3 instead" "nopy:$NOPY:python3 is not on PATH" "none:$NONE:Neither jq nor python3"; do
  name=${arm%%:*}; rest=${arm#*:}; p=${rest%%:*}; want=${rest#*:}
  OUT=$(cd "$SCRATCH" && echo '{}' | PATH="$p" "$BASH_BIN" "$ORIENT" 2>/dev/null); RC=$?
  case "$OUT" in *"$want"*) [ "$RC" -eq 0 ] && ok "R11 $name: the SessionStart notice says '$want'" || bad "R11 $name: exit $RC" ;;
    *) bad "R11 $name: no notice"; info "$OUT" ;; esac
done
OUT=$(cd "$SCRATCH" && echo '{}' | "$BASH_BIN" "$ORIENT" 2>/dev/null)
[ -z "$OUT" ] && ok "R11 both present, nothing to orient: silent" || { bad "R11 both present: [$OUT]"; }
OUT=$(cd "$P" && echo '{}' | PATH="$NOJQ" "$BASH_BIN" "$ORIENT" 2>/dev/null)
case "$OUT" in *"python3 instead"*"Spec register"*|*"python3 instead"*"Register:"*) ok "R11 with a register: the notice leads the orientation, one JSON object" ;;
  *) bad "R11 with a register: notice missing or misplaced"; info "${OUT:0:300}" ;; esac
printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null && ok "  and it is valid JSON" || bad "  not valid JSON"

printf '\n[sabotage] the arms above bite\n'
SAB="$WORK/sab"; mkdir -p "$SAB"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$SAB"/ 2>/dev/null
sed -i.bak 's/^guard_walk_exempt "\$FILE"/case "$FILE" in *\/scripts\/*) true ;; *) false ;; esac/' "$SAB/pipeline-state-guard-hook.sh"
run "$SAB/pipeline-state-guard-hook.sh" "$(edit_payload "$P/src/scripts/app.js")"
[ "$VERDICT" != deny ] && ok "the old */scripts/* exemption lets src/scripts/app.js through — AC-3 would see it" || bad "sabotage R5 not observable"
sed -i.bak 's/^FILE=\$(guard_canon "\$FILE")/: canon removed/' "$SAB/core-machinery-guard-hook.sh"
run "$SAB/core-machinery-guard-hook.sh" "$(edit_payload "$CP/linked-scripts/spec_active.py")"
[ "$VERDICT" != deny ] && ok "without canon, a symlinked scripts dir is let through — AC-2 would see it" || bad "sabotage R4 not observable"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
