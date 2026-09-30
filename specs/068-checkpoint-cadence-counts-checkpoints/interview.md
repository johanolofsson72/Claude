# Spec interview — 068-checkpoint-cadence-counts-checkpoints

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (two readers of one count, one new engine, no entity, no new surface), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: one cadence engine, both readers moved onto it, harness with sabotage arms, the rule's count definition. Out: inserting checkpoint rows automatically, a configurable N, walking git history for tick order.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A fresh session in a project whose register holds H or carved rows (fundit F211). It is told to work a checkpoint after four feature specs, or never told after a skipped multiple.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** The banner fires exactly when five or more feature specs sit ticked below the last ticked checkpoint, and says so with the count and the checkpoint id.

## Q4 — What is a checkpoint row
**Q:** How is a checkpoint row recognised?
**A (auto):** Id `H<digit>…`, or track field `checkpoint`. Both, because the template's own rows use both and a slug must not decide it (the SC-1444 lesson).

## Q5 — What is a carved row
**Q:** How is a carved row recognised?
**A (auto):** A letter-suffixed numeric id (`016a`) or `carved by <id>` on the row. Only the canonical phrase; `from` is too common in goals ("From fundit F211").

## Q6 — Standing rows
**Q:** Does the standing T0 row count?
**A (auto):** No. It is a pointer, not work; the orientation hook already skips it for "next".

## Q7 — "Since" order
**Q:** File order or tick order?
**A (auto):** File order (see Clarifications).

## Q8 — Due condition
**Q:** Multiple of 5 or at least 5?
**A (auto):** At least 5. The modulo silences a skipped checkpoint at 6.

## Q9 — No checkpoint yet
**Q:** What if no checkpoint was ever ticked?
**A (auto):** Count from the top; `since=none`.

## Q10 — Pending checkpoint
**Q:** A checkpoint row exists but is not ticked?
**A (auto):** Unticked H rows do not reset the count. The orientation banner stays silent when the NEXT row is that checkpoint; project-maintenance stays silent while any checkpoint row is pending, as today.

## Q11 — Engine contract
**Q:** Output and exit codes?
**A (auto):** One line `since=… count=… due=…`; exit 0 due, 1 not due, 4 no/unreadable register.

## Q12 — Engine missing
**Q:** What does the orientation hook do if the engine is absent (truncated sync)?
**A (auto):** Fall back to printing nothing for the cadence, but only after the engine is on the CORE list so sync always ships it. A banner that guesses is what this spec removes.

## Q13 — Lanes
**Q:** Does SPEC_OWNER change the count?
**A (auto):** No. A checkpoint covers the whole system, both lanes' rows.

## Q14 — Portability
**Q:** Language for the engine?
**A (auto):** bash + awk, bash 3.2 and BSD/GNU awk safe, no python: the hook must work on Git Bash without python3.

## Q15 — Error semantics
**Q:** What happens on a malformed row?
**A (auto):** It is not a `- [x]` row by the anchored pattern, so it is not counted; no crash.

## Q16 — Acceptance
**Q:** How is it proven?
**A (auto):** A harness with fixture registers for AC1–AC7 plus sabotage arms that re-introduce each of the three old behaviours and must turn a case red.

## Q17 — Reversibility
**Q:** Rollback story?
**A (auto):** Revert the commit; no state is written anywhere.
