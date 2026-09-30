# 043 — mutation-gate-reports-a-headline-only

Track: spec-only. No entity, no state machine, no new external surface. One CORE script section and
its test change. Not hardened.

Evidence: fundit spec 006. The headline read 88.21% and PASS while `PushEndpointPolicy`, the SSRF
decision, killed 65.79%. Diagnosis on the register row.

## The defect, as measured on 2026-09-30

The row blames `run-mutation-gate.sh` passing `--reporter progress`. That half has moved on. Neither
runner that exists (fundit, rocky) passes a CLI reporter any more, and every Stryker config in both
lists `"json"`. The runner is project-local by design (settled by 045/F041), so the template has no
runner to fix anyway.

The half that still stands is in CORE. `.claude/rules/spec-hardening.md` gates on the changed
critical **module**. `scripts/project-maintenance.sh` section 5 reads one number, the last
`mutation score` line, and compares it with the break. A run at 88% passes without a word while one
module sits at 65%. And a run that wrote no JSON report at all, which is Stryker's default reporter
list, reads exactly like a run whose modules were all checked. Trap 4 of
`.claude/rules/mutation-timeouts.md`: an unmeasured state and a clean state must never render
identically.

## Decision

After a mutation run in `--full`, section 5 reads the Stryker JSON reports **this run wrote**: every
`mutation-report.json` (Stryker.NET) or `mutation.json` (StrykerJS) newer than a marker touched just
before the run. Stale reports from earlier runs are ignored.

- Per file, the score is Stryker's own: `(Killed + Timeout) / (Killed + Timeout + Survived +
  NoCoverage)`. The label says so, as the headline's does.
- Several reports from one run (fundit runs two passes, rocky one per module) are merged **per
  mutant**, keyed by file, mutator, replacement and location. A mutant detected in any report counts
  as detected, because the suite kills it.
- Every file with at least one valid mutant and a score under the limit is listed, lowest first,
  with its detected/valid counts. The limit is the same one the headline uses (the config's
  `thresholds.break`, else 80).
- A headline that passes with modules under the limit is a finding. A headline that fails carries the
  list inside the existing GATE FAILED finding.
- A run that produced a score but no report is a finding: the per-module gate is unmeasured. The
  message names the fix: list `"json"` in the config's `reporters`, and note that a CLI `--reporter`
  replaces that list rather than adding to it.
- The due-state stamp is unchanged. A score came back, so the headline was measured (F044); the
  finding carries the module gap.

## Out of scope

- The project-local runners. fundit and rocky already keep the json reporter; they get the fix on
  the next sync because the reading happens in CORE.
- A strict scorer (Killed / valid). Same position as 041.
- Invalid mutate globs (row 047) and `.stryker-tmp` litter (row 053).

## Functional requirements

- FR-01 A passing headline with a file under the limit in this run's report produces a `[MUTATION]`
  finding naming the file, its score and its counts.
- FR-02 No file under the limit produces no module finding.
- FR-03 A scored run with no report written by it produces a finding that names `"json"` and
  `reporters`.
- FR-04 A report older than the run is ignored.
- FR-05 Reports from one run merge per mutant; a mutant detected in any report is detected.
- FR-06 A failing headline lists the modules under the limit in the GATE FAILED finding.
- FR-07 A file whose mutants are all CompileError/Ignored is not listed (no valid mutants).
- FR-08 Existing arms C14–C16 and C28–C30 keep their verdicts.
- FR-09 The runner output contract comment in section 5 states the report half of the contract.

## Clarifications

### Session 2026-09-30

- Q: Key the merge per file (best score) or per mutant? → A: Per mutant. Best-of-files would call a
  file clean when two passes each killed different halves; per mutant is what the suite actually
  kills.
- Q: Is a missing report a finding or a note? → A: A finding. The module gate is the rule's gate;
  leaving it unmeasured without turning the run red is the trap-4 shape.
- Q: python3 missing? → A: A finding that says per-module scores could not be read, never silence.
