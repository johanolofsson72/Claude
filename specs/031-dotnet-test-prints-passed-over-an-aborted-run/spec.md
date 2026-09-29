# 031 — dotnet test prints Passed! over an aborted run

Track: spec-only. No entity, no state machine, no new surface. Not hardened: one sourced helper
and three call sites that already judge a run.

Evidence: rocky 2026-09-05, finding F006 from checkpoint H13 (`specs/INDEX.pending.md` § 031).

## Problem as filed

The integration test host crashed, and the block that `dotnet test` printed read, in this order:

```
The active test run was aborted. Reason: Test host process crashed
Passed!  - Failed: 0, Passed: 1673, Skipped: 7, Total: 1680
Test Run Aborted.
```

The suite is 3050 tests, so 45% of it never ran, and the summary word was `Passed!`. Nothing in the
template reads the abort line.

## What was measured (2026-09-29)

Three places in the template judge a test run from its output. Each one was fed the captured
transcript above:

| Call site | Reads | On the aborted transcript |
|---|---|---|
| `repeat-failure-guard-hook.sh` | text only; the payload has no exit code | `Passed! *-` matches, so the verdict is **passed** and a live failure counter is **reset** |
| `project-maintenance.sh --suite` | `$?` only | red on rocky's exit 1; would stamp the suite green on any abort that exits 0 |
| `template-sync-verify.sh` | `$?`, then the evidence pattern `Passed!` for derived commands | same as above: on exit 0 the evidence gate is satisfied by the `Passed!` line |

The row names `scripts/e2e-wait-audit.sh` as a starting point. It is project-side (rocky) and not
in the template, so this spec does not touch it. It is recorded as a note for rocky.

## Decision

One sourced helper, `scripts/run-verdict.sh`, owns the abort pattern. It follows the same pattern
as `hook-verdict.sh` (spec 029).

- `run_aborted "$OUT"` returns 0 when the output carries an abort line.
- `run_verdict "$RC" "$OUT"` prints `aborted`, `failed` or `passed`. An abort wins over both the
  exit code and the summary word. A non-zero exit code is `failed`. Exit 0 with a failure summary is
  also `failed`, because `dotnet test` exiting 0 on failures has already been measured.

The abort pattern, case-insensitive: `test run (was )?aborted` or `summary: aborted`. The first
covers both vstest lines (`The active test run was aborted.` and `Test Run Aborted.`). The second
covers the Microsoft.Testing.Platform summary.

## Functional requirements

- **FR-01** `scripts/run-verdict.sh` defines `run_aborted` and `run_verdict` as specified above,
  and has no side effects when sourced.
- **FR-02** `repeat-failure-guard-hook.sh` classifies an aborted run as **failed** before any
  success pattern is tried. The rocky transcript counts up instead of resetting.
- **FR-03** `project-maintenance.sh --suite` takes its verdict from `run_verdict`. An aborted run is
  a `[SUITE]` finding that says the run aborted and how many tests the partial summary claims.
  It is not stamped, even when the exit code is 0.
- **FR-04** `template-sync-verify.sh` refuses to verify an aborted run: it does not write
  `verified`, and it keeps the obligation. This holds for declared and derived commands alike,
  because an abort is not a judgement about a command a human chose.
- **FR-05** `run-verdict.sh` is in `CORE_SCRIPTS`, next to `hook-verdict.sh`, and the parity test
  stays green.
- **FR-06** The tests prove the fix in both directions. A green `dotnet test` transcript stays
  passed. The captured abort transcript goes red at every call site. Each new red arm fails on HEAD.

## Acceptance

- `bash scripts/test-run-verdict.sh`, `bash scripts/test-pipeline-hooks.sh` and
  `bash scripts/test-project-maintenance.sh` pass.
- The new abort arms are red on HEAD before the fix.

## Clarifications

### Session 2026-09-29

- Q: Does e2e-wait-audit.sh belong in scope? → A: No. It is not in the template. The row's scope
  says "the two existing call sites", and the template has three that judge a run; all three
  are fixed.
- Q: Does an abort outrank exit 0 on a declared command in template-sync-verify? → A: Yes. The
  evidence gate is for derived commands only, because it judges the command. An abort judges the
  run, whoever chose the command.
- Q: Should the hook source the helper or copy the pattern? → A: Source it, via a sibling of
  `$0`, as `template-sync-verify.sh` already does for the detector. One copy of the pattern. The
  helper is CORE and ships in the same sync as the hook. A missing helper gives today's behaviour,
  not a crash, because the hook must never break a Bash call.
