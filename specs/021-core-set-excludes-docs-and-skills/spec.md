# 021 — core set excludes docs and skills

Track: spec-only. No entity, no state machine, no new external surface. Not hardened: three files,
no auth/PII/upload, no concurrency.

Found on msroute during `/project-update`, 2026-09-03. Diagnosis: `specs/INDEX.pending.md` § 021.

## Problem as filed

`core_divergence()` asks only about `CORE_SCRIPTS` and `CORE_RULES`. A project-authored change to a
template-owned file under `.claude/docs/` or `.claude/skills/` never reaches `--owed`, so
`core-owed-tick-guard-hook.sh` is told nothing and allows the tick. msroute reported `--owed` and
`--unlisted` empty while carrying two such edits.

## What was measured (2026-09-29)

1. **The report already exists.** `[manual]` (spec 007af, landed 2026-08-20, two weeks before the
   finding) names every doc or skill whose bytes differ from the manifest with no `.sync-local`
   record, on every syncing session start, with both remedies: merge with `/project-update`, or
   record it with `--accept-local`. The finder queried `--owed` and `--unlisted`, not that block.
2. **Fleet, 45 stamped projects:** 4 carry an unrecorded doc/skill divergence, one file each —
   `deployment.md` in teach, radar and fundit, `workflows.md` in msroute. msroute's two original
   files have since landed.
3. **None of the four is purely owed upstream.** teach adds its observability stack, fundit its
   Swarm secrets map, radar its ssh aliases, msroute holds an older copy. Gating the tick on them
   would have been wrong on at least 3 of 4 — the 33%-precision shape 007au rejected by name.
4. **The loss runs both ways.** A locally edited doc also stops receiving template fixes: msroute is
   missing the hook-output-channels correction in `workflows.md`, teach and fundit the dependency
   gate line in `deployment.md`. `[manual]` covers this direction too; its remedy is the same merge.

## Decision

The tick gate's scope is correct. `--owed` stays CORE-only; docs and skills stay manifest-protected
and are `[manual]`'s job. What is wrong is that nothing says so: the usage header does not list
`--owed` or `--unlisted` at all, and the tick guard's header lists the two families without naming
what it deliberately leaves out. So a reader who gets "nothing owed" concludes "nothing differs".

## Functional requirements

- **FR-01** The usage header of `template-autosync.sh` documents `--owed` and `--unlisted` with
  their exit codes and states that docs and skills are outside `--owed` and reported by `[manual]`.
- **FR-02** `core-owed-tick-guard-hook.sh`'s "what counts as owed" names the excluded family and why
  (measured precision), so the next reader does not refile this row.
- **FR-03** A regression test pins the boundary: a committed local edit to a shipped doc and to a
  shipped skill → `--owed` exits 1 (none) and a syncing run's `[manual]` block names both.
- **FR-04** No behaviour change. CORE membership, overwrite semantics, `[manual]` wording unchanged.

## Acceptance

- AC-13 in `scripts/test-template-autosync-owed.sh` passes, and fails if either path is moved into
  `core_divergence`'s candidate set or dropped from `[manual]`.
- The existing 12 ACs still pass.

## Clarifications

### Session 2026-09-29

- Q: Gate or report? → A: Report; already reported. Measured 0 of 4 purely owed (see above).
- Q: Widen CORE to docs/skills? → A: No. It would change overwrite semantics for two directories and
  destroy the four projects' local content on the next sync.
- Q: Add a machine-readable `--local-only` query? → A: No consumer asks for one (YAGNI). `[manual]`
  is the reader-facing answer.
