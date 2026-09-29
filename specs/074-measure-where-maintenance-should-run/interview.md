# Spec interview — 074-measure-where-maintenance-should-run

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with the recommended option; the direction itself was given by the
developer on 2026-09-29 and is recorded as a human answer). Not hardened: no trigger fires.

## Q1 — Scope boundary
**Q:** Does 074 move any job to the cloud?
**A:** No. Measure first over at least five ordinary specs, then place (075). Developer, 2026-09-29.

## Q2 — Scope boundary
**Q:** Which jobs are measured?
**A (auto):** The ones that cost time: secrets, traceability, similarity, mutation, suite and portability, plus the whole pass. The cheap greps are not measured.

## Q3 — Primary actor
**Q:** Who writes the ledger?
**A (auto):** `project-maintenance.sh`, whoever runs it: by hand, `--if-due`, cron or a cloud routine.

## Q4 — Data model
**Q:** What does a ledger line hold?
**A (auto):** A TSV line: ISO timestamp, place, job, seconds, rc, peak RSS in MB, cores, load1, ticked specs.

## Q5 — Data model (place)
**Q:** How is the cloud told apart from local?
**A (auto):** `CLAUDE_CODE_REMOTE=true` is what the docs give for cloud VMs. Otherwise the place is `local-<uname -s>` in lowercase.

## Q6 — Where it lives
**Q:** Tracked or machine-local?
**A (auto):** Machine-local, under `.claude/state/`, which is already gitignored. A tracked file with two machines appending to it would be a merge conflict on every run.

## Q7 — Error semantics
**Q:** What if the ledger cannot be written?
**A (auto):** The job's result is unchanged and the wrapper warns on stderr. A measurement must never turn a green pass red.

## Q8 — Error semantics (no python3)
**Q:** What if python3 is missing (for example, bare Git Bash)?
**A (auto):** The job runs unwrapped and the pass prints a note that it was not measured. The run itself still happens.

## Q9 — Peak memory
**Q:** How is peak memory measured portably?
**A (auto):** With `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss` after the child is reaped. It is KB on Linux and bytes on macOS. Blank when the module is absent (Windows).

## Q10 — Four states (report)
**Q:** What does the report say with no data?
**A (auto):** "no runs recorded", never a table of zeros. An unmeasured job and one that measured zero must not look the same.

## Q11 — Cloud-fit criterion
**Q:** When does a job "fit" the cloud VM?
**A (auto):** Max RSS under 12 GB, which leaves 4 GB of the documented 16 for the OS and the agent. Wall time is reported, not gated; 075 decides.

## Q12 — Five-spec counter
**Q:** How does the report know five specs have passed?
**A (auto):** Each line carries the ticked count. The span is the maximum minus the minimum over the ledger, shown as "N of 5".

## Q13 — Carving measurement
**Q:** How is carving measured?
**A (auto):** The report runs `register-convergence.sh --quiet` and prints its line. The carve ratio already exists; 074 does not duplicate it.

## Q14 — Integration points
**Q:** What else must change?
**A (auto):** The CORE_SCRIPTS list in `template-autosync.sh`, so products receive it. Nothing else reads the ledger.

## Q15 — Concurrency
**Q:** Two passes at once?
**A (auto):** A single `write()` of one line in append mode, well under PIPE_BUF. Lines never interleave within one machine.

## Q16 — Non-functional limits
**Q:** Does the ledger grow without bound?
**A (auto):** At one line per job per pass it reaches a few KB a month. The report reads it whole. No rotation until it matters.

## Q17 — Acceptance
**Q:** What proves it works?
**A (auto):** A self-test covering rc and output passthrough, line shape, cloud place, a harmless write failure, empty report, aggregation and span. Plus one real `--full` run on this Mac.

## Q18 — Reversibility
**Q:** How is it undone?
**A (auto):** Remove the wrapper calls. The ledger is disposable state.
