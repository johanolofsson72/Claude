# Spec interview — 042-needs-clause-swallows-a-null-dependency

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no auth, PII, upload, new external surface, state machine or entity. The change is read-only reporting in one script.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: `runnable()` and the report in `scripts/lane_status.py`, plus cases in `scripts/test-lane-orientation.sh`. Out: `validate-register-ids.sh`, the row format, the `NEEDS` regex.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer on a multi-lane project asking "what can I start", and anyone running `lane-status.sh` on a register that writes "no dependency" in words.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** agentcrm's shape (`needs inget` on rows whose real dependencies are ticked) lists every runnable row, and the unresolved entries are named once.

## Q4 — Word list or resolution?
**Q:** Skip known null words, or decide some other way?
**A (auto):** By shape: an entry with no digit is prose. Every row id format has a digit and no word for "nothing" does, so it holds in every language without a list.

## Q5 — Unresolved entry: block or free?
**Q:** Does an id-shaped entry that names no row block the row?
**A (auto):** Yes. agentcrm's register documents that policy on purpose (a typo must never make a row look free), and the digit test already frees the prose case that was the bug. Deviation from the diagnosis, which proposed freeing it.

## Q6 — Typo safety
**Q:** How does `needs 04` (meant 004) surface?
**A (auto):** The row stays held and the entry is printed on a `needs names no row, held until fixed` line, so the hold says why.

## Q7 — Held rows
**Q:** Is a `- [!]` row a known id for resolution?
**A (auto):** Yes. It is in the register and not ticked, so it blocks.

## Q8 — In-progress rows
**Q:** Is a `- [/]` row a known id?
**A (auto):** Yes, and it blocks until ticked, unchanged from today.

## Q9 — Mixed clause
**Q:** `needs 011, inget` with 011 open?
**A (auto):** Withheld on 011; `inget` still reported. Resolution is per entry.

## Q10 — Where the report shows
**Q:** Brief, full report, or both?
**A (auto):** Both, gated like the runnable list (full, or multi-lane brief). The single-lane brief stays silent.

## Q11 — Which rows get the report
**Q:** Report unresolved entries on ticked rows too?
**A (auto):** Only open rows (`[ ]`, `[/]`, `[!]`). A ticked row's `needs` no longer decides anything, and printing it would add noise to every session.

## Q12 — Owned rows
**Q:** Report unresolved entries on rows owned by another lane?
**A (auto):** Yes. The typo is a register defect whoever owns the row; the line is one line.

## Q13 — Output format
**Q:** What does the line look like?
**A (auto):** `  needs names no row, held until fixed: 036 → 04; 038 → R9` — one line, like `no Blocks line`. Prose entries never appear on it.

## Q14 — Empty state
**Q:** No unresolved entries?
**A (auto):** No line at all. Absence is the clean state; the known-positive test (case 7b) proves the line can appear.

## Q15 — Error semantics
**Q:** Can this raise?
**A (auto):** No new failure modes; it is set membership over parsed rows.

## Q16 — Deleted rows
**Q:** `needs` names a row that was deleted from the register?
**A (auto):** Blocks and is reported. The reader decides whether the citation or the deletion was wrong.

## Q17 — Performance
**Q:** Any limits?
**A (auto):** None relevant; registers are under a few hundred rows.

## Q18 — Acceptance tests
**Q:** What proves it?
**A (auto):** Known positives for `inget`/`nothing`/`none`, a real open dependency still blocking, a ticked one satisfied, a mixed clause, a typo reported, single-lane silence intact. Hand mutants on the new branch must die.

## Q19 — Reversibility
**Q:** Rollback?
**A (auto):** Revert the commit. No data or format change.

## Q20 — Non-goals
**Q:** Anything deliberately left?
**A (auto):** Validating `needs` citations in `validate-register-ids.sh` goes to FINDINGS, not this row (freeze on).
