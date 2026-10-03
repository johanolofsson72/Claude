#!/bin/bash
# PreToolUse guard: the files that wire every hook stay out of the agent's tools for the keys that
# decide which hooks run (spec 089).
#
# WHY THIS EXISTS
# ---------------
# Every gate in this template is a PreToolUse hook wired in a settings file, and a settings file is
# JSON the gated agent could write. One Edit of .claude/settings.json removed every hook (F081, 083
# adversarial #15). An `env` entry in the gitignored settings.local.json set SPEC_ACCEPTANCE=off or
# ALLOW_CORE_MACHINERY_EDIT=1 for the next session and left no diff behind (F103, 088 adversarial
# #11). `"disableAllHooks": true` in any of them switched everything off at once.
#
# WHAT IT GUARDS (developer O1, O2)
# ---------------------------------
# Three files: <project>/.claude/settings.json, <project>/.claude/settings.local.json and
# <config>/settings.json (CLAUDE_CONFIG_DIR, default ~/.claude). Every key except a safe list
# ($schema, language, model, and permissions.allow/ask/additionalDirectories): spec 095 R2 inverted
# 089's three keys (F115). Another
# project's settings are not this guard's. The verdict is scripts/settings_guard.py:
#
#   Edit/Write/MultiEdit  the call is applied to the current bytes as the tool would apply it, and a
#                         change to any of the three keys is denied, as is a result that is not a
#                         JSON object (Claude Code drops a file it cannot parse, hooks and all)
#   NotebookEdit, a glob, a path with no bytes (bash-write-guard's delegated shell write)
#                         denied: nothing to compare
#   Bash                  a simple command that names a guarded file passes only when it reads
#                         (cat, jq, grep, sed -n, git diff/add/commit, …) on a line that changes no
#                         variable, function or alias first (095 R7); a redirection into one never does
#   Bash, git             a verb that writes the tree (checkout, restore, stash pop, apply, merge, …)
#                         is judged by what git says it would write (095 R1, F114). A bound (/tla
#                         GAP-1): a hand edit landing between the check and git's run is overwritten
#                         by restore, checkout -- path and reset --hard, which do not refuse
#   mcp__* tools          every string in the input, as a path and as a command (095 R3, F116); the
#                         matcher in settings.json must list mcp__.* for this to run (R4)
#
# THE ROUTES THAT STAY OPEN (developer O3, O4). No override variable, no template exemption. The
# developer edits the file by hand, or runs a command with the `!` prefix: that runs outside the
# agent's tools, so no PreToolUse hook sees it. The SessionStart autosync wires project hooks as a hook
# of its own, not as an agent tool, and is not affected.
#
# THE BOUND. Command text only, like bash-write-guard and trust-anchor-guard. A script the agent writes
# and runs, a tool that writes a settings file it was not handed on the command line
# (sync-core-hooks.py), and a directory assembled at runtime from parts that spell neither the file nor
# its directory are not seen here.
#
# AN ASSUMPTION (/tla GAP-1). A Write is judged against the bytes on disk at check time. If the developer
# hand-edits the file before the Write lands, a Write allowed against the old bytes would put the old
# keys back. Claude Code refuses a Write/Edit to a file that changed since it was read, and that check
# is what closes the race: specs/089-settings-edit-guard/SettingsGuard.tla holds with it, and fails in
# 4 steps without it.
#
# FAILS CLOSED on a call the pre-check sends to the verdict when the verdict cannot run, except an
# Edit/Write of this guard's own files: a guard that cannot run must not block its own repair (the
# 2026-10-01 trust-anchor lockout). Never echoes the command. Exit: always 0.

set -u

INPUT=$(cat 2>/dev/null || true)   # mutant-equivalent: cat on a pipe does not fail; the || only guards a closed stdin
[ -z "$INPUT" ] && exit 0

# Cheapest exit first: only the tool call is matched, from "tool_input" on, so the harness fields
# (transcript_path, cwd) never wake the verdict.
TI=${INPUT#*\"tool_input\"}
HIT=0
if [ "${#TI}" -gt 4096 ]; then
  HIT=1
else
  N=${TI//[\"\'\\]/}
  shopt -s nocasematch
  case "$N" in
    *sett*|*.cla*) HIT=1 ;;
  esac
  shopt -u nocasematch
  case "$TI" in
    *"\$'"*) HIT=1 ;;                                  # ANSI-C quoting hides the letters
    *\"command\"*) case "$TI" in *[*?[]*) HIT=1 ;; esac ;;   # a glob can spell either name
  esac
  # Spec 095 R1: a git verb that rewrites the tree names no settings file (`git checkout HEAD -- .`),
  # and git aliases can spell one, so any git command with a second word goes to the verdict.
  case "$TI" in
    # On the raw payload: a JSON \n or \t before git is a boundary (a heredoc body), and stripping the
    # backslash would glue it to the word.
    *\"command\"*) [[ $TI =~ (^|[^A-Za-z0-9_.-]|\\[nt])git[[:space:]]+[^[:space:]] ]] && HIT=1 ;;
  esac
  # Spec 095 R3: an MCP or plugin tool names its file in a field of its own choosing.
  [[ $INPUT =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"mcp__ ]] && HIT=1
  # A file_path that is a symlink, or a hard link to a guarded file, under an innocent name.
  if [ "$HIT" -eq 0 ] && [[ $TI =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    _fp="${BASH_REMATCH[1]}"
    case "$_fp" in *[*?[]*) HIT=1 ;; esac
    [ -L "$_fp" ] && HIT=1
    if [ "$HIT" -eq 0 ] && [ -f "$_fp" ]; then   # mutant-equivalent: with HIT=1 the loop can only set HIT=1 again
      _cfg="${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}"
      for _s in "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" "$_cfg/settings.json"; do
        [ -f "$_s" ] && [ "$_fp" -ef "$_s" ] && { HIT=1; break; }
      done
    fi
  fi
fi
[ "$HIT" -eq 1 ] || exit 0

HOOK_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! . "$HOOK_DIR/guard-lib.sh" 2>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED — settings-edit-guard cannot load scripts/guard-lib.sh, and this call names a settings file. Re-run the template sync (it is in CORE_SCRIPTS)."}}'
  exit 0
fi

VERDICT=$(printf '%s' "$INPUT" | python3 "$HOOK_DIR/settings_guard.py" 2>/dev/null) || VERDICT="crash"
[ -n "$VERDICT" ] || VERDICT="crash"
KIND=${VERDICT%%$'\t'*}
REST=""
case "$VERDICT" in *$'\t'*) REST=${VERDICT#*$'\t'} ;; esac
TARGET=${REST%%$'\t'*}
KEYS=""
case "$REST" in *$'\t'*) KEYS=${REST#*$'\t'} ;; esac

# The repair path: a crash denies everything it would judge except an edit of the guard itself.
if [ "$KIND" = crash ] && [[ $TI =~ \"file_path\"[[:space:]]*:[[:space:]]*\"[^\"]*/scripts/(settings-edit-guard-hook\.sh|settings_guard\.py|shell_glob\.py|guard-lib\.sh)\" ]]; then
  guard_context "settings-edit-guard crashed and ALLOWED this edit unchecked, because it is an edit of the guard's own code (${BASH_REMATCH[1]}): a guard that cannot run must not block its own repair. Fix the crash; every settings call it would judge is denied until then."
  exit 0
fi

ROUTES="Hook wiring and hook environment are the developer's to change. Show them the exact change you wanted (the JSON before and after, or the command), and ask them to apply it by hand in their editor, or to run it themselves with the \`!\` prefix (a \`!\` command runs outside the agent's tools, so no PreToolUse hook sees it). There is no override variable (spec 089, developer decision O3). Reading stays open: the Read tool, or cat / jq / grep in the shell."

case "$KIND" in
  none) exit 0 ;;
  settings-key)
    guard_deny "BLOCKED — this edit changes ${KEYS} in ${TARGET} (spec 089, 095).

Every settings key is guarded except a short safe list (\$schema, language, model, and permissions.allow, ask, additionalDirectories). hooks, env and disableAllHooks decide which guards run and what they see, and keys such as apiKeyHelper, statusLine or enabledPlugins run a command or add tools next session. Formatting and the safe keys stay editable.

$ROUTES" ;;
  settings-invalid)
    guard_deny "BLOCKED — after this edit ${TARGET} would not be a JSON object (spec 089).

Claude Code ignores a settings file it cannot parse, and every hook wired in it goes with it. Check the edit: a missing comma or brace is the usual cause.

$ROUTES" ;;
  settings-unreadable)
    guard_deny "BLOCKED — ${TARGET} is not a JSON object right now, so this guard cannot tell what the edit changes (spec 089).

The file needs a repair the developer makes by hand.

$ROUTES" ;;
  settings-shell)
    guard_deny "BLOCKED — a write to ${TARGET} that carries no bytes to check (a shell write, a NotebookEdit, or a glob path) (spec 089).

This guard judges a settings write by what it does to the guarded keys, and this route (a shell write, an MCP tool, a NotebookEdit) does not show it the result. Use the Edit tool for a change to another key; it is judged on the bytes.

$ROUTES" ;;
  settings-bash)
    guard_deny "BLOCKED — this shell command writes, or may write, a guarded settings file (spec 089). Derived target: ${TARGET}

The command is not shown here. Only reads pass when a command names one of the three settings files (cat, head, tail, grep, rg, jq, wc, diff, ls, stat, python3 -m json.tool <file>, git diff/log/show/status/add/commit, …). A redirection into one, an output option naming one, sed, cp, mv, rm, ln, touch, an interpreter or a script handed one are refused. If the file is only mentioned in prose (a message, a finding), drop the .claude/ prefix or use the Write tool for the text.

$ROUTES" ;;
  settings-git)
    guard_deny "BLOCKED — this git command would rewrite a settings file's guarded keys, or this guard cannot tell what it would write (spec 095). Target: ${TARGET}. Cause: ${KEYS}.

A git verb that writes the working tree (checkout, restore, switch, reset --hard, stash, clean, apply, am, merge, rebase, cherry-pick, revert, read-tree) is judged by the content it would leave. It passes when the settings files keep their hooks, env and other guarded keys, and is refused when they change or when git cannot answer. A pull from a configured remote is not judged.

$ROUTES" ;;
  crash)
    guard_deny "BLOCKED — settings-edit-guard crashed (python3 missing, or an error in scripts/settings_guard.py) on a call that names a settings file. It does not allow what it could not judge (spec 089). Its own files (scripts/settings-edit-guard-hook.sh, settings_guard.py, guard-lib.sh) stay editable with the Edit tool so it can be repaired." ;;
  *)
    guard_deny "BLOCKED — settings-edit-guard cannot read this call (the payload is not JSON), and its text names a settings file. A guard that cannot see what it guards does not allow (spec 089)." ;;
esac
exit 0
