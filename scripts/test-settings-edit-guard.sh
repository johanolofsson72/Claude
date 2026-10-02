#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-settings-edit-guard.sh — the agent's tools cannot change which hooks run (spec 089).
#
#   089-AC-1  an Edit that removes a hook, a Write that adds disableAllHooks, a MultiEdit that breaks
#             the JSON: each denied, naming the file and the developer's two routes
#   089-AC-2  settings.local.json created with env SPEC_ACCEPTANCE=off is denied; with only
#             permissions it is allowed in silence
#   089-AC-3  sed -i, rm, cd .claude && mv, printf > ~/.claude/settings.json are denied without echoing;
#             jq, git add, grep reads are allowed
#   089-AC-4  a re-indent and a permissions.allow entry are allowed
#   089-AC-5  bash-write-guard hands a tee write and a python3 -c naming the file to this guard
#
# Every arm runs the real hook with the payload Claude Code sends and reads the verdict the way the CLI
# does (hook-verdict.sh). Sabotage arms replace one rule of the verdict and require the attack it
# stops to pass, so the arm that denies it is about that rule.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
GUARD="$SELF_DIR/settings-edit-guard-hook.sh"
BASHGUARD="$SELF_DIR/bash-write-guard-hook.sh"
BASH_BIN=$(command -v bash)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t settingsguard)
WORK=$(cd -P "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR

P="$WORK/proj"
mkdir -p "$P/.claude" "$P/docs" "$P/scripts" "$P/sub"
git init -q "$P"
cat > "$P/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash"]
  },
  "env": {
    "SPEC_INTERVIEW_MODE": "auto"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/spec-interview-guard-hook.sh\"" },
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/trust-anchor-guard-hook.sh\"" }
        ]
      }
    ]
  }
}
EOF
printf '{ "hooks": {} }\n' > "$HOME/.claude/settings.json"
S="$P/.claude/settings.json"
L="$P/.claude/settings.local.json"
G="$HOME/.claude/settings.json"

# run <guard> <payload> -> OUT, VERDICT   (CLAUDE_PROJECT_DIR is the fixture project)
# A guard answers through JSON and always exits 0: a non-zero exit is a hook error the CLI reports instead
# of the decision (F099), so every run asserts it.
run() {
  OUT=$(printf '%s' "$2" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$1") 2>/dev/null); RC=$?
  VERDICT=$(hook_verdict "$OUT")
  [ "$RC" -eq 0 ] || { bad "exit $RC from $(basename "$1") (a guard always exits 0)"; VERDICT="exit$RC"; }
}
reason() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
expect() { [ "$VERDICT" = "$2" ] && ok "$1" || { bad "$1 (want $2, got $VERDICT)"; }; }
bash_p()  { jq -cn --arg c "$1" --arg w "${2:-$P}" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}'; }
write_p() { jq -cn --arg p "$1" --arg c "$2" --arg w "$P" '{tool_name:"Write",tool_input:{file_path:$p,content:$c},cwd:$w}'; }
edit_p()  { jq -cn --arg p "$1" --arg o "$2" --arg n "$3" --arg w "$P" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n},cwd:$w}'; }
multi_p() { jq -cn --arg p "$1" --argjson e "$2" --arg w "$P" '{tool_name:"MultiEdit",tool_input:{file_path:$p,edits:$e},cwd:$w}'; }
routes() { case "$(reason)" in *"by hand"*'`!`'*) ok "  the reason names both developer routes" ;; *) bad "  the reason lacks the developer routes" ;; esac; }

HOOK_LINE='          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/trust-anchor-guard-hook.sh\"" }'

printf '\n[R3] the Edit route, judged on the bytes  (089-AC-1)\n'
run "$GUARD" "$(edit_p "$S" ",
$HOOK_LINE" "")"
expect "089-AC-1 Edit removing a hook entry" deny
case "$(reason)" in *"$S"*) ok "  the reason names the file" ;; *) bad "  the reason does not name the file" ;; esac
case "$(reason)" in *hooks*) ok "  and the key" ;; *) bad "  the key is not named" ;; esac
routes
run "$GUARD" "$(write_p "$S" "$(jq '. + {disableAllHooks: true}' "$S")")"
expect "089-AC-1 Write adding disableAllHooks" deny
routes
run "$GUARD" "$(multi_p "$S" '[{"old_string":"\"allow\": [\"Bash\"]","new_string":"\"allow\": [\"Bash\", \"Read\"]"},{"old_string":"\n}\n","new_string":"\n"}]')"
expect "089-AC-1 MultiEdit leaving invalid JSON" deny
case "$(reason)" in *"JSON object"*) ok "  the reason says why" ;; *) bad "  the reason does not say the JSON breaks" ;; esac
routes
run "$GUARD" "$(edit_p "$S" '"SPEC_INTERVIEW_MODE": "auto"' '"SPEC_INTERVIEW_MODE": "auto", "SPEC_ACCEPTANCE": "off"')"
expect "Edit adding an env entry" deny
run "$GUARD" "$(edit_p "$S" 'trust-anchor-guard-hook.sh' 'true.sh')"
expect "Edit rewriting a hook command" deny
run "$GUARD" "$(write_p "$S" '{"permissions":{"allow":["Bash"]}}')"
expect "Write dropping hooks and env wholesale" deny
run "$GUARD" "$(jq -cn --arg p "$S" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"\"PreToolUse\"",new_string:"\"PreToolUseX\"",replace_all:true},cwd:"/"}')"
expect "replace_all renaming the event" deny
run "$GUARD" "$(edit_p "$G" '{ "hooks": {} }' '{ "hooks": {}, "disableAllHooks": true }')"
expect "~/.claude/settings.json disableAllHooks" deny
run "$GUARD" "$(jq -cn --arg p "$S" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p,new_source:"{}"}}')"
expect "NotebookEdit on settings.json" deny

printf '\n[R1] spellings of the same file\n'
run "$GUARD" "$(edit_p ".claude/settings.json" '"auto"' '"manual"')";          expect "relative path" deny
run "$GUARD" "$(edit_p "$P/docs/../.claude/settings.json" '"auto"' '"manual"')"; expect "a .. path" deny
case "$(uname -s)" in
  Darwin*|MINGW*|MSYS*|CYGWIN*)
    run "$GUARD" "$(edit_p "$P/.CLAUDE/Settings.JSON" '"auto"' '"manual"')";   expect "another case on a case-folding file system" deny ;;
esac
ln -s "$S" "$P/docs/notes.json"
run "$GUARD" "$(edit_p "$P/docs/notes.json" '"auto"' '"manual"')";             expect "a symlink with an innocent name" deny
ln "$S" "$P/docs/hard.json"
run "$GUARD" "$(edit_p "$P/docs/hard.json" '"auto"' '"manual"')";              expect "a hard link with an innocent name" deny
rm -f "$P/docs/hard.json"
CFG="$WORK/cfg"; mkdir -p "$CFG"; printf '{}\n' > "$CFG/settings.json"
OUT=$(edit_p "$CFG/settings.json" '{}' '{"disableAllHooks":true}' | (cd "$P" && CLAUDE_PROJECT_DIR="$P" CLAUDE_CONFIG_DIR="$CFG" "$BASH_BIN" "$GUARD") 2>/dev/null); VERDICT=$(hook_verdict "$OUT")
expect "CLAUDE_CONFIG_DIR moves the user settings" deny
run "$GUARD" "$(write_p "$P/.claude/s*.json" '{}')";                            expect "a glob path (a delegated shell write)" deny
run "$GUARD" "$(jq -cn --arg p "$S" '{tool_name:"Write",tool_input:{file_path:$p}}')"; expect "a path with no bytes" deny

printf '\n[R2] settings.local.json  (089-AC-2)\n'
run "$GUARD" "$(write_p "$L" '{"env":{"SPEC_ACCEPTANCE":"off"}}')"
expect "089-AC-2 creating settings.local.json with env" deny
run "$GUARD" "$(write_p "$L" '{"permissions":{"allow":["Bash(git status)"]}}')"
expect "089-AC-2 creating it with only permissions" none
[ -z "$OUT" ] && ok "  in silence" || bad "  the allow says something"
run "$GUARD" "$(write_p "$L" '{"env":{"ALLOW_CORE_MACHINERY_EDIT":"1"}}')";     expect "env ALLOW_CORE_MACHINERY_EDIT" deny

printf '\n[R2] what stays editable  (089-AC-4)\n'
run "$GUARD" "$(write_p "$S" "$(jq -c . "$S")")"
expect "089-AC-4 a re-indent (minified)" none
run "$GUARD" "$(edit_p "$S" '"allow": ["Bash"]' '"allow": ["Bash", "Read(./docs/**)"]')"
expect "089-AC-4 a permissions.allow entry" none
run "$GUARD" "$(write_p "$S" "$(jq '. + {outputStyle: "Proactive"}' "$S")")"; expect "outputStyle" none
run "$GUARD" "$(edit_p "$S" 'no such text' 'x')";                               expect "an Edit that would fail in the tool" none
run "$GUARD" "$(write_p "$WORK/other/.claude/settings.json" '{"disableAllHooks":true}')"; expect "another project's settings (O1)" none
run "$GUARD" "$(edit_p "$P/docs/guide.md" 'a' 'settings.json hooks')";         expect "a doc that mentions settings.json" none

printf '\n[R3] what cannot be judged is refused\n'
printf '{ "hooks": ' > "$L"
run "$GUARD" "$(edit_p "$L" '{' '{ ')";                                        expect "a current file that is not JSON" deny
rm -f "$L"
run "$GUARD" "$(write_p "$S" "$(jq '. + {x: 1}' "$S" | sed 's/"x": 1/"x": NaN/')")"; expect "NaN, which JSON.parse rejects" deny
run "$GUARD" "$(edit_p "$S" '"auto"' '"auto", "n": Infinity')";               expect "Infinity" deny
printf '{"env":{"X":1}}\n' > "$L"
run "$GUARD" "$(write_p "$L" '{"env":{"X":true}}')";                            expect "env 1 -> true is a change (True == 1 in Python)" deny
rm -f "$L"
run "$GUARD" "$(edit_p "$S" '"auto"' '“manual”')";                             expect "a smart-quote edit that does change env" deny
run "$GUARD" "$(edit_p "$S" '“auto”' '"manual"')";                             expect "a quote-normalised match is not simulated" deny

printf '\n[R4] the shell route  (089-AC-3)\n'
SECRET="hunter2-SECRET-TOKEN"
run "$GUARD" "$(bash_p "sed -i '' 's/auto/manual/' .claude/settings.json # $SECRET")"
expect "089-AC-3 sed -i" deny
case "$(reason)" in *"$SECRET"*) bad "  the reason echoes the command" ;; *) ok "  the reason does not echo the command" ;; esac
run "$GUARD" "$(bash_p "rm .claude/settings.local.json")";                        expect "089-AC-3 rm settings.local.json" deny
run "$GUARD" "$(bash_p "cd .claude && mv settings.json x")";                      expect "089-AC-3 cd .claude && mv settings.json" deny
run "$GUARD" "$(bash_p "printf '{}' > ~/.claude/settings.json")";                 expect "089-AC-3 printf > ~/.claude/settings.json" deny
for c in "jq .hooks .claude/settings.json" "git add .claude/settings.json" "grep -n env .claude/settings.local.json"; do
  run "$GUARD" "$(bash_p "$c")"; expect "089-AC-3 read: ${c%% *}" none
done
while IFS= read -r c; do
  [ -n "$c" ] || continue
  run "$GUARD" "$(bash_p "$c")"; expect "deny: $c" deny
done <<'EOF'
echo '{}' > .claude/settings.json
echo x >> .claude/settings.local.json
cat /tmp/x | tee .claude/settings.json
cp /tmp/evil.json .claude/settings.json
cp /tmp/evil.json .claude/
mv .claude .claude.off
rm -rf .claude
ln -sf /tmp/evil.json .claude/settings.json
touch .claude/settings.local.json
truncate -s 0 .claude/settings.json
git checkout -- .claude/settings.json
git restore .claude/settings.json
python3 -c "import json; json.dump({}, open('.claude/settings.json','w'))"
bash -c "rm .claude/settings.json"
sh -c 'cd .claude; rm settings.json'
eval "rm .claude/settings.json"
rm .c*/s*.json
rm .claude/settings.{json,local.json}
rm $'\x2eclaude/settings.json'
rm .cl""aude/sett\ings.json
rm "$HOME/.claude/settings.json"
rm ${HOME}/.claude/settings.json
rm "$CLAUDE_PROJECT_DIR/.claude/settings.json"
f=sett; rm .claude/${f}ings.json
cd .claude && rm -f *
cd .claude; cp /tmp/x .
pushd .claude && rm settings.local.json
cd sub && rm ../.claude/settings.json
git -C .claude checkout settings.json
find . -name settings.json -delete
ls | xargs rm settings.json
git diff --output=.claude/settings.json
git diff -o .claude/settings.json
cat > .claude/settings.json <<'JSON'
dd if=/dev/null of=.claude/settings.json
echo x >| .claude/settings.json
cat x 1<> .claude/settings.json
rm .claude/settings.json'unbalanced
cat /tmp/x > >(tee .claude/settings.json)
echo `rm .claude/settings.json`
echo $(rm .claude/settings.json)
LESSOPEN='|sed -i s/a/b/ %s' less .claude/settings.json
GIT_EXTERNAL_DIFF=./x.sh git diff .claude/settings.json
git -c core.pager='tee x' log .claude/settings.json
rg --pre ./x.sh hooks .claude/settings.json
p=.claude/settings.json; sed -i '' s/a/b/ "$p"
f=.claude/settings.local.json && echo '{"env":{"SPEC_ACCEPTANCE":"off"}}' > $f
export p=.claude/settings.json
p=$(echo .claude/settings.json); rm "$p"
echo .claude/settings.json | xargs rm
echo "rm .claude/settings.json" | sh
cat .claude/settings.json > >(sh)
rm $(printf .claude/settings.json)
EOF
run "$GUARD" "$(bash_p "rm settings.json" "$P/.claude")";                        expect "deny: rm settings.json with cwd inside .claude" deny
while IFS= read -r c; do
  [ -n "$c" ] || continue
  run "$GUARD" "$(bash_p "$c")"; expect "allow: $c" none
done <<'EOF'
cat .claude/settings.json
head -40 .claude/settings.json
python3 -m json.tool .claude/settings.json > /dev/null
python3 -m json.tool .claude/settings.json >/dev/null 2>&1 || echo invalid
jq -r '.hooks | keys' .claude/settings.json
git diff .claude/settings.json
git log --oneline -- .claude/settings.json
git show HEAD:.claude/settings.json
git commit -m "docs: say who edits .claude/settings.json"
git status --short
ls -la .claude
grep -rn "settings.json" scripts/
grep -q "trust-anchor-guard-hook.sh" .claude/settings.json && echo wired
cd sub && cp ../docs/a.md .
find . -name '*.py' | head
python3 scripts/sync-core-hooks.py "$TEMPLATE/.claude/settings.json"
bash scripts/test-settings-edit-guard.sh
rm -rf .claude/worktrees/old
mkdir -p .claude/agents
EOF

run "$GUARD" "$(bash_p "python3 - <<'PY'
open('.claude/settings.json', 'w').write('{}')
PY")";                                                                          expect "deny: a python3 heredoc whose body names settings.json" deny
run "$GUARD" "$(bash_p "cat > docs/settings-notes.md <<'MD'
The hooks live in .claude/settings.json and the developer edits them.
MD")";                                                                          expect "allow: a heredoc doc that mentions settings.json" none
run "$GUARD" "$(bash_p "git commit -F - <<'MSG'
feat: guard .claude/settings.json
MSG")";                                                                         expect "allow: a commit message heredoc naming settings.json" none
run "$GUARD" "$(bash_p "python3 <<\EOF
p = '.claude/settings.json'
EOF")";                                                                         expect "deny: <<\\EOF, a backslash-quoted delimiter" deny
run "$GUARD" "$(bash_p "python3 <<E\OF
p = '.claude/settings.json'
EOF")";                                                                         expect "deny: <<E\\OF, a partly quoted delimiter" deny
run "$GUARD" "$(bash_p "cat x
rm .claude/settings.json")";                                                    expect "deny: a write on the second line" deny

printf '\n[R5] the bash-write-guard route  (089-AC-5)\n'
OUT=$(bash_p "echo '{}' | tee .claude/settings.json" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$BASHGUARD") 2>/dev/null)
VERDICT=$(hook_verdict "$OUT"); expect "089-AC-5 tee into settings.json is denied by bash-write-guard" deny
case "$(reason)" in *settings-edit-guard-hook.sh*) ok "  and names the settings delegate" ;; *) bad "  the delegate is not named" ;; esac
OUT=$(bash_p "python3 -c \"open('.claude/settings.json','w').write('{}')\"" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$BASHGUARD") 2>/dev/null)
VERDICT=$(hook_verdict "$OUT"); expect "089-AC-5 python3 -c naming settings.json is denied by bash-write-guard" deny
case "$(reason)" in *settings-edit-guard-hook.sh*) ok "  and names the settings delegate" ;; *) bad "  the delegate is not named" ;; esac

printf '\n[R6] pre-check, fail closed, repair path\n'
NOPY="$WORK/nopy"; mkdir -p "$NOPY"
for d in $(printf '%s' "$PATH" | tr ':' ' '); do for f in "$d"/*; do n=${f##*/}; [ "$n" = python3 ] && continue; [ -x "$f" ] && [ ! -e "$NOPY/$n" ] && ln -s "$f" "$NOPY/$n" 2>/dev/null; done; done
OUT=$(bash_p "ls -la" | (cd "$P" && PATH="$NOPY" CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$GUARD") 2>/dev/null); VERDICT=$(hook_verdict "$OUT")
expect "a plain command never wakes the verdict (no python3 needed)" none
printf 'x\n' > "$P/scripts/x.sh"
OUT=$(edit_p "$P/scripts/x.sh" a b | (cd "$P" && PATH="$NOPY" CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$GUARD") 2>/dev/null); RC=$?; VERDICT=$(hook_verdict "$OUT")
[ "$RC" -eq 0 ] || bad "exit $RC on an unrelated Edit"
expect "an unrelated Edit of an existing file (not a hard link) never wakes the verdict" none
OUT=$(edit_p "$S" '"auto"' '"auto"' | (cd "$P" && PATH="$NOPY" CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$GUARD") 2>/dev/null); VERDICT=$(hook_verdict "$OUT")
expect "without python3 a settings edit is denied" deny
OUT=$(edit_p "$P/scripts/settings-edit-guard-hook.sh" a b | (cd "$P" && PATH="$NOPY" CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$GUARD") 2>/dev/null); RC=$?; VERDICT=$(hook_verdict "$OUT")
[ "$RC" -eq 0 ] || bad "exit $RC on the repair path"
expect "without python3 the guard's own file stays editable" none
case "$OUT" in *"ALLOWED this edit unchecked"*) ok "  and says so" ;; *) bad "  the allow is silent" ;; esac
run "$GUARD" '';                                                               expect "an empty payload" none
LONE="$WORK/lone"; mkdir -p "$LONE"; cp "$GUARD" "$SELF_DIR/settings_guard.py" "$LONE"/
run "$LONE/settings-edit-guard-hook.sh" "$(edit_p "$S" '"auto"' '"manual"')"; expect "without guard-lib.sh a settings edit is denied" deny
run "$GUARD" '{"tool_name":"Bash","tool_input":{"command":"rm .claude/settings.json"'
expect "a truncated payload naming a settings file" deny

printf '\n[090 R8c] a glob keeps to one path component, as the shell does\n'
PYHD=$'python3 - <<\'X\'\nprint(2 * 3)\nX'
run "$GUARD" "$(bash_p "$PYHD")";                                expect "an interpreter heredoc with a * in its program is allowed (found 2026-10-02)" none
run "$GUARD" "$(bash_p "$(printf 'cd %s && python3 - <<%sX%s\nf(*args)\nX' "$P" "'" "'")")"; expect "the same after a cd into the project" none
run "$GUARD" "$(bash_p "rm .claude/*.json")";                     expect "control: rm .claude/*.json still names the settings file" deny
run "$GUARD" "$(bash_p "rm -r .c*")";                             expect "control: rm -r .c* still names .claude" deny
run "$GUARD" "$(bash_p "rm -r *")";                               expect "control: rm -r * does not reach a dot directory (the shell's rule)" none
run "$GUARD" "$(bash_p "shopt -s dotglob; rm -r *")";           expect "review #8: with dotglob, rm -r * reaches .claude" deny
run "$GUARD" "$(bash_p "shopt -s dotglob; rm */settings.json")"; expect "review #8: with dotglob, */settings.json reaches .claude/settings.json" deny
run "$GUARD" "$(bash_p "shopt -s globstar; rm .claude/**/settings.json")"; expect "review #8: with globstar, **/ also matches no directory" deny
run "$GUARD" "$(bash_p "shopt -s dot''glob; cp e.json */settings.json")"; expect "/security-review: a quoted dot''glob still turns the loose match on" deny
run "$GUARD" "$(bash_p "shopt -s \$'\\x64otglob'; cp e.json */settings.json")"; expect "/security-review: an ANSI-C spelled dotglob too" deny
run "$GUARD" "$(bash_p "bash -O dotglob -c 'rm */settings.json'")"; expect "/security-review: bash -O dotglob" deny
run "$GUARD" "$(bash_p "echo x > .cla{u..u}de/settings.json")"; expect "/simplify: a brace sequence (.cla{u..u}de) is expanded like bash does" deny
run "$GUARD" "$(bash_p "echo x > .claude/s{e..e}ttings.json")"; expect "a brace sequence inside the name" deny
run "$GUARD" "$(bash_p "echo x > out{1..9999}.txt")";            expect "control: a huge sequence naming no settings file" none
MG="$WORK/mutglob"; mkdir -p "$MG"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MG"/ 2>/dev/null
python3 - "$MG/settings_guard.py" <<'PY' || bad "sabotage target not found (shell_glob_match)"
import sys
p = sys.argv[1]; s = open(p).read()
old = '    ps, qs = path.split("/"), pat.split("/")\n'
if old not in s: sys.exit(1)
open(p, "w").write(s.replace(old, '    return fnmatch.fnmatchcase(path, pat)\n' + old, 1))
PY
run "$MG/settings-edit-guard-hook.sh" "$(bash_p "$PYHD")"; expect "sabotage: fnmatch across / denies the interpreter heredoc again" deny

printf '\n[sabotage] each rule is what denies its attack\n'
sabotage() { # sabotage <label> <old> <new> <payload>
  local m="$WORK/mut$PASS$FAIL"; mkdir -p "$m"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$m"/ 2>/dev/null
  python3 - "$m/settings_guard.py" "$2" "$3" <<'PY' || { bad "$1: sabotage target not found"; return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
  run "$m/settings-edit-guard-hook.sh" "$4"; expect "$1" none
}
sabotage "sabotage: without the key comparison a hook removal passes" \
  'return ["settings-key", path, ",".join(keys)] if keys else ["none"]' 'return ["none"]' \
  "$(edit_p "$S" 'trust-anchor-guard-hook.sh' 'true.sh')"
sabotage "sabotage: without the read list sed -i passes" \
  'if not reads(words) or in_subst:' 'if False:' \
  "$(bash_p "sed -i '' s/a/b/ .claude/settings.json")"
sabotage "sabotage: without the redirect check printf > passes" \
  'hit = word_hit(t, g, bases, by_name, dots)' 'hit = None' \
  "$(bash_p "printf x > .claude/settings.json")"
sabotage "sabotage: without the cd bases ../.claude passes" \
  'bases.append(full)' 'pass' \
  "$(bash_p "cd sub && rm ../.claude/settings.json")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
