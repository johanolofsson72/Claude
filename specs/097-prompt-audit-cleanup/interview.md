# Spec interview — 097-prompt-audit-cleanup

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: not large/advanced (spec-only, text). No overflow.

## Q1 — Scope boundary
**Q:** All prompt files, or the five areas the row names?
**A (auto):** The five areas (A1–A8 in spec.md). A wider emphasis sweep of `.claude/rules/` is out.

## Q2 — Primary actor and trigger
**Q:** Who is affected?
**A (auto):** Claude in this template and in every project the wizard bootstraps or autosync updates.

## Q3 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** Each finding fixed in place; SC-A greps come back empty; the budget and the suite hold.

## Q4 — Data model
**Q:** Any data touched?
**A (auto):** None. Markdown only.

## Q5 — Validation rules
**Q:** Which side wins a contradiction?
**A (auto):** The side a hook or a BLOCKING rule enforces (R5): 3 attempts, the pipeline for 2+ files, the AUTO interview.

## Q6 — The four states
**Q:** Error, empty, loading?
**A (auto):** N/A: no runtime surface. The suite's doc tests are the check.

## Q7 — Error semantics
**Q:** What if a fix breaks a doc-citation test?
**A (auto):** Fix the citation in the same change; never weaken the test.

## Q8 — Authorization
**Q:** Any guarded file?
**A (auto):** No settings file is touched; `language` already says `english`.

## Q9 — Concurrency
**Q:** Two lanes?
**A (auto):** Single lane. N/A.

## Q10 — Integration points
**Q:** What reads these files?
**A (auto):** Every session (CLAUDE.md, rules), the wizard on a new project, autosync to projects (rules and CLAUDE.md core sections).

## Q11 — Edge cases
**Q:** The wizard's other copies?
**A (auto):** Untouched (skill lineage divergence memory); only the template's copy.

## Q12 — Non-functional limits
**Q:** Size?
**A (auto):** CLAUDE.md stays under the 40 KB always-loaded cap; the edits shorten more than they add.

## Q13 — Acceptance criteria
**Q:** Measurable done?
**A (auto):** SC-A greps empty, `context-budget.sh` within budget, full suite green.

## Q14 — Non-goals
**Q:** Rewording rules for style?
**A (auto):** No. Only contradictions, stale references and the wizard's shouting.

## Q15 — Reversibility
**Q:** Undo?
**A (auto):** Revert the commit.
