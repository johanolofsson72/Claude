# Plan — 006

1. `scripts/skill-reachable.sh` (bash 3.2-safe, python3 only for the JSON reads). Resolve the
   project root (`CLAUDE_PROJECT_DIR`, else the git toplevel, else `$PWD`) and the config dir
   (`CLAUDE_CONFIG_DIR`, else `$HOME/.claude`). Look in the project skills, then the user skills,
   then the plugin skills. `--required` expands to the in-script list, and each missing name gets
   its install hint.
2. `scripts/ui-design-hook.sh`: after the UI decision, run the check for `frontend-design`. On
   exit 1, `notice_both` a headline and the reason, followed by the existing reminder text. Any
   other exit keeps today's payload.
3. `scripts/project-maintenance.sh` §3h: guarded on the script existing, each missing skill is
   `add`ed and exit 3 is `note`d.
4. `CORE_SCRIPTS` += `skill-reachable.sh test-skill-reachable.sh`.
5. `scripts/test-skill-reachable.sh`: fixture config and project dirs. Bite-check by mutating.
6. Pending-archive note, register tick, commit, push.
