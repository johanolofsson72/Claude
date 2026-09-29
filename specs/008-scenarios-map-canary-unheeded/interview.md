# Spec interview — 008-scenarios-map-canary-unheeded

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
No hardened trigger fired (5 source files, no risk domain), so there are no overflow questions.

## Q1 — Scope boundary
**Q:** Does the spec split any project's map?
**A (auto):** No. It changes the template's canary so that each project records and decides its own map. Splitting stays per-project work.

## Q2 — Scope boundary
**Q:** Is INDEX.md over the canary included?
**A (auto):** No. Row 017 owns the register-size case. The INDEX.md hint is left untouched.

## Q3 — Primary actor & trigger
**Q:** Which run records the finding?
**A (auto):** `project-maintenance.sh`, on any invocation (plain, `--full`, `--if-due`). It is the recurring job, and it already measures the same files.

## Q4 — Primary actor & trigger
**Q:** Should the SessionStart orientation hook write the finding?
**A (auto):** No. A hook that dirties git-tracked files on every session start is worse than the silence. It prints the right remedy and points at the maintenance pass.

## Q5 — Happy-path outcome
**Q:** What does success look like in a project with a 121 KB map?
**A (auto):** Its FINDINGS.md has one open `debt` line naming the path, the size and the split remedy. The next 5-spec review decides it.

## Q6 — Data model
**Q:** What is the finding's text format?
**A (auto):** `scenario-map canary: <path> is <N> KB (<layout role>, canary 25 KB) — <remedy>`. The prefix up to and including the path plus a space is the dedup key.

## Q7 — Validation rules
**Q:** How is "already recorded" decided?
**A (auto):** An open ledger line (`- [ ] F…`) containing the literal key `scenario-map canary: <path> `. Fixed-string match, so a path containing regex metacharacters cannot misfire.

## Q8 — Four observable states
**Q:** What are success, error, empty and loading for a report script?
**A (auto):** Success: a finding is recorded and named in the report. Error: `[SETUP]` when finding.sh is missing, or `[CONTEXT-COST] … could not be recorded` when it exits non-zero. Empty: no oversize map, so nothing is printed and nothing is written. Loading: N/A for a synchronous shell pass.

## Q9 — Error semantics
**Q:** What if finding.sh fails (exit ≠ 0)?
**A (auto):** It is reported as a finding carrying its stderr, and the verdict turns red. It is never swallowed.

## Q10 — Authorization
**Q:** Any authorization surface?
**A (auto):** None. It is a local script writing to the project's own tracked file. N/A.

## Q11 — Concurrency / ordering
**Q:** Two maintenance passes at once?
**A (auto):** They are not guarded, and finding.sh is not either. The worst case is a duplicate line, which the review drops. This is accepted, because nightly maintenance is single-shot by construction.

## Q12 — Integration points
**Q:** Which contracts are touched?
**A (auto):** finding.sh's `--add TEXT --kind debt` CLI (unchanged), scenario-map-layout's split predicate (whether `specs/scenarios/` has files), and the canary test's `[CONTEXT-COST] <path>` output shape, which must be kept.

## Q13 — Edge cases
**Q:** What if a decided finding exists for the same path?
**A (auto):** A new open one is added. Only open ones suppress. The decision is revisited at each review while the map stays oversize.

## Q14 — Edge cases
**Q:** Empty `specs/scenarios/` directory with a big SCENARIOS.md?
**A (auto):** Treat it as single-file, following the layout rule, so the hint is to split.

## Q15 — Non-functional limits
**Q:** Runtime cost?
**A (auto):** At most one `grep -F` and one finding.sh call per oversize file, which is negligible next to the freshness pass.

## Q16 — Acceptance criteria
**Q:** What proves it?
**A (auto):** New cases in test-project-maintenance.sh (A1–A6), plus a hook-remedy arm in test-scenario-map-canary.sh (A7). Both suites must stay green (A8).

## Q17 — Non-goals & assumptions
**Q:** Does the template register keep a per-project list?
**A (auto):** No. The row becomes a pointer to the mechanism, and INDEX.pending.md keeps the 2026-09-29 measurement as dated evidence only.

## Q18 — Reversibility
**Q:** How do you undo it?
**A (auto):** Revert the commit. The recorded findings are ordinary ledger lines that the review can drop.
