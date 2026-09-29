# Plan — 021

1. `scripts/template-autosync.sh` usage header: add `--owed` and `--unlisted` entries with exit codes; state docs/skills are `[manual]`'s (FR-01).
2. `scripts/core-owed-tick-guard-hook.sh` header: a third bullet under WHAT COUNTS AS OWED naming what is excluded and the 0-of-4 measurement (FR-02).
3. `scripts/test-template-autosync-owed.sh`: AC-13 fixture with a RULE_DOCS doc and a skill, both edited and committed; assert `--owed` exit 1 and `[manual]` names both on a bumped sync (FR-03).
4. Verify: owed test green; mutate `core_divergence` to include docs → AC-13 red; revert.
