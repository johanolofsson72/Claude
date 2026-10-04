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
# A hook always exits 0 (its header); any other exit is reported as the verdict `exit<N>`, so a test that
# reads only the JSON cannot miss it (spec 091 mutation gate: `exit 0` -> `exit 1` survived otherwise).
run() {
  OUT=$(printf '%s' "$2" | (cd "$P" && "$BASH_BIN" "$1") 2>/dev/null); local rc=$?
  VERDICT=$(hook_verdict "$OUT"); [ "$rc" -eq 0 ] || VERDICT="exit$rc"
}
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

printf '\n[091 R2] remotes, upstreams and remote-tracking refs are the developer'"'"'s  (091-AC-1)\n'
for c in "git remote set-url origin https://github.com/johanolofsson72/Claude.git" \
         "git -C . remote add template https://github.com/johanolofsson72/Claude.git" \
         "git remote rename origin old" "git remote remove origin" "git remote set-url --push origin x" \
         "git config remote.origin.url https://github.com/johanolofsson72/Claude.git" \
         "git config --local Remote.Origin.Url x" "git config set remote.origin.url x" \
         "git config --replace-all remote.origin.pushurl x" \
         "git config url.https://github.com/johanolofsson72/Claude.git.insteadOf https://github.com/me/p.git" \
         "git config branch.main.remote ." "git config --unset branch.main.merge" \
         "git config alias.r '!git remote set-url origin x'" "git config include.path /tmp/x" \
         "git config --rename-section remote.origin remote.gone" "git config -e" \
         "git update-ref refs/remotes/origin/main HEAD" "git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/x" \
         "git fetch . HEAD:refs/remotes/origin/main" "git fetch origin +refs/heads/*:refs/*" \
         "git push . HEAD:refs/remotes/origin/main" "git fetch --refmap=x origin" \
         "bash -c 'git remote set-url origin x'" "sh -c \"git update-ref refs/remotes/origin/main HEAD\"" \
         "true && command git remote add a b" "env GIT_DIR=.git git remote add a b" "/usr/bin/git remote add a b" \
         "sudo git remote set-url origin x" "git \$'\\x72emote' set-url origin x"; do
  run "$GUARD" "$(bash_p "$c")"
  expect "091-AC-1 denies: $c" deny
done
case "$(reason)" in *"spec 091"*) ok "the reason names spec 091" ;; *) bad "reason: $(reason | head -c 120)" ;; esac
for c in "git remote -v" "git remote get-url origin" "git remote" "git remote show origin" \
         "git config --get remote.origin.url" "git config remote.origin.url" "git config --list" \
         "git config user.name t" "git config core.autocrlf false" "git fetch origin" "git fetch" \
         "git push origin main" "git push -u origin main" "git pull --rebase" "git symbolic-ref HEAD" \
         "git log --oneline refs/remotes/origin/main" "cat tsconfig.json" "echo remote config" \
         "printf 'git remote set-url origin x' > notes.txt"; do
  run "$GUARD" "$(bash_p "$c")"
  expect "control allows: $c" none
done

printf '\n[091] the hook exits 0 on every path\n'
OUT=$(printf '' | "$BASH_BIN" "$GUARD" 2>/dev/null); expect_rc=$?
[ "$expect_rc" -eq 0 ] && [ -z "$OUT" ] && ok "empty input: exit 0, no output" || bad "empty input: rc $expect_rc, '$OUT'"
run "$GUARD" "$(bash_p "$(printf 'echo %04096d git remote' 0)")"
expect "a payload over 4 KB still reaches the parser and is allowed when harmless" none

printf '\n[091 adversarial review] the bypasses it traced are denied\n'
for c in "git -c remote.origin.url=/tmp/forge fetch origin" \
         "git -c url./tmp/f/.insteadOf=https://github.com/ fetch origin" \
         "git --config-env=remote.origin.url=X fetch origin" \
         "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0=/tmp/f git fetch origin" \
         "env GIT_CONFIG_PARAMETERS=x git fetch origin" "export GIT_CONFIG_COUNT=1; git fetch origin" \
         "git fetch . 'refs/heads/*:refs/rem*'" "git fetch . 'refs/heads/*:refs/*/origin/main'" \
         "git fast-import < stream" "git fetch-pack x" "git send-pack . HEAD:refs/remotes/origin/main" \
         "/usr/libexec/git-core/git-update-ref refs/remotes/origin/main HEAD" "git-remote set-url origin X" \
         "git-config remote.origin.url X" "find . -maxdepth 0 -exec git remote set-url origin X \\;" \
         "git --attr-source HEAD remote set-url origin X"; do
  run "$GUARD" "$(bash_p "$c")"
  expect "B1-B6 denies: $c" deny
done
for c in "git push origin main:main" "git -c user.name=x commit -m y" "git fetch origin main:main" \
         "echo GIT_CONFIG_COUNT=1 git" "git -c core.autocrlf=false status"; do
  run "$GUARD" "$(bash_p "$c")"
  expect "B1-B6 control allows: $c" none
done

printf '\n[091 R7] the placement table is the developer'"'"'s\n'
mkdir -p "$P/.claude"; printf 'mutation\tlocal\tx\n' > "$P/.claude/workload-placement.tsv"
run "$GUARD" "$(write_p "$P/.claude/workload-placement.tsv" "mutation	cloud	x")"
expect "R7 a Write of .claude/workload-placement.tsv is denied" deny
case "$(reason)" in *"R7"*) ok "the reason names R7" ;; *) bad "reason: $(reason | head -c 120)" ;; esac
run "$GUARD" "$(edit_p "$P/.claude/workload-placement.tsv" "local" "cloud")"
expect "R7 an Edit of it is denied" deny
run "$GUARD" "$(jq -cn --arg p "$P/.claude/workload-placement.tsv" '{tool_name:"Edit",tool_input:{file_path:$p}}')"
expect "R7 a delegated shell write (no bytes) is denied" deny
run "$GUARD" "$(write_p "$P/.CLAUDE/Workload-Placement.TSV" "x")"
expect "R7 a case-folded spelling is denied" deny
ln -s "$P/.claude/workload-placement.tsv" "$P/docs/innocent.tsv"
run "$GUARD" "$(write_p "$P/docs/innocent.tsv" "x")"
expect "R7 a symlink onto it is denied" deny
run "$GUARD" "$(write_p "$P/scripts/workload-placement.tsv" "x")"
expect "R7 the template's table (CORE, scripts/) is not this rule's" none
run "$GUARD" "$(bash_p "cat .claude/workload-placement.tsv")"
expect "R7 reading it is fine" none

printf '\n[095-R3] MCP tools  (095-AC-3, trust half)\n'
mcp_p() { jq -cn --arg t "$1" --argjson i "$2" --arg w "$P" '{tool_name:$t,tool_input:$i,cwd:$w}'; }
run "$GUARD" "$(mcp_p mcp__fs__write_file "$(jq -cn --arg p "$P/.git/claude-developer-words" '{path:$p,content:"x"}')")"
expect "095-AC-3 mcp__fs__write_file to .git/claude-developer-words" deny
run "$GUARD" "$(mcp_p mcp__fs__write_file '{"path":"src/a.txt","content":"x"}')";        expect "095-AC-3 mcp__fs__write_file to src/a.txt" none
run "$GUARD" "$(mcp_p mcp__fs__edit_file "$(jq -cn --arg p "$ACC" '{path:$p,edits:[{oldText:"a",newText:"b"}]}')")"; expect "an MCP edit of an acceptance.md" deny
run "$GUARD" "$(mcp_p mcp__fs__move_file '{"source":"x","destination":".git/hooks/pre-commit"}')"; expect "an MCP move into .git" deny
run "$GUARD" "$(mcp_p mcp__shell__run '{"command":"bash scripts/project-maintenance.sh --trust --yes"}')"; expect "a command string is judged as shell text" deny
run "$GUARD" "$(mcp_p mcp__fs__read_file "$(jq -cn --arg p "$P/.git/claude-developer-words" '{path:$p}')")"; expect "a read tool by name is left alone" none

printf '\n[095-R8] --trust counts as a word, not as prose  (095-AC-5, trust half)\n'
run "$GUARD" "$(bash_p 'bash scripts/finding.sh --add "the maintenance prompt takes --trust from a pty" --spec 095 --kind gap')"
expect "095-AC-5 finding.sh prose naming --trust" none
run "$GUARD" "$(bash_p 'A=--trust; bash scripts/project-maintenance.sh $A')";            expect "an assignment carrying --trust" deny
run "$GUARD" "$(bash_p 'bash -c "scripts/project-maintenance.sh --trust"')";             expect "--trust inside a bash -c program" deny
run "$GUARD" "$(bash_p 'eval "scripts/project-maintenance.sh --trust"')";                expect "--trust inside eval" deny
run "$GUARD" "$(bash_p 'echo "scripts/project-maintenance.sh --trust" | sh')";           expect "--trust on a line piped into sh" deny
run "$GUARD" "$(bash_p 'bash scripts/project-maintenance.sh --trust=1')";                expect "--trust=1" deny
run "$GUARD" "$(bash_p "bash -xc 'bash scripts/project-maintenance.sh --trust'")";      expect "adversarial #10: a -xc cluster" deny
run "$GUARD" "$(bash_p "$(printf "cat >> notes.md <<'X'\nbash -c 'x' and later --trust in prose\nX")")"; expect "a heredoc handed to cat is data, even after -c" none
run "$GUARD" "$(bash_p "$(printf "bash <<'X'\nscripts/project-maintenance.sh --trust\nX")")"; expect "control: a heredoc handed to bash is a program" deny
run "$GUARD" "$(bash_p "bash -c -x 'bash scripts/project-maintenance.sh --trust'")";   expect "/security-review: bash -c -x" deny
run "$GUARD" "$(bash_p "bash -c -- 'bash scripts/project-maintenance.sh --trust'")";   expect "/security-review: bash -c --" deny
run "$GUARD" "$(bash_p 'sh <<< "scripts/project-maintenance.sh --trust"')";             expect "adversarial #10: a here-string" deny
run "$GUARD" "$(bash_p "python3 -c \"import subprocess; subprocess.run(['bash','scripts/project-maintenance.sh','--trust'])\"")"; expect "adversarial #10: a list form" deny
run "$GUARD" "$(bash_p 'git config diff.x.y.textconv sh')";                              expect "adversarial #7: a dotted subsection" deny
run "$GUARD" "$(bash_p 'git config difftool.x.path /tmp/x')";                            expect "adversarial #7: difftool.*.path" deny

printf '\n[095-R10] git config keys that run a program  (095-AC-5)\n'
run "$GUARD" "$(bash_p 'git config core.hooksPath /tmp/h')";       expect "095-AC-5 git config core.hooksPath" deny
case "$(reason)" in *"spec 095"*) ok "  the reason cites 095" ;; *) bad "  the reason does not cite 095" ;; esac
for k in core.fsmonitor core.sshCommand filter.lfs.smudge credential.helper diff.x.textconv merge.x.driver init.templateDir core.worktree; do
  run "$GUARD" "$(bash_p "git config $k /tmp/x")";                 expect "git config $k" deny
done
run "$GUARD" "$(bash_p 'git config --global core.editor vim')";    expect "a --global exec key" deny
run "$GUARD" "$(bash_p 'git config --unset core.hooksPath')";      expect "--unset of an exec key" deny
run "$GUARD" "$(bash_p 'git config "$k" /tmp/x')";                 expect "threat model: a key spelled at runtime" deny
run "$GUARD" "$(bash_p 'git -c core.fsmonitor=false status')";     expect "095-AC-5 a one-shot git -c stays allowed" none
run "$GUARD" "$(bash_p 'git config --get core.hooksPath')";        expect "reading an exec key" none
run "$GUARD" "$(bash_p 'git config user.name t')";                 expect "control: an ordinary key" none

printf '\n[095] sabotage\n'
MUT2="$WORK/mut095"; mkdir -p "$MUT2"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MUT2"/ 2>/dev/null
python3 - "$MUT2/destructive_command.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'if _EXEC_KEY.match(words[0]) or re.search(r"[$`*?\\[]", words[0]):'
assert old in s, "sabotage target not found"
open(p, "w").write(s.replace(old, 'if False:'))
PY
run "$MUT2/trust-anchor-guard-hook.sh" "$(bash_p 'git config core.hooksPath /tmp/h')"
expect "sabotage 095-R10: without the exec-key rule core.hooksPath passes" none
MUT3="$WORK/mut095b"; mkdir -p "$MUT3"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MUT3"/ 2>/dev/null
python3 - "$MUT3/trust-anchor-guard-hook.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '        if touches_git(q):\n            print("store"); sys.exit(0)\n'
assert old in s, "sabotage target not found"
open(p, "w").write(s.replace(old, ''))
PY
run "$MUT3/trust-anchor-guard-hook.sh" "$(mcp_p mcp__fs__write_file "$(jq -cn --arg p "$P/.git/claude-developer-words" '{path:$p,content:"x"}')")"
expect "sabotage 095-R3: without the MCP path scan the store write passes" none

printf '\n[098-R1] a symlink at any component of the path  (098-AC-1)\n'
ln -s .git "$P/gd"
run "$GUARD" "$(write_p "$P/gd/info/exclude" "x")";    expect "098-AC-1 Write gd/info/exclude (gd -> .git) is denied" deny
case "$(reason)" in *"inside a git directory"*) ok "  as a write inside a git directory" ;; *) bad "  the wrong reason: $(reason | head -1)" ;; esac
run "$GUARD" "$(write_p "$P/gd/description" "x")";     expect "098-AC-1 Write gd/description is denied" deny
run "$GUARD" "$(write_p "gd/config" "x")";             expect "a relative gd/config, resolved against the payload's cwd, is denied" deny
run "$GUARD" "$(write_p "$P/docs/notes.md" "x")";      expect "098-AC-1 Write docs/notes.md in the same project passes" none
for c in 'chmod 000 .git' 'chmod -R 000 .git/objects' 'mv .git .git2' 'chown nobody "$PWD/.git"' 'setfacl -m u:x:0 ./.git'; do
  run "$GUARD" "$(bash_p "$c")"; expect "threat #6: [$c] changes the git dir and is refused" deny
done
for c in 'chmod +x scripts/a.sh' 'git mv .github/x.yml .github/y.yml' 'mv .gitignore .gitignore.bak' 'chmod 644 docs/.gitkeep'; do
  run "$GUARD" "$(bash_p "$c")"; expect "  control: [$c] passes" none
done
# TB1: a git dir kept outside the tree has no .git component; the project's .git file names it.
Q="$WORK/sep"; mkdir -p "$Q"; git init -q --separate-git-dir="$WORK/sepgd" "$Q"
runq() { OUT=$(printf '%s' "$1" | (cd "$Q" && CLAUDE_PROJECT_DIR="$Q" "$BASH_BIN" "$GUARD") 2>/dev/null); VERDICT=$(hook_verdict "$OUT"); }
runq "$(jq -cn --arg p "$WORK/sepgd/config" --arg w "$Q" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:$w}')"
expect "TB1 a Write into a git dir kept elsewhere is denied" deny
ln -s "$WORK/sepgd" "$Q/sg"
runq "$(jq -cn --arg p "$Q/sg/hooks/pre-commit" --arg w "$Q" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:$w}')"
expect "TB1 and through a link to it" deny
runq "$(jq -cn --arg p "$Q/src.txt" --arg w "$Q" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:$w}')"
expect "TB1 an ordinary file in that project passes" none
MUT1="$WORK/mut1"; mkdir -p "$MUT1"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MUT1"/
sed 's/^      guard_precheck_link "\$INPUT" \&\& HIT=1$/      [ -L "$_fp" ] \&\& HIT=1/' "$GUARD" > "$MUT1/trust-anchor-guard-hook.sh"
if cmp -s "$GUARD" "$MUT1/trust-anchor-guard-hook.sh"; then bad "098-R1 sabotage target not found"; else
  run "$MUT1/trust-anchor-guard-hook.sh" "$(write_p "$P/gd/info/exclude" "x")"
  expect "098-R1 sabotage: testing only the last component lets gd/info/exclude through" none
fi
rm -f "$P/gd"

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
