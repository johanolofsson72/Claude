#!/bin/bash
# validate-hooks.sh — does every hook Claude Code loads for this project resolve? (spec 086)
#
# Reads the project's .claude/settings.json and settings.local.json, the user's
# ~/.claude/settings.json and hooks/hooks.json of each enabled plugin, and reports:
#
#   UNRESOLVED  a command whose program or script does not exist, or that keeps a `$` after the
#               variables Claude Code sets are expanded (F001: a literal ${CLAUDE_PLUGIN_ROOT}
#               failed at every session start, in every project, for months)
#   CHANNEL     a project-authored, non-CORE hook that emits a top-level additionalContext or a
#               hookSpecificOutput with no hookEventName (F003: rocky's SC-id guards were inert
#               denies that no CORE test could see)
#   UNREADABLE  a settings or hooks file that does not parse
#
# Runs nothing it reads. The logic is in scripts/hook_audit.py; this wrapper finds the project root
# and hands it the CORE list, so CORE hooks (covered by test-hook-channels.sh) are not judged twice.
#
# Usage:  bash scripts/validate-hooks.sh [project-root]
# Exit:   0 clean · 1 findings · 2 cannot run (no python3, no hook_audit.py, bad root)
#
# project-maintenance.sh runs it on every pass and reports a non-zero exit as [HOOKS].
# Scenario ids: none here; scripts/test-validate-hooks.sh is the proof.
set -uo pipefail

SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
[ -d "$ROOT" ] || { echo "validate-hooks: no such directory: $ROOT" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "validate-hooks: python3 not found — hooks not checked" >&2; exit 2; }
[ -f "$SD/hook_audit.py" ] || { echo "validate-hooks: scripts/hook_audit.py missing — run /project-update" >&2; exit 2; }

# An unknown CORE list is passed as unset, never as empty: empty would mean "nothing is CORE".
if [ -f "$SD/template-autosync.sh" ] && CORE=$(bash "$SD/template-autosync.sh" --list-core-scripts 2>/dev/null) && [ -n "$CORE" ]; then
  HOOK_AUDIT_CORE="$CORE" python3 "$SD/hook_audit.py" "$ROOT"
else
  python3 "$SD/hook_audit.py" "$ROOT"
fi
