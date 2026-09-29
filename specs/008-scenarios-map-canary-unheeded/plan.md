# Plan — 008 scenarios-map canary unheeded

## Approach

1. `scripts/project-maintenance.sh` section 2: keep the loop and the `[CONTEXT-COST] <path>` shape
   the canary test parses. Pick the hint by role (INDEX / single-file map / split index / feature
   file). For scenario-map files, call a small `record_map_canary PATH KB HINT` helper that dedups on
   the open key and shells to `scripts/finding.sh --add … --kind debt`. A missing or failing
   finding.sh is an `add` (red).
2. `scripts/spec-register-orientation-hook.sh`: set `SCEN_BLOATED=1` when any map file is named,
   and append one remedy line to SIZE_WARN.
3. `.claude/rules/scenarios.md`: extend the canary bullet with the record-and-review sentence.
4. Tests: C31–C36 in `test-project-maintenance.sh` (copy the real finding.sh into the fixture),
   plus two arms in `test-scenario-map-canary.sh`.
5. Register: reword row 008 (≤300 B, no enumeration), and update `INDEX.pending.md` with the
   2026-09-29 table.

## Layout predicate

A split layout means `specs/scenarios/` contains at least one `.md` file. That is the same predicate
as `scenario-map-layout.sh`, inlined because section 2 already globs the directory.

## Risks

- Fixture tmpdirs in the canary suite are not git repos. finding.sh falls back to `$PWD`, which is
  the fixture, so nothing writes into the template's own ledger. The test asserts this (the
  template's FINDINGS.md hash is unchanged).
