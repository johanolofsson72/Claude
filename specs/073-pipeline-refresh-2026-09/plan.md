# Plan — 073

Workstreams on disjoint files, so they can run in parallel:

- **A — sync engine** (lead): `sync-prompt.md`, the three skills, `template-autosync.sh` clone
  discovery, `template-autosync-hook.sh` verdict, `speckit-extension-policy.sh`, new `speckit-version`.
- **B — Linux**: `project-maintenance.sh`, `portability_audit.py`, `local-llm-stats.sh`,
  `.claude/skills/tla/SKILL.md`, new `install-global-skills.sh`, tests.
- **C — hook latency**: `bash-write-detect-hook.sh`, `bash-write-guard-hook.sh`, the python guards,
  `.claude/settings.json` wiring; measured before/after.
- **D — context diet**: `.claude/rules/*.md` → trimmed rules + `.claude/docs/*` rationale.
- **E — supply chain + tool docs** (after A): wizard/update defaults, `project-freshness.sh`
  osv-scanner, `docs/testing.md`, `docs/deployment.md`, agent frontmatter.
- **F — verification**: all harnesses, Linux container, humanizer on prose.
- **G — rollout**: 15 projects, sync paths only, push.

New CORE scripts are registered in `CORE_SCRIPTS` by workstream A.
