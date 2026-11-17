#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-validate-hooks.sh — the hook audit (spec 086, F001 F003).
#
#   bash scripts/test-validate-hooks.sh
#
# Every case builds a project and a HOME of its own (HOOK_AUDIT_HOME), so the developer's real
# ~/.claude is never read and a red here is never about this machine. V13 runs the audit over the
# template's own settings.json, so a CORE hook that stops resolving fails here first.
set -uo pipefail
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AUDIT="$SD/hook_audit.py"
T=$(mktemp -d); T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
P=0; F=0
ok()  { P=$((P + 1)); printf '  ok   %s\n' "$1"; }
bad() { F=$((F + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

# fix <name> — an empty project and an empty HOME; prints the project path, HOME is <path>.home
fix() {
  local d="$T/$1"
  mkdir -p "$d/proj/.claude" "$d/proj/scripts" "$d/home/.claude/plugins"
  printf '%s' "$d"
}
settings() { printf '{"hooks":{"%s":[{"matcher":"%s","hooks":[%s]}]}%s}\n' "$2" "${3:-}" "$4" "${5:-}" > "$1"; }
cmdhook() { jq -cn --arg c "$1" '{type:"command",command:$c}'; }
audit() { # audit <fixture> [env...] — stdout+stderr, rc in $RC
  local d=$1; shift
  OUT=$(env HOOK_AUDIT_HOME="$d/home" "$@" python3 "$AUDIT" "$d/proj" 2>&1); RC=$?
}
has()  { grep -Fq -e "$2" <<< "$OUT" && ok "$1" || bad "$1 — no '$2'" "$OUT"; }
hasnt(){ grep -Fq -e "$2" <<< "$OUT" && bad "$1 — has '$2'" "$OUT" || ok "$1"; }
rc()   { [ "$RC" = "$2" ] && ok "$1" || bad "$1 — exit $RC, expected $2" "$OUT"; }

echo "validate-hooks self-test (spec 086)"

# V1 — a clean project: a CORE-style hook that resolves, a builtin, and a substitution prefix
D=$(fix v1); printf '#!/bin/bash\nexit 0\n' > "$D/proj/scripts/a-hook.sh"
settings "$D/proj/.claude/settings.json" PreToolUse Bash \
  "$(cmdhook 'bash "$CLAUDE_PROJECT_DIR/scripts/a-hook.sh"'),$(cmdhook "echo '{\"x\":1}'"),$(cmdhook 'INPUT=$(cat); printf %s "$INPUT" | grep -q x || exit 0')"
audit "$D"; rc "V1 a resolving project is clean" 0; has "V1 the summary counts three hooks" "3 command hook(s)"

# V2 — the F001 shape in a user hook: ${CLAUDE_PLUGIN_ROOT} outside a plugin is never set
D=$(fix v2); settings "$D/home/.claude/settings.json" SessionStart "" "$(cmdhook 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"')"
audit "$D"; rc "V2 an unexpanded variable is a finding" 1
has "V2 named UNRESOLVED with its source and event" "UNRESOLVED user SessionStart: unexpanded variable in the script path"

# V3/V4 — plugin hooks: ${CLAUDE_PLUGIN_ROOT} expands to the install path, args form included
D=$(fix v3); PL="$D/home/.claude/plugins/cache/m/p/1"; mkdir -p "$PL/hooks" "$PL/scripts"
: > "$PL/scripts/ok.mjs"
printf '{"enabledPlugins":{"p@m":true,"off@m":false}}\n' > "$D/home/.claude/settings.json"
jq -n --arg ip "$PL" --arg off "$D/off" '{version:2,plugins:{"p@m":[{scope:"user",installPath:$ip}],"off@m":[{scope:"user",installPath:$off}]}}' \
  > "$D/home/.claude/plugins/installed_plugins.json"
jq -n '{hooks:{SessionStart:[{hooks:[{type:"command",command:"node",args:["${CLAUDE_PLUGIN_ROOT}/scripts/ok.mjs"]}]}]}}' > "$PL/hooks/hooks.json"
mkdir -p "$D/off/hooks"; settings "$D/off/hooks/hooks.json" Stop "" "$(cmdhook 'bash /nowhere/x.sh')"
if command -v node >/dev/null 2>&1; then
  audit "$D"; rc "V3 a plugin args hook that resolves is clean" 0
else ok "V3 skipped — node not installed"; fi
hasnt "V9 a disabled plugin's hooks are not read" "/nowhere/x.sh"
jq -n '{hooks:{SessionStart:[{hooks:[{type:"command",command:"bash '"'"'${CLAUDE_PLUGIN_ROOT}'"'"'/run.sh"}]}]}}' > "$PL/hooks/hooks.json"
audit "$D"; rc "V4 a single-quoted \${CLAUDE_PLUGIN_ROOT} is a finding" 1
has "V4 named as unexpanded, in the plugin" "UNRESOLVED plugin p@m SessionStart: unexpanded variable"
jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"bash \"${CLAUDE_PLUGIN_ROOT}/gone.sh\""}]}]}}' > "$PL/hooks/hooks.json"
audit "$D"; has "V4b an expanded plugin script that is missing is named" "script not found '$PL/gone.sh'"

# V5/V6 — a missing project script, a program nowhere on PATH
D=$(fix v5); settings "$D/proj/.claude/settings.json" Stop "" \
  "$(cmdhook 'bash "$CLAUDE_PROJECT_DIR/scripts/missing.sh"'),$(cmdhook 'nosuchprog-086 --x')"
audit "$D"; rc "V5 missing pieces are findings" 1
has "V5 a missing project script is named" "script not found '$D/proj/scripts/missing.sh'"
has "V6 a program not on PATH is named" "program not on PATH 'nosuchprog-086'"

# V7/V8 — F003: a project-authored hook with the inert-deny defect, and a top-level additionalContext
D=$(fix v7)
printf '%s\n' '#!/bin/bash' "jq -n '{hookSpecificOutput:{permissionDecision:\"deny\"}}'" > "$D/proj/scripts/sc-id-guard.sh"
printf '%s\n' '#!/bin/bash' "echo '{\"additionalContext\": \"hi\"}'" > "$D/proj/scripts/nudge.sh"
settings "$D/proj/.claude/settings.json" PreToolUse Edit \
  "$(cmdhook 'bash "$CLAUDE_PROJECT_DIR/scripts/sc-id-guard.sh"'),$(cmdhook 'bash scripts/nudge.sh')"
audit "$D"; rc "V7 channel defects are findings" 1
has "V7 the inert deny is named" "CHANNEL project PreToolUse[Edit]: scripts/sc-id-guard.sh emits hookSpecificOutput with no hookEventName"
has "V8 the top-level additionalContext is named" "scripts/nudge.sh emits a top-level additionalContext"
audit "$D" HOOK_AUDIT_CORE=$'sc-id-guard.sh\nnudge.sh'
rc "V7b a CORE hook is not channel-checked here (test-hook-channels.sh owns it)" 0
printf '%s\n' '#!/bin/bash' "jq -n '{hookSpecificOutput:{hookEventName:\"PreToolUse\",permissionDecision:\"deny\"}}'" > "$D/proj/scripts/sc-id-guard.sh"
audit "$D"; hasnt "V7c a guard that names its event is clean" "sc-id-guard.sh emits"

# V10 — a settings file that does not parse is said, never read as no hooks
D=$(fix v10); printf '{ "hooks": ' > "$D/proj/.claude/settings.local.json"
audit "$D"; rc "V10 an unreadable settings file is a finding" 1; has "V10 named UNREADABLE" "UNREADABLE $D/proj/.claude/settings.local.json"

# V12 — a leading ~ is HOME
D=$(fix v12); mkdir -p "$D/home/.claude/hooks"; : > "$D/home/.claude/hooks/x.sh"
settings "$D/home/.claude/settings.json" Stop "" "$(cmdhook 'bash ~/.claude/hooks/x.sh')"
audit "$D"; rc "V12 ~ expands to HOME" 0

# V13 — the template's own settings resolve, through the wrapper
D=$(fix v13)
OUT=$(HOOK_AUDIT_HOME="$D/home" bash "$SD/validate-hooks.sh" "$SD/.." 2>&1); RC=$?
rc "V13 every hook in the template's settings.json resolves" 0

echo "[098-R8] the two MCP guards' matchers"
m8() { # m8 <name> <matcher> [local-matcher]: a project wiring both guards under <matcher>
  local d; d=$(fix "$1")
  printf '#!/bin/bash\nexit 0\n' > "$d/proj/scripts/settings-edit-guard-hook.sh"
  printf '#!/bin/bash\nexit 0\n' > "$d/proj/scripts/trust-anchor-guard-hook.sh"
  settings "$d/proj/.claude/settings.json" PreToolUse "$2" \
    "$(cmdhook 'bash "$CLAUDE_PROJECT_DIR/scripts/trust-anchor-guard-hook.sh"'),$(cmdhook 'bash "$CLAUDE_PROJECT_DIR/scripts/settings-edit-guard-hook.sh"')"
  [ -n "${3:-}" ] && settings "$d/proj/.claude/settings.local.json" PreToolUse "$3" \
    "$(cmdhook 'bash "$CLAUDE_PROJECT_DIR/scripts/trust-anchor-guard-hook.sh"'),$(cmdhook 'bash "$CLAUDE_PROJECT_DIR/scripts/settings-edit-guard-hook.sh"')"
  audit "$d" HOOK_AUDIT_CORE="$(printf 'settings-edit-guard-hook.sh\ntrust-anchor-guard-hook.sh\n')"
}
m8 m1 'Edit|Write|MultiEdit|NotebookEdit|Bash|AskUserQuestion|mcp__.*'; rc "098-R8 the template's matcher is clean" 0
m8 m2 'Edit|Write|MultiEdit|NotebookEdit|Bash'; rc "098-R8 a matcher without mcp__ is a finding" 1
has "  named, with the guard" "MATCHER project PreToolUse[Edit|Write|MultiEdit|NotebookEdit|Bash]: trust-anchor-guard-hook.sh does not run for MCP tools"
has "  and the settings guard too" "settings-edit-guard-hook.sh does not run for MCP tools"
has "  with the fix" "Add |mcp__.* to"
m8 m3 'Edit|mcp__x__.*'; rc "threat #14: one server's tools only is a finding" 1; has "  naming the probe it missed" "does not match mcp__y__edit"
m8 m4 'Edit|mcp__('; rc "threat #14: a matcher that does not compile is a finding" 1; has "  said as such" "does not compile"
m8 m5 '*'; rc "'*' covers everything" 0
m8 m6 'Edit|Bash' 'mcp__.*'; rc "105-R11 a covering group in settings.local.json no longer hides the committed one" 1
m8 m7 'Write|Edit|mcp__'; rc "threat #14: a prefix that only a search would accept is a finding (fullmatch)" 1
no_matcher() { case "$OUT" in *MATCHER*) bad "$1" "$OUT" ;; *) ok "$1" ;; esac; }
# Not judged: the user's settings, and a wiring on any event but PreToolUse (clarification R8).
G2="$(cmdhook 'bash "$HOME/scripts/trust-anchor-guard-hook.sh"'),$(cmdhook 'bash "$HOME/scripts/settings-edit-guard-hook.sh"')"
D9=$(fix m9); settings "$D9/home/.claude/settings.json" PreToolUse 'Edit|Bash' "$G2"
audit "$D9"; no_matcher "098-R8 a user-level wiring is not judged"
D10=$(fix m10); settings "$D10/proj/.claude/settings.json" PostToolUse 'Edit|Bash' "$G2"
audit "$D10"; no_matcher "098-R8 a PostToolUse wiring is not judged"
SAB8="$T/sab8"; mkdir -p "$SAB8"
sed 's/    findings.extend(mcp_matcher_findings(wired))/    pass/' "$AUDIT" > "$SAB8/hook_audit.py"
if cmp -s "$AUDIT" "$SAB8/hook_audit.py"; then bad "098-R8 sabotage target not found"; else
  D8="$T/m2"; OUT=$(env HOOK_AUDIT_HOME="$D8/home" HOOK_AUDIT_CORE="$(printf 'settings-edit-guard-hook.sh\ntrust-anchor-guard-hook.sh\n')" python3 "$SAB8/hook_audit.py" "$D8/proj" 2>&1); RC=$?
  hasnt "098-R8 sabotage: without the check the MCP gap goes unnamed" "does not run for MCP tools"
fi

echo "[105-R11] every guard in scripts/ is wired, by its resolved script, in the committed file"
w11() { # w11 <name> <matcher> <command> [local-command]: trust-anchor present, wired by <command>
  local d; d=$(fix "$1")
  printf '#!/bin/bash\nexit 0\n' > "$d/proj/scripts/trust-anchor-guard-hook.sh"
  settings "$d/proj/.claude/settings.json" PreToolUse "$2" "$(cmdhook "$3")"
  [ -n "${4:-}" ] && settings "$d/proj/.claude/settings.local.json" PreToolUse "$2" "$(cmdhook "$4")"
  audit "$d" HOOK_AUDIT_CORE="trust-anchor-guard-hook.sh"
}
FULL='Edit|Write|MultiEdit|NotebookEdit|Bash|AskUserQuestion|mcp__.*'
w11 r1 "$FULL" 'bash "$CLAUDE_PROJECT_DIR/scripts/trust-anchor-guard-hook.sh"'; rc "105-R11 control: a fully wired guard is clean" 0
w11 r2 "$FULL" 'echo ok'; rc "105-R11 a guard in scripts/ that nothing runs is a finding" 1
has "  named UNWIRED" "UNWIRED project PreToolUse: scripts/trust-anchor-guard-hook.sh"
w11 r3 "$FULL" 'echo trust-anchor-guard-hook.sh'; rc "105-R11 a command that only names the guard does not wire it" 1; has "  UNWIRED" "UNWIRED"
w11 r4 "$FULL" 'echo ok' 'bash "$CLAUDE_PROJECT_DIR/scripts/trust-anchor-guard-hook.sh"'; rc "105-R11 wiring in settings.local.json alone is UNWIRED" 1; has "  UNWIRED" "UNWIRED"
w11 r5 'Edit|Write|mcp__.*' 'bash "$CLAUDE_PROJECT_DIR/scripts/trust-anchor-guard-hook.sh"'; rc "105-R11 a matcher missing Bash is a finding" 1
has "  naming the tools it misses" "does not run for MultiEdit, NotebookEdit, Bash, AskUserQuestion"
D11=$(fix r6); printf '#!/bin/bash\nexit 0\n' > "$D11/proj/scripts/trust-anchor-guard-hook.sh"
printf '{"hooks":{"PreToolUse":[{"matcher":"%s","hooks":[{"type":"command","async":true,"command":"bash \\"$CLAUDE_PROJECT_DIR/scripts/trust-anchor-guard-hook.sh\\""}]}]}}\n' "$FULL" > "$D11/proj/.claude/settings.json"
audit "$D11" HOOK_AUDIT_CORE="trust-anchor-guard-hook.sh"; rc "105-R11 an async guard is a finding (threat #34)" 1; has "  named ASYNC" "ASYNC project"
D12=$(fix r7); audit "$D12"; rc "105-R11 control: a guard the project never received needs no wiring" 0
SAB11="$T/sab11"; mkdir -p "$SAB11"
sed 's/    findings.extend(wiring_findings(root, wired))/    pass/' "$AUDIT" > "$SAB11/hook_audit.py"
if cmp -s "$AUDIT" "$SAB11/hook_audit.py"; then bad "105-R11 sabotage target not found"; else
  OUT=$(env HOOK_AUDIT_HOME="$T/r2/home" HOOK_AUDIT_CORE="trust-anchor-guard-hook.sh" python3 "$SAB11/hook_audit.py" "$T/r2/proj" 2>&1); RC=$?
  rc "105-R11 sabotage: without the audit an unwired guard passes" 0
fi

# V14 — the wrapper refuses a root that is not there, rather than calling it clean
OUT=$(bash "$SD/validate-hooks.sh" "$T/nope" 2>&1); RC=$?
rc "V14 a missing root is exit 2" 2

printf '\n%s passed, %s failed\n' "$P" "$F"
[ "$F" -eq 0 ]
