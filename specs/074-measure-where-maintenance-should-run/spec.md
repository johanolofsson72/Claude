# 074 — measure where maintenance should run

Track: spec-only (harness instrumentation; no new entity, no state machine).
Requested by the developer 2026-09-29. Companion row 075 makes the placement decision.

## Problem

The developer wants heavy jobs that do not need the local setup (Stryker, full suites) to run in
Claude cloud, so they stop loading the Mac and David's Linux machine. Local work stays local. They
also want the need for maintenance and carving measured over at least five ordinary specs before
anything is placed.

Nothing measures that today. `maintenance-due.sh --stamp` records the date, the done count and the
row count for a job. It records no duration, no memory, and nothing about where the job ran. A
placement decision made now would be a guess.

The cloud target has hard numbers (code.claude.com/docs/en/cloud-environments, checked 2026-09-29).
A VM is Ubuntu 24.04 x86_64 with 4 vCPU, 16 GB RAM and 30 GB disk. There is no .NET SDK until a
setup script installs it. Sessions count against plan usage, and a routine's cron interval is at
least one hour. So peak memory and wall time per job are the numbers that decide placement: a suite
that peaks at 11.5 GB (agentcrm, 2026-09-01) sits close to the ceiling.

## Requirements

- R1 `project-maintenance.sh` runs each measured job through `scripts/maintenance_ledger.py run`.
  The measured jobs are secrets, traceability, similarity, mutation, suite and portability. Each run
  appends one line to `.claude/state/maintenance-runs.tsv`. The line holds the timestamp, place,
  job, seconds, exit code, peak RSS in MB, cores, the 1-minute load at start, and the ticked-spec
  count. The whole pass is also recorded as job `pass`.
- R2 place is `cloud` when `CLAUDE_CODE_REMOTE=true`, otherwise `local-<os>`.
- R3 The wrapper is transparent. The child's stdout/stderr and exit code pass through unchanged,
  and a ledger write that fails never changes the job's result. Without python3 the job runs
  unwrapped and the pass prints a note saying the run was not measured.
- R4 `maintenance_ledger.py report [--all]` summarises per job and place: runs, median and max
  seconds, max RSS, failures, and whether the job fits the cloud VM (max RSS under 12 GB of the
  16 GB). It also prints how many ticked specs the ledger spans against the 5 that 075 needs, and
  the register convergence line. With `--all` it reads every sibling repo's ledger. An empty ledger
  prints "no runs recorded", never zeros.
- R5 The new files are CORE (listed in `template-autosync.sh`), so product projects, where the heavy
  jobs actually are, start recording at their next session start.
- R6 `.claude/docs/workload-placement.md` records the developer's principle, the cloud facts, and
  how 075 reads the ledger. No rule changes until 075.

## Non-goals

Moving any job to the cloud (075). Cross-machine aggregation: each machine keeps its own ledger,
since cloud VM state does not persist and 075 decides how cloud numbers come back. Changing the
due thresholds.

## Acceptance

- `bash scripts/test-maintenance-ledger.sh` green: rc passthrough, output passthrough, line shape,
  cloud place, a ledger write failure is harmless, the empty report, aggregation, and spec span.
- `bash scripts/test-project-maintenance.sh` and `test-maintenance-due.sh` stay green.
- One real `project-maintenance.sh --full` on this Mac writes ledger lines, and `report` reads them.

## Clarifications

### Session 2026-09-29 (auto-picked)

- Q: Is `pass` recorded when the pass exits early on `--if-due` with nothing due? → A: No. Nothing ran, so there is nothing to measure.
- Q: Is the ledger read by `maintenance-due.sh`? → A: No. Due-ness stays in the stamp file; the ledger is evidence for 075 only.
