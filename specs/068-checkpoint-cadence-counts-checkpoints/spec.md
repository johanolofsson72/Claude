# 068 — checkpoint-cadence-counts-checkpoints

Track: spec-only. No entity, no state machine, no new external surface. Touches
`scripts/spec-register-orientation-hook.sh`, `scripts/project-maintenance.sh`, one new engine
(`scripts/checkpoint-cadence.sh`) with its harness, the CORE list in `scripts/template-autosync.sh`
and the count definition in `.claude/rules/spec-hardening.md`. No hardening trigger.

Evidence: fundit F211 (2026-09-24). Diagnosis in `specs/INDEX.pending.md`.

## The defect

Both readers of the every-5 checkpoint cadence compute `DONE % 5` over every `- [x]` row. That
counts checkpoint rows (H1, H2) and carved rows (016a, `carved by …`) as feature specs, so fundit
was told "checkpoint due" at 20 done when four feature specs had been ticked since H2. The modulo
has a second failure in the other direction: at 21 done the alarm goes silent although the
checkpoint was never worked. A register that skipped a multiple of 5 never hears about it again.

## Requirements

- **FR-01** One engine, `scripts/checkpoint-cadence.sh`, answers "how many feature specs have been
  ticked since the last ticked checkpoint row". Both readers call it; neither recomputes.
- **FR-02** A ticked row counts when it is not a checkpoint row, not a carved row and not a
  standing row. Checkpoint: id starts with `H` followed by a digit, or its track field (field 3)
  reads `checkpoint`. Carved: id is digits followed by a letter suffix (`016a`, `002ab`), or the
  row carries `carved by <id>`. Standing: track field `standing` / `stående`.
- **FR-03** "Since" is file order: rows below the last ticked checkpoint row. With no ticked
  checkpoint row, every counted row since the top of `## Specs`.
- **FR-04** Due when the count is ≥ 5 (not when it is a multiple of 5), so a skipped checkpoint
  keeps being reported until one is worked.
- **FR-05** The orientation banner keeps its current suppression (next row is already a
  checkpoint → silent) and names the count as feature specs since the last checkpoint, with that
  checkpoint's id.
- **FR-06** `project-maintenance.sh` keeps its "no pending checkpoint row" condition and uses the
  engine's count.
- **FR-07** Engine output is one machine line `since=<id|none> count=<N> due=<0|1>`; exit 0 due,
  1 not due, 4 no register. An unreadable register is never "not due" silently.

## Acceptance

- AC1 fundit's shape: H2 ticked, then 4 features + 1 carved row + 1 `NNNa` row ticked → count 4,
  not due; the orientation hook prints no checkpoint alarm.
- AC2 5 features since H1 → due; the hook prints the alarm naming `5 feature specs since H1`.
- AC3 7 features since H1 (skipped multiple) → still due.
- AC4 no checkpoint ever, 5 features + a standing T0 → due, `since=none`.
- AC5 next row is an H row → no alarm even when due.
- AC6 project-maintenance reports `[HARDENING]` for AC2's register and not for AC1's.
- AC7 no register → exit 4.
- AC8 sabotage: counting H rows, counting carved rows, or reverting to modulo turns a case red.

## Clarifications

### Session 2026-09-30

- Q: Does a carved row count toward the five? → A: No. The diagnosis and the register's own
  precedent count feature specs; a carved row is follow-up work of a spec already counted.
- Q: File order or git-tick order for "since"? → A: File order. Registers are ordered and an H row
  is placed after the specs it covers; git history would make a SessionStart hook walk commits for
  a banner. A tail row worked early still sits below the H row it follows in time only if it was
  appended after it, which is the common case.
- Q: Keep the multiple-of-5 test? → A: No, ≥ 5 since the last checkpoint. The modulo is what made
  a skipped checkpoint disappear at 6.
- Q: Make N configurable? → A: Not now. No project has recorded a different N; the constant lives
  in the one engine, so changing it later is one line.
