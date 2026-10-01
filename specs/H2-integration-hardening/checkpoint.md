# H2 — integration-hardening checkpoint (template repo)

Second checkpoint. It covers the rows ticked since H1 (commit 9c8dc8a, 2026-09-30): 043–079, about
30 of them, almost all closed on the same day. `checkpoint-cadence.sh` counted 33 feature specs
past H1.

## 1. Full-system regression

All 67 `scripts/test-*.sh`, run one at a time under bash.

- First run: 63/67. Each of the four reds came from a row ticked since H1, and none was caught when
  that row was ticked:
  - `test-core-gates.sh`: the doc self-tests that 071 and 072 added (`test-doc-*.sh`) match the gate
    shape but were missing from `NON_GATES`. Both are now listed as template-only.
  - `test-hook-channels.sh`: the emit scan globs `scripts/*-hook.sh`, so it picked up
    `test-allium-check-hook.sh` (050). That file reads payloads and emits none. Test files are now
    skipped.
  - `test-runtime-markers-ignored.sh`: 051's `.claude/.suite-command` had no bucket. It is a
    project decision, so it is classified as tracked by design.
  - `test-validate-scenario-traceability.sh` case40a: `checkpoint-cadence.sh` (068) cited
    `SC-1444` in a comment. This was already recorded as F057 and is now resolved.
- After the fixes: 68/68, including the new `test-harness-state-gc.sh` (596 s in total).

## 2. Cross-cutting security sweep

- `project-freshness.sh`: no verified credentials, and no key material except 3 allowed hits.
  osv-scanner is not installed, and the template has no lockfiles, so nothing went unscanned.
- `security-scanner`, in adversarial mode: 11 confirmed findings. Four were fixed in place, each
  with arms that fail against the old code:
  - trufflehog's plain printer writes `Raw result:
    <credential>`, and that output reaches maintenance reports, the nightly log and the
    transcript. freshness now asks for `--json` and prints only the detector, file, line and
    commit.
  - `harness-state-gc.sh` read `find` output line by line, so a
    marker named `x<LF>victim` made it delete `./victim`. The same name with `.git` works too.
    Reproduced, then fixed with `-print0`. New test: `test-harness-state-gc.sh` (CORE).
  - The nightly installer matched its marker as a substring, so installing or
    removing `/repos/app` also dropped `/repos/app-admin`. It also treated a failed `crontab -l`
    as an empty crontab and overwrote the developer's jobs. It now matches the marker at the end
    of the line, and refuses unless the error is "no crontab".
  - `core-owed-tick-guard-hook.sh` emitted its override notice
    without `hookEventName`, which is the F055 defect class.
- Recorded as F062–F070: the unattended nightly runs repo-owned command strings; `lane-catchup
  --apply` strips the `~/.ssh` and `~/.aws` deny rules; the worktree pruner misses detached HEADs;
  `maintenance_ledger --all` runs sibling repos' scripts; `update-template.sh` gives a headless
  session web and Bash access together; Stryker glob backtracking has no timeout on the nightly
  path; nightly log and PATH files are keyed by basename; `detect-verify-command.sh` quoting; and
  `tlc-cleanup` scope is machine-wide.
- The fix for row 069 (`tlc-cleanup.sh`) was verified and holds.

## 3. Scenario-map reconciliation

Not applicable. The template has no language marker and no `specs/SCENARIOS.md`, the same as at H1.

## 4. Mutation spot-check

Stryker has no bash target, so this is the H1 method again: a sampled operator-mutation pass,
stratified by operator, 12 mutants per module, seed 2. It ran in a detached worktree under
`$HOME`, with each module's tests. It covered the three most-changed modules since H1.

| Module | Commits since H1 | Killed | Finding |
|---|---|---|---|
| `template-autosync.sh` | 9 | 3/12 (25%) | F071 |
| `project-maintenance.sh` | 7 | 7/12 (58%, unchanged since H1) | F072 |
| `validate-scenario-traceability.sh` | 4 | 11/12, 1 timeout | F073 |

- `template-autosync.sh`: row 078 armed the 10 mutants H1 left alive. A fresh sample shows
  that fixed the sample and not the file (530 operator sites). Among the survivors are two exit
  codes on the template-discovery path and the claimed-vs-parsed count check.
- The timeout: changing `--help`'s `exit 0` to `exit 1` makes the traceability self-test hang
  for the full 600 s instead of failing. A timeout is not a kill.
- The first launch went through zsh, and `$M` did not word-split, so
  nothing ran. Same trap as H1, caught before any number was read.

## Carve budget

The freeze is on, so no rows were added apart from this checkpoint (exempt). F057 was resolved,
and F062–F073 were recorded. 65 findings are open, so the batch review is due.
