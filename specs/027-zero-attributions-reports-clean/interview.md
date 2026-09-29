# Spec interview — 027-zero-attributions-reports-clean

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no hardened trigger fires (no auth/PII/upload/new surface, no state machine, 3 files of code).

## Q1 — Scope boundary
**Q:** Only the zero-attribution verdict, or also a "thin attribution" heuristic?
**A (auto):** Only zero. A thin-attribution heuristic has no measurement behind it, so it becomes a finding.

## Q2 — Primary actor
**Q:** Who is hurt?
**A (auto):** The developer who reads maintenance output and treats silence as a green light. On agentcrm the depth-3 chain had to be traced by hand.

## Q3 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** On the template's own register, `--carves` exits 3 with "unmeasurable", and the maintenance pass lists it.

## Q4 — Threshold input
**Q:** What separates a young register from one that doesn't attribute: row count or ticked count?
**A (auto):** Ticked count. A wizard plans rows up front, so a row count says nothing about how much work has been done.

## Q5 — Threshold value
**Q:** Which number?
**A (auto):** 10 ticked. It is §5's floor for the carve ratio and follows the same logic. Measured: 17 of 18 zero-attribution registers are above it.

## Q6 — Exit code
**Q:** Which exit code for unmeasurable?
**A (auto):** 3. Exit 1 means "exceeded" to project-maintenance, and 4 is already "could not run". In register-convergence.sh, 3 means "not enough to tell".

## Q7 — Young register
**Q:** What does a young register with zero attributions print?
**A (auto):** A line that says it is too young to measure, with exit 0. It must not say "clean".

## Q8 — Unresolved-only
**Q:** Zero resolved but some unresolved attributions, ≥ 10 ticked?
**A (auto):** Unmeasurable (exit 3), with the unresolved list above it. The line counts them.

## Q9 — Error semantics
**Q:** What happens when the audit cannot run (no python3, no engine)?
**A (auto):** project-maintenance reports "could not run" with the exit code. Today any code other than 1 is dropped without a word.

## Q10 — Four states
**Q:** Success, error, empty and loading for a CLI report?
**A (auto):** Success is clean or a verdict. Error is "could not run" with the exit code. Empty is "no register" (exit 4), or "too young" when the register has no attributions yet. Loading does not apply to a synchronous report.

## Q11 — Integration points
**Q:** Which callers read the exit code or the output?
**A (auto):** project-maintenance.sh branches on rc. lane-catchup.sh greps `^carve shape`, and the new lines start that way, so it needs no change.

## Q12 — Fatal or reported
**Q:** Can unmeasurable fail a build?
**A (auto):** No. §4b: reported, never fails a build. The maintenance script's own exit stays unchanged.

## Q13 — Wording
**Q:** What should the unmeasurable line tell the reader to do?
**A (auto):** It should name the fix: write `carved by <id>` on the rows a spec carved. It should point to §4b.

## Q14 — Concurrency
**Q:** Any ordering or concurrency concern?
**A (auto):** None. It is a read-only report over one file.

## Q15 — Non-functional
**Q:** Performance limits?
**A (auto):** Unchanged. Counting ticked rows reuses the loop that already exists.

## Q16 — Acceptance criteria
**Q:** What pins it?
**A (auto):** Five arms in test-register-convergence.sh: clean, over budget, unmeasurable, young, and unresolved-only. Each one fails on the old engine.

## Q17 — Non-goals
**Q:** What is explicitly out?
**A (auto):** Backfilling attributions in downstream registers (each project's own work) and changing the regex.

## Q18 — Reversibility
**Q:** Rollback story?
**A (auto):** One revert. No state is written.

## Q19 — Downstream impact
**Q:** After sync, 17 projects get a new maintenance finding. Is that noise?
**A (auto):** No. It is the finding §4b already describes. Findings are reported, never fatal, so no build turns red.

## Q20 — Rule text
**Q:** Does carve-budget.md change?
**A (auto):** Yes, one sentence in §4b that names the verdict and the exit code. The rule already holds the reasoning.
