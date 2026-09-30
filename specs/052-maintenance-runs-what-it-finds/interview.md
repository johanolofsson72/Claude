# Spec interview — 052-maintenance-runs-what-it-finds

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger, so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: running `scripts/check-*.sh` in every pass, and refusing the bare dotnet fallbacks when
more than one solution exists. Out: checking the references inside a lone solution, a shipped `check-all.sh`.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer whose ratchets stopped running unnoticed, and one whose green project shows red
because the pass built a stale root solution (ighweld, 2026-09-18).

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** A plain `project-maintenance.sh` runs every ratchet and says nothing when they are green.
`--suite`/`--full` never build a solution the project did not choose.

## Q4 — Which ratchets
**Q:** Glob or declaration list?
**A (auto):** Glob `scripts/check-*.sh`. A list someone has to maintain is the same forgetting, one level up.

## Q5 — Opt-out
**Q:** Some ratchets need live infra or arguments (iskvalp `check-env.sh`). How are they excluded?
**A (auto):** `# maintenance: skip <reason>` in the first 30 lines. The reason is required and printed in a note, so a skip is never silent.

## Q6 — Marker without reason
**Q:** What happens to `# maintenance: skip` with nothing after it?
**A (auto):** The ratchet runs, and a note says the marker was ignored. Running is the safe default.

## Q7 — Timeout
**Q:** A ratchet that hangs?
**A (auto):** 300 s per ratchet via `timeout`/`gtimeout`, `MAINTENANCE_RATCHET_TIMEOUT` overrides. A timeout is a finding. With no binary: unbounded, noted once.

## Q8 — Four states
**Q:** Success / error / empty / loading?
**A (auto):** Green: silent. Red: `[RATCHET]` with exit code and output tail. Empty (no ratchets): no output. Timed out: a finding that says it timed out. There is no loading state in a batch script.

## Q9 — Invocation contract
**Q:** How is a ratchet called?
**A (auto):** `bash scripts/check-x.sh` from the repo root, no arguments, stdin from /dev/null. Exit 0 passes, anything else fails. That is the contract every surveyed ratchet already meets with its defaults.

## Q10 — Every pass or --full?
**Q:** When do ratchets run?
**A (auto):** Every pass. They are ratchets, meant to be cheap, and the timeout bounds the ones that are not.

## Q11 — Solution ambiguity threshold
**Q:** What counts as ambiguous?
**A (auto):** More than one `*.sln`/`*.slnx` at depth ≤ 3 outside `node_modules`. That is the same depth the existing detection uses, and the ighweld shape (root plus `src/welding/`) falls inside it.

## Q12 — Ambiguous: finding or note?
**Q:** Is the refusal red?
**A (auto):** Red (`[SUITE]` / `[MUTATION]`). The job was asked for and did not run. Staying due is what keeps it in front of the developer.

## Q13 — Declarations
**Q:** What unlocks the ambiguous case?
**A (auto):** `.claude/.suite-command` for the suite (051) and `scripts/run-mutation-gate.sh` for mutation (051's FR-06). No new file.

## Q14 — Error message
**Q:** What exactly does the refusal say?
**A (auto):** It lists every solution found, says the root one would be built blind, and names the declaration file to write.

## Q15 — Concurrency
**Q:** Parallel ratchets?
**A (auto):** Sequential. Ratchets can build (check-e2e-typecheck), and two builds in one tree race each other (row 047).

## Q16 — Stamping
**Q:** Does anything get stamped for ratchets?
**A (auto):** No due-state job. Ratchets run on every pass, so there is nothing to track. A refused suite or mutation run is never stamped.

## Q17 — Reversibility
**Q:** Rollback?
**A (auto):** Revert the commit. There is no state, and projects pick it up on the next autosync.

## Q18 — Acceptance
**Q:** Measurable done?
**A (auto):** AC1–AC10 as fixture cases in `test-project-maintenance.sh`, red on HEAD for the new arms, and the whole file green.
