# Acceptance cases — 085-template-mutation-runner-and-core-coverage

**Confirmed:** 2026-10-01 · 66b87d0361fe — "Confirmed as written"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`085-AC-<n>`.

## AC-1 — The template measures its own mutation gate
**Given** the template repository with `scripts/run-mutation-gate.sh` and every module self-test green
**When** `bash scripts/project-maintenance.sh --full` runs
**Then** the report carries a `[MUTATION]` line with a number or no mutation finding at all, the ledger records a `mutation` run, and `maintenance-due.sh` no longer lists the mutation job as never run

## AC-2 — A timeout is not a kill, and a red baseline is not a score
**Given** a module whose self-test sleeps past its limit against one mutant, and separately a module whose self-test is red unmutated
**When** the runner measures each
**Then** the first mutant is reported `timeout` and counted as survived, and the second run prints no `mutation score` line and exits 2 naming the red test

## AC-3 — Every recorded survivor is killed or proven equivalent
**Given** the sites named by F048, F049, F071 and F072 at their current lines
**When** `run-mutation-gate.sh --lines` re-measures them
**Then** every non-equivalent mutant on them is killed, and each remaining one carries a `# mutant-equivalent:` reason that the spec repeats

## AC-4 — The runner leaves nothing behind
**Given** a run that finishes, one that fails its baseline, and one interrupted with SIGINT
**When** each ends
**Then** no worktree of the run remains in `git worktree list`, its run directory is gone, and the real index and HEAD are unchanged

## AC-5 — Readiness needs a heavy-job measurement
**Given** a ledger that spans five ticked specs with `secrets` and `similarity` runs but no `mutation` or `suite` run
**When** `maintenance_ledger.py report` runs
**Then** it says `keep measuring — no run of: mutation, suite` and never `ready for 075`
