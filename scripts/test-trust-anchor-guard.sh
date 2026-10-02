#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-trust-anchor-guard.sh — the agent's tools cannot write what stands for a developer's decision
# (spec 088 R3).
#
#   088-AC-3  a Write to .git/claude-trusted-commands, a Bash append to .git/claude-developer-words, a
#             Bash run of project-maintenance.sh --trust, and an Edit adding a **Confirmed:** line are
#             each denied, with a reason that names the store or line and does not echo the command
#
# Every arm runs the real hook with the payload Claude Code sends and reads the verdict the way the CLI
# does (hook-verdict.sh). Controls prove the guard is narrow: case edits, a fresh acceptance.md, the
# --confirm helper, ordinary commands and an honest AskUserQuestion all pass. The bash-write-guard route
# is checked end to end. A sabotage arm removes the Confirmed-line rule and requires the forged Edit to
# pass, so the arm that denies it is about that rule.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
GUARD="$SELF_DIR/trust-anchor-guard-hook.sh"
BASHGUARD="$SELF_DIR/bash-write-guard-hook.sh"
BASH_BIN=$(command -v bash)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t trustanchor)
WORK=$(cd -P "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"

P="$WORK/proj"
mkdir -p "$P/specs/001-x" "$P/docs"
git init -q "$P"
cat > "$P/specs/001-x/acceptance.md" <<'EOF'
# Acceptance cases — 001-x

**Confirmed:** 2026-10-01 · 0123456789ab — "Confirmed as written"

## AC-1 — one
**Given** a
**When** b
**Then** c
EOF

# run <guard> <payload> -> OUT, VERDICT
run() { OUT=$(printf '%s' "$2" | (cd "$P" && "$BASH_BIN" "$1") 2>/dev/null); VERDICT=$(hook_verdict "$OUT"); }
reason() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
expect() { [ "$VERDICT" = "$2" ] && ok "$1" || { bad "$1 (want $2, got $VERDICT)"; }; }
bash_p()  { jq -cn --arg c "$1" --arg w "$P" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}'; }
write_p() { jq -cn --arg p "$1" --arg c "$2" --arg w "$P" '{tool_name:"Write",tool_input:{file_path:$p,content:$c},cwd:$w}'; }
edit_p()  { jq -cn --arg p "$1" --arg o "$2" --arg n "$3" --arg w "$P" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n},cwd:$w}'; }
ACC="$P/specs/001-x/acceptance.md"

printf '\n[R3a] the stores, by any tool that names a path  (088-AC-3)\n'
run "$GUARD" "$(write_p "$P/.git/claude-trusted-commands" "deadbeef  suite")"
expect "088-AC-3 Write .git/claude-trusted-commands" deny
case "$(reason)" in *claude-trusted-commands*) ok "  the reason names the store" ;; *) bad "  the reason does not name the store" ;; esac
run "$GUARD" "$(write_p "$P/.git/claude-developer-words" "x")";            expect "Write .git/claude-developer-words" deny
run "$GUARD" "$(write_p "$P/.git/Claude-Trusted-Commands" "x")";           expect "the name in another case (case-insensitive file systems)" deny
run "$GUARD" "$(edit_p "$P/.git/claude-trusted-commands" "a" "b")";        expect "Edit of the store" deny
run "$GUARD" "$(write_p ".git/claude-developer-words" "x")";               expect "relative path to the store" deny
ln -s "$P/.git/claude-trusted-commands" "$P/docs/notes.txt"
run "$GUARD" "$(write_p "$P/docs/notes.txt" "x")";                         expect "a symlink with an innocent name that lands on the store" deny
run "$GUARD" "$(jq -cn --arg p "$P/.git/claude-trusted-commands" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p,new_source:"x"}}')"
expect "NotebookEdit naming the store" deny

printf '\n[R3c] shell text  (088-AC-3)\n'
SECRET="hunter2-SECRET-TOKEN"
run "$GUARD" "$(bash_p "echo $SECRET >> .git/claude-developer-words")"
expect "088-AC-3 Bash append to .git/claude-developer-words" deny
case "$(reason)" in *"$SECRET"*) bad "  the reason echoes the command" ;; *) ok "  the reason does not echo the command" ;; esac
run "$GUARD" "$(bash_p "bash scripts/project-maintenance.sh --trust --yes")"
expect "088-AC-3 Bash project-maintenance.sh --trust --yes" deny
run "$GUARD" "$(bash_p "bash scripts/project-maintenance.sh --trust")";      expect "--trust without --yes" deny
run "$GUARD" "$(bash_p "bash scripts/project-maintenance.sh --tr\"\"ust")";  expect "a quote-split --tr\"\"ust" deny
run "$GUARD" "$(bash_p "bash scripts/project-\\maintenance.sh --trust")";    expect "a backslash in the name" deny
run "$GUARD" "$(bash_p "MAINTENANCE_TTY=/tmp/yes bash scripts/project-maintenance.sh")"; expect "MAINTENANCE_TTY set" deny
run "$GUARD" "$(bash_p "cat .git/claude-trust*")";                          expect "a glob that expands to the store" deny
run "$GUARD" "$(bash_p "cat .git/claude-tr[u]sted-commands")";              expect "a bracket glob" deny
run "$GUARD" "$(bash_p "printf '%s\\n' '**Confirmed:** 2026-10-01 · 0123456789ab — \"ok\"' >> $ACC")"
expect "Bash writing a Confirmed line" deny
run "$GUARD" "$(bash_p "C='**Confirm''ed:**'; echo \$C")";                  expect "Confirmed split by quotes" deny

printf '\n[R3c] the spellings the adversarial review used\n'
run "$GUARD" "$(bash_p "env -u CLAUDECODE bash scripts/project-maintenanc?.sh --trust --yes")"; expect "#1 a globbed script name with --trust" deny
run "$GUARD" "$(bash_p "cp scripts/project-maintenance.sh /tmp/pm.sh && bash /tmp/pm.sh --trust --yes")"; expect "#1 a copied script with --trust" deny
run "$GUARD" "$(bash_p "unset CLAUDECODE; true")";                          expect "#1 clearing CLAUDECODE" deny
run "$GUARD" "$(bash_p "printf x >> .git/\$'\\x63laude-trusted-commands'")"; expect "#2 ANSI-C quoting of the store name" deny
run "$GUARD" "$(bash_p "bash scripts/project-maintenance.sh \$'--tr\\x75st'")"; expect "#2 ANSI-C quoting of --trust" deny
run "$GUARD" "$(bash_p "echo x >> .git/c*-trusted-commands")";             expect "#2 a glob on the store's first letters" deny
run "$GUARD" "$(bash_p "echo x >> .git/cl{a,a}ude-trusted-commands")";     expect "#2 a brace on the store name" deny
run "$GUARD" "$(bash_p "cat .git/c*")";                                     expect "#2 any glob through .git/" deny
run "$GUARD" "$(bash_p "mkdir -p .git/worktrees/x")";                       expect "a hand-made .git/worktrees entry" deny
run "$GUARD" "$(write_p "$P/src/app/.git" "")";                             expect "F090 planting a .git file with Write" deny
run "$GUARD" "$(write_p "$P/.git/config" "x")";                             expect "any Write inside .git/" deny
run "$GUARD" "$(jq -cn --arg p "$P/specs/0*/acc*.md" '{tool_input:{file_path:$p}}')"; expect "#3 a delegated glob that matches an acceptance.md" deny
run "$GUARD" "$(bash_p "git worktree add .claude/worktrees/w")";            expect "git worktree add itself is allowed" none
run "$GUARD" "$(bash_p "git init --separate-git-dir=/tmp/worktrees/x src/app")"; expect "/security-review: git init --separate-git-dir" deny
run "$GUARD" "$(bash_p "ln specs/001-x/acceptance.md notes.md")";          expect "/security-review: a hard link of an acceptance.md" deny
ln "$ACC" "$P/docs/alias.md"
run "$GUARD" "$(edit_p "$P/docs/alias.md" "0123456789ab" "ffffffffffff")"
OUT_SAVE=$VERDICT
OUT=$(jq -cn --arg p "$P/docs/alias.md" --arg w "$P" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"0123456789ab",new_string:"ffffffffffff"},cwd:$w}' | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$GUARD") 2>/dev/null)
VERDICT=$(hook_verdict "$OUT"); expect "/security-review: an Edit through a hard-linked alias is judged as the acceptance.md" deny
rm -f "$P/docs/alias.md"
run "$GUARD" "$(bash_p "cat .gitignore && ls .github/workflows/*.yml")";    expect ".gitignore and a .github glob are not .git/" none
run "$GUARD" "$(bash_p "bash scripts/test-developer-answers.sh")";          expect "running the hook's own test by name" none
BIG=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":"a"*300000}}))' "$P/docs/big.txt")
run "$GUARD" "$BIG";                                                        expect "#8 a 300 KB Write is parsed from stdin, not denied as unreadable" none

printf '\n[R3b] the Confirmed line in acceptance.md  (088-AC-3)\n'
run "$GUARD" "$(edit_p "$ACC" "**Then** c" "**Then** the **Confirmed** badge shows")"; expect "#9 a case about a **Confirmed** badge is not a Confirmed line" none
run "$GUARD" "$(edit_p "$ACC" "## AC-1 — one" "**Confirmed:** 2026-10-02 · ffffffffffff — \"yes\"

## AC-1 — one")"
expect "088-AC-3 Edit adding a second Confirmed line" deny
run "$GUARD" "$(edit_p "$ACC" "0123456789ab" "ffffffffffff")";               expect "Edit swapping the digest only" deny
run "$GUARD" "$(edit_p "$ACC" '**Confirmed:** 2026-10-01 · 0123456789ab — "Confirmed as written"' "")"; expect "Edit removing the Confirmed line" deny
run "$GUARD" "$(edit_p "$ACC" "# Acceptance cases — 001-x" "# Acceptance cases — 001-x

**Conf")"
OUT1=$VERDICT
run "$GUARD" "$(edit_p "$ACC" "**Given** a" "irmed:** 2026-10-02 · ffffffffffff — \"y\"
**Given** a")"
[ "$OUT1" = none ] && [ "$VERDICT" = none ] && ok "each half of a spliced line alone changes no Confirmed line" || bad "splice halves: $OUT1 / $VERDICT"
printf '# A\n\n**Conf\n**Given** a\n' > "$P/specs/001-x/splice.md"; mkdir -p "$P/specs/002-y"
printf '# A\n\n**Conf|X\n' > "$P/specs/002-y/acceptance.md"
run "$GUARD" "$(edit_p "$P/specs/002-y/acceptance.md" "|X" "irmed:** 2026-10-02 · ffffffffffff — \"y\"")"
expect "an Edit that completes a Confirmed line across old_string is seen (applied to the bytes)" deny
run "$GUARD" "$(jq -cn --arg p "$ACC" --arg w "$P" '{tool_name:"MultiEdit",tool_input:{file_path:$p,edits:[{old_string:"**Given** a",new_string:"**Given** A"},{old_string:"0123456789ab",new_string:"ffffffffffff"}]},cwd:$w}')"
expect "MultiEdit whose second edit swaps the digest" deny
run "$GUARD" "$(write_p "$ACC" "$(sed 's/0123456789ab/ffffffffffff/' "$ACC")")"; expect "Write with a changed Confirmed line" deny
run "$GUARD" "$(jq -cn --arg p "$ACC" '{tool_input:{file_path:$p}}')";      expect "a path with no bytes (bash-write-guard's delegation)" deny

printf '\n[R3d] an AskUserQuestion that answers itself\n'
run "$GUARD" '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"ok?","header":"h","multiSelect":false,"options":[{"label":"a","description":"d"},{"label":"b","description":"d"}]}],"answers":{"ok?":"a"}}}'
expect "pre-filled answers are denied" deny
run "$GUARD" '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"ok?","header":"h","multiSelect":false,"options":[{"label":"a","description":"d"},{"label":"b","description":"d"}]}]}}'
expect "an honest question passes" none
run "$GUARD" '{"tool_name":"AskUserQuestion","tool_input":{"questions":[],"answers":{}}}'
expect "an empty answers object passes" none

printf '\n[R3] controls: what the guard must not stop\n'
run "$GUARD" "$(edit_p "$ACC" "**Given** a" "**Given** a changed state")";  expect "Edit of a case body" none
run "$GUARD" "$(write_p "$P/specs/003-z/acceptance.md" "# A
## AC-1 — x
**Given** a
**When** b
**Then** c")";                                                                  expect "Write of a new acceptance.md with no Confirmed line" none
run "$GUARD" "$(write_p "$ACC" "$(sed 's/\*\*Given\*\* a/**Given** b/' "$ACC")")"; expect "Write keeping the Confirmed line byte for byte" none
run "$GUARD" "$(edit_p "$P/docs/acceptance.md" "a" "**Confirmed:** x")";    expect "an acceptance.md outside specs/ is not this guard's" none
run "$GUARD" "$(bash_p "bash scripts/acceptance-cases.sh --confirm specs/001-x --quote \"Confirmed as written\"")"; expect "the --confirm helper itself" none
run "$GUARD" "$(bash_p "bash scripts/project-maintenance.sh --full --suite")"; expect "project-maintenance without --trust" none
run "$GUARD" "$(bash_p "bash scripts/project-maintenance.sh --trusted-output")"; expect "a longer option that only starts with --trust" none
run "$GUARD" "$(bash_p "npm i -g @anthropic-ai/claude-code && git status")"; expect "an ordinary command naming claude-code" none
run "$GUARD" "$(bash_p "cat specs/001-x/acceptance.md")";                   expect "reading an acceptance.md through the shell" none
run "$GUARD" "$(write_p "$P/src/App.cs" "class A {}")";                      expect "an unrelated Write" none

printf '\n[R3] fails closed on what it cannot read\n'
run "$GUARD" '{"tool_name":"Bash","tool_input":{"command":"cat .git/claude-trusted-commands"'
expect "a truncated payload naming a store" deny
run "$GUARD" '{"tool_name":"Bash","tool_input":{"command":"ls"'
expect "a truncated payload naming nothing passes (precheck)" none

printf '\n[R3] harness fields are not the tool call, and a crash does not block the repair (2026-10-01 lockout)\n'
NOPY="$WORK/nopy"; mkdir -p "$NOPY"
for t in bash cat jq python3; do :; done
for d in $(printf '%s' "$PATH" | tr ':' ' '); do for f in "$d"/*; do n=${f##*/}; [ "$n" = python3 ] && continue; [ -x "$f" ] && [ ! -e "$NOPY/$n" ] && ln -s "$f" "$NOPY/$n" 2>/dev/null; done; done
META=$(jq -cn --arg w "$P" '{session_id:"s",transcript_path:"/Users/x/.claude/projects/-Users-x-repos-Claude/t.jsonl",scratchpad_dir:"/private/tmp/claude-501/x",cwd:$w,tool_name:"Bash",tool_input:{command:"ls -la"}}')
OUT=$(printf '%s' "$META" | (cd "$P" && PATH="$NOPY" "$BASH_BIN" "$GUARD") 2>/dev/null); VERDICT=$(hook_verdict "$OUT")
expect "scratchpad_dir=/…/claude-501/ in the harness fields does not wake the verdict (no python3 needed)" none
MUT2="$WORK/mut2"; mkdir -p "$MUT2"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MUT2"/ 2>/dev/null
python3 - "$MUT2/trust-anchor-guard-hook.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'sys.path.insert(0, sys.argv[1])'
assert old in s, "crash target not found"
open(p, "w").write(s.replace(old, 'raise RuntimeError("induced")', 1))
PY
run "$MUT2/trust-anchor-guard-hook.sh" "$(edit_p "$P/scripts/trust-anchor-guard-hook.sh" "a" "--trust")"; expect "a crashing guard still lets its own file be edited (the edit names a trigger word)" none
case "$OUT" in *"ALLOWED this edit unchecked"*) ok "  and says so" ;; *) bad "  the allow is silent" ;; esac
run "$MUT2/trust-anchor-guard-hook.sh" "$(bash_p "echo x >> .git/claude-trusted-commands")"; expect "a crashing guard still denies a store write" deny
run "$MUT2/trust-anchor-guard-hook.sh" "$(edit_p "$P/src/trust-anchor-guard-hook.sh" "a" "--trust")"; expect "the repair exemption is the root scripts/ copy only" deny

printf '\n[R3] the bash-write-guard route\n'
OUT=$(bash_p "sed -i.bak 's/0123456789ab/ffffffffffff/' specs/001-x/acceptance.md" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$BASHGUARD") 2>/dev/null)
VERDICT=$(hook_verdict "$OUT"); expect "sed -i on acceptance.md reaches the trust-anchor delegate" deny
case "$(reason)" in *trust-anchor-guard-hook.sh*) ok "  and names it" ;; *) bad "  the delegate is not named" ;; esac
OUT=$(bash_p "cat notes > specs/001-x/acceptance.md" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$BASHGUARD") 2>/dev/null)
VERDICT=$(hook_verdict "$OUT"); expect "a redirect into acceptance.md is denied" deny

printf '\n[090 R8b] a glob is judged by what bash expands it to  (090-AC-5, F112)\n'
FIX=$'cat > fix.json <<\'X\'\n{/* c */ "a": 1}\nX'
OUT=$(bash_p "$FIX" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$BASHGUARD") 2>/dev/null)
VERDICT=$(hook_verdict "$OUT"); expect "090-AC-5 a heredoc fixture holding {/* c */}: allowed (bash-write route)" none
FIXPY=$'python3 - <<\'X\'\nprint({/* 1 */})\nX'
OUT=$(bash_p "$FIXPY" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$BASHGUARD") 2>/dev/null)
VERDICT=$(hook_verdict "$OUT"); expect "an interpreter heredoc holding {/* */}: allowed" none
run "$GUARD" "$(jq -cn --arg p "$P/{/*" '{tool_input:{file_path:$p}}')";           expect "a delegated target {/* (no comma: literal braces)" none
run "$GUARD" "$(jq -cn --arg p "$P/docs/*" '{tool_input:{file_path:$p}}')";        expect "a delegated docs/* with no acceptance.md in docs/" none
OUT=$(bash_p "sed -i 's/x/y/' specs/*/acceptance.md" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$BASHGUARD") 2>/dev/null)
VERDICT=$(hook_verdict "$OUT"); expect "090-AC-5 sed -i on specs/*/acceptance.md is still denied" deny
for g in 'specs/*/acceptance.md' 'specs/001-x/*' 'specs/001-x/{acceptance,x}.md' 'specs/001-x/ACCEPT*.MD' \
         'specs/001-x/{a..a}cceptance.md' 'specs/001-x/a[[=c=]]ceptance.md' 'specs/00{1..3}-x/acceptance.md' \
         'SPECS/*/acceptance.md' 'specs/0*/a*'; do
  run "$GUARD" "$(jq -cn --arg p "$P/$g" '{tool_input:{file_path:$p}}')"
  expect "a delegated glob that reaches acceptance.md: $g" deny
done
ln -s ../specs/001-x/acceptance.md "$P/docs/cases.txt"
run "$GUARD" "$(jq -cn --arg p "$P/docs/c*.txt" '{tool_input:{file_path:$p}}')";   expect "a glob that expands to a symlink to acceptance.md" deny
rm -f "$P/docs/cases.txt"
run "$GUARD" "$(jq -cn --arg p "$P/specs/009-new/acceptance.md" '{tool_input:{file_path:$p}}')"; expect "a literal acceptance.md that does not exist yet is still one" deny
ALTS=$(python3 -c 'print(",".join("q%d" % i for i in range(300)))')
# Built in a variable first: bash 3.2 brace-expands a {…} inside "$( … "…" … )" (measured).
GP="$P/specs/001-x/{$ALTS,acceptance}.m?"; PL=$(jq -cn --arg p "$GP" '{tool_input:{file_path:$p}}'); run "$GUARD" "$PL"; expect "review #2: 300 brace alternatives before acceptance are not truncated away" deny
# Built in a variable first: bash 3.2 brace-expands a {…} inside "$( … "…" … )" (measured).
GP="$P/specs/{100..001}-x/acceptance.m?"; PL=$(jq -cn --arg p "$GP" '{tool_input:{file_path:$p}}'); run "$GUARD" "$PL"; expect "review #2: a descending sequence reaching 001 is denied" deny
T0=$(date +%s)
# Built in a variable first: bash 3.2 brace-expands a {…} inside "$( … "…" … )" (measured).
GP="$P/specs/x{1..99999999}/a*"; PL=$(jq -cn --arg p "$GP" '{tool_input:{file_path:$p}}'); run "$GUARD" "$PL"; expect "review #3: a huge sequence fails closed" deny
# Built in a variable first: bash 3.2 brace-expands a {…} inside "$( … "…" … )" (measured).
GP="$P/s{1..64}{1..64}{1..64}{1..64}/a*"; PL=$(jq -cn --arg p "$GP" '{tool_input:{file_path:$p}}'); run "$GUARD" "$PL"; expect "review #3: nested sequences fail closed" deny
[ $(( $(date +%s) - T0 )) -le 5 ] && ok "review #3: both answered within 5 s" || bad "review #3: the caps did not bound the time"
MUTG="$WORK/mutg"; mkdir -p "$MUTG"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MUTG"/ 2>/dev/null
python3 - "$MUTG/trust-anchor-guard-hook.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "            if any(same_as_acceptance(m) for m in hits):"
assert old in s, "sabotage target not found"
open(p, "w").write(s.replace(old, "            if True:"))
PY
run "$MUTG/trust-anchor-guard-hook.sh" "$(jq -cn --arg p "$P/{/*" '{tool_input:{file_path:$p}}')"
expect "sabotage: 'any glob could match' denies {/* again — the F112 arm is about the expansion" deny

printf '\n[R3] sabotage: without the Confirmed-line rule the forged Edit passes\n'
MUT="$WORK/mut"; mkdir -p "$MUT"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MUT"/ 2>/dev/null
python3 - "$MUT/trust-anchor-guard-hook.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'print("acceptance-confirmed" if conf_lines(after) != conf_lines(cur) else "none")'
assert old in s, "sabotage target not found"
open(p, "w").write(s.replace(old, 'print("none")'))
PY
run "$MUT/trust-anchor-guard-hook.sh" "$(edit_p "$ACC" "0123456789ab" "ffffffffffff")"
expect "sabotage: the digest swap is allowed by the mutant" none

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
