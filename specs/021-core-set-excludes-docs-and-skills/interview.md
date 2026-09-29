# Spec interview — 021-core-set-excludes-docs-and-skills

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with the recommended option). No hardened trigger fires (three files,
no entity, no auth/PII/upload, no concurrency), so there are no overflow questions. The one question
that could have needed the developer (gate vs report) was settled by a fleet measurement.

## Q1 — Scope boundary
**Q:** Does this spec change which files the sync overwrites?
**A (auto):** No. CORE membership and overwrite semantics are untouched (FR-04).

## Q2 — Scope boundary
**Q:** Does it fix the four projects that carry a divergent doc today?
**A (auto):** No. Each is that project's merge or `--accept-local`, and `[manual]` already asks for it.

## Q3 — Primary actor
**Q:** Who reads the change?
**A (auto):** A developer or agent who queried `--owed` and needs to know what the answer excludes, and whoever maintains the tick guard.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** The usage header and the guard header both say docs/skills are outside `--owed` and point at `[manual]`, and a test proves it.

## Q5 — Data model
**Q:** Any change to the manifest, stamp or `.sync-local` format?
**A (auto):** None.

## Q6 — Validation
**Q:** What does the test reject?
**A (auto):** A doc or skill divergence appearing in `--owed`, `--owed` exiting other than 1 on such a project, and `[manual]` failing to name either path.

## Q7 — Four states
**Q:** Success / error / empty / loading?
**A (auto):** CLI only. Success = exit 1 + `[manual]` lines; error = exit 2 (unchanged); empty = silent; loading N/A.

## Q8 — Error semantics
**Q:** Does `--owed`'s exit-code contract change?
**A (auto):** No. 0 findings, 1 none, 2 cannot answer — now documented in the header.

## Q9 — Authorization
**Q:** Any authorization surface?
**A (auto):** N/A — local script, no actors.

## Q10 — Concurrency
**Q:** Ordering or concurrency concerns?
**A (auto):** None; documentation plus a hermetic test in its own temp dir.

## Q11 — Integration points
**Q:** Which consumers of `--owed` exist?
**A (auto):** `core-owed-tick-guard-hook.sh` only. It keeps its current behaviour.

## Q12 — Edge case: accepted local difference
**Q:** Is a doc recorded with `--accept-local` in scope?
**A (auto):** No. It is INTENTIONAL and silent by design (007af); the test covers the unrecorded case.

## Q13 — Edge case: skill added after the project
**Q:** A skill the template adds later, which the project never had?
**A (auto):** Added, not divergent; out of scope.

## Q14 — Non-functional
**Q:** Any cost on the session-start path?
**A (auto):** Zero. No code on that path changes.

## Q15 — Acceptance
**Q:** Measurable definition of done?
**A (auto):** AC-13 passes, AC-01..12 still pass, and a mutation that adds `.claude/docs/` to `core_divergence`'s candidate set makes AC-13 fail.

## Q16 — Non-goals
**Q:** Add a `--local-only` machine-readable query?
**A (auto):** No; no consumer. Recorded in Clarifications.

## Q17 — Reversibility
**Q:** Rollback story?
**A (auto):** Revert the commit; comments and a test only.

## Q18 — Premise check
**Q:** Is the filed premise ("absent from the question") still true?
**A (auto):** Half. Absent from `--owed`, present in `[manual]` since 2026-08-20. The spec records that rather than building a second detector.
