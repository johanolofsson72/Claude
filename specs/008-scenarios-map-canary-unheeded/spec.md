# 008 — scenarios-map canary unheeded

Track: spec-only. No entity, no state machine, no external surface. Five files of shell and rule
prose (`project-maintenance.sh`, `spec-register-orientation-hook.sh`, `scenarios.md` and two self-tests)
plus register bookkeeping. That is under the six-file hardening trigger, and none of the risk domains apply.

## Problem

The context-cost canary has measured scenario maps since 007bl, and it fires. Almost nobody acts on it.
Measured 2026-09-29 across every project under `~/repos` that has a map: **17 files over 25 KB in 17
projects**. They range from puck (439 KB, single file) and noisycricket-joucbox (145 KB) down to rocky
(54 KB split index) and consultpilot (43 KB, one feature file). The template row named four of them.

There are two reasons the canary goes unheeded, and both are in the template:

1. **Its advice is wrong for a map.** Both canary sites print one remedy list for every file they
   name. `archive-completed-rows.sh` works on `INDEX.md`. `archive-spec-history.sh` trims a history
   section. Neither one moves a single SC row. A developer who follows the advice on a 121 KB map
   gets back a few hundred bytes and the same warning.
2. **A warning is not a record.** The orientation banner prints and scrolls away. Nothing puts the
   oversize map in front of a decision. The template's answer so far has been this row, which lists
   instances from outside the project. It went stale twice: film-i-vast was missed, and then puck,
   iskvalp, teach and ten more were missed. The fix has to live in the project that owns the map, not
   in a list kept elsewhere.

## Requirements

- R1 When `project-maintenance.sh` finds a scenario-map file (`specs/SCENARIOS.md` or
  `specs/scenarios/*.md`) over 25 KB, the hint names a remedy that shrinks that file:
  - single-file map: split it per `.claude/rules/scenarios.md` "When to split", and prove the move with
    `scripts/scenario-map-rows.sh` + `scripts/test-scenario-map-split.sh`;
  - split index: the index keeps one row per feature and its history is archived
    (`archive-spec-history.sh`), so trim the history and any retired-feature prose;
  - feature file: split that feature into sub-feature files, or archive its history.
  The `INDEX.md` hint is unchanged.
- R2 For each scenario-map file over the canary, `project-maintenance.sh` records a finding in the
  project's own `specs/FINDINGS.md` through `scripts/finding.sh --add --kind debt`. The text starts
  with the stable key `scenario-map canary: <path> ` and carries the size and the R1 remedy.
- R3 Recording is idempotent: when an **open** finding already carries the key for that path, nothing
  is added. A decided finding does not suppress a new one. If the map is still over at the next pass,
  it is back in front of the next review.
- R4 When `scripts/finding.sh` is missing, the pass reports `[SETUP]`, saying that the canary could not
  be recorded. It never skips silently.
- R5 The SessionStart canary keeps naming every file. When a scenario-map file is among them, it adds a
  line saying that the archivers do not shrink a map, pointing at "Keep the map lean", and saying that
  `project-maintenance.sh` records it in `specs/FINDINGS.md`.
- R6 `.claude/rules/scenarios.md` says that the canary records a finding for each file and that the
  5-spec review decides it.
- R7 Row 008 stops enumerating projects. `INDEX.pending.md` carries the 2026-09-29 measurement as
  evidence, and says that each project's own maintenance pass now owns the per-project work.

## Out of scope

- Splitting any project's map. That is per-project work with its own spec, and R2 hands it to each
  project.
- `INDEX.md` over the canary. That is row 017.
- A SessionStart hook writing to git-tracked files. The hook reports, and the maintenance pass records.

## Acceptance

- A1 Fixture with a single-file map over 25 KB → the maintenance output carries the split hint, and
  FINDINGS.md gains one `scenario-map canary: specs/SCENARIOS.md ` line of kind debt.
- A2 A second run → still one open line for that path.
- A3 An over-size feature file under the split layout → a finding naming `specs/scenarios/<f>.md`
  with the feature-file hint.
- A4 A map under 25 KB → no finding, and FINDINGS.md is not created.
- A5 The only matching finding is decided → a new open one is added.
- A6 `finding.sh` absent → a `[SETUP]` line, and the verdict is red.
- A7 Orientation hook with an oversize map → the scenario-map remedy line appears. With only INDEX.md
  oversize → it does not.
- A8 The existing canary and maintenance suites stay green.

## Clarifications

### Session 2026-09-29

- Q: Should the SessionStart hook record the finding itself? → A: No. It runs every session and
  would dirty the tree. The maintenance pass is the recurring job, and the hook points at it.
- Q: Should a decided finding suppress re-recording? → A: No, only an open one does. A decision to
  live with an oversize map is taken again at every review for as long as it is oversize, and that
  review happens only every 5 specs.
- Q: Kind? → A: `debt`. It costs context on every spec and breaks nothing.
