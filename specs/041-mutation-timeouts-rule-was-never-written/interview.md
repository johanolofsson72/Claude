# Spec interview — 041-mutation-timeouts-rule-was-never-written

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no auth, PII, upload, new external surface, state machine or entity. The new validator reads files and writes nothing.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the rule, its CORE listing, two pointers, a citation validator and its test. Out: changing gremlins/Stryker behaviour, a strict scorer, the allium warnings (row 050), maintenance wiring (row 052).

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** Any reader who follows one of the ten citations and finds nothing, and any project reading a mutation score whose timeouts count as kills.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** Every citation resolves to a numbered trap that says what the citing site meant, the rule reaches projects on the next sync, and the validator is green on the template.

## Q4 — Trap numbering
**Q:** Invent a numbering or recover it?
**A (auto):** Recover. The ten sites agree on trap 4's meaning; traps 1-3 and 5 are the concrete mutation cases the row names, ordered so the principle sits at 4.

## Q5 — What trap 4 says
**Q:** One principle or two?
**A (auto):** One principle with two halves: unmeasured must not render as clean, and a detector is believed only after a known positive (control first). Both halves are cited.

## Q6 — Always loaded or path-scoped?
**Q:** Should the rule load every session?
**A (auto):** Path-scoped to mutation tooling files. Always-loaded rules cost context in every project on every session; the always-loaded spec-hardening.md carries a one-line pointer instead.

## Q7 — Shipping
**Q:** Does dropping the file in `.claude/rules/` reach projects?
**A (auto):** No. `copy_file` adds a new file only if it is CORE, so it must join `CORE_RULES`.

## Q8 — Recurrence
**Q:** Is writing the file enough?
**A (auto):** No. The defect is a citation nothing checks, so a validator checks that cited rules/docs exist and cited traps are defined.

## Q9 — Validator scope
**Q:** Which files are scanned?
**A (auto):** Git-tracked files outside `specs/`. Specs are history and legitimately name files that were missing at the time.

## Q10 — Fixture paths
**Q:** How are test fixtures like `demo-rule.md` told apart from citations?
**A (auto):** A path the same file builds under a variable root (`$T/.claude/rules/demo-rule.md`) is a fixture in that file. The sweep shows every fixture has that form.

## Q11 — The four observable states
**Q:** What does the validator print for success, error, empty and loading?
**A (auto):** Success: exit 0 with the count. Error: exit 1 with `path:line: reason` per problem. Empty: exit 3, "unmeasurable". Loading: N/A (a sub-second read-only scan). Usage/environment error: exit 2.

## Q12 — Error semantics
**Q:** Is a dangling citation fatal?
**A (auto):** It fails the validator (exit 1). It never blocks a hook or an edit; it is a check, not a guard.

## Q13 — Trap-citation window
**Q:** How far from the rule path may `trap N` sit?
**A (auto):** The citing line and the one before it. The sweep has one two-line citation (`test-scenario-map-rows.sh:23-24`); wider windows start catching local trap numbering in other files.

## Q14 — Bare basename citations
**Q:** `trap 4 in mutation-timeouts.md` has no directory. Checked?
**A (auto):** Yes, when `trap N` sits on the same or previous line. The basename is looked up in `.claude/rules/` then `.claude/docs/`; not found is a dangling citation.

## Q15 — Concurrency / ordering
**Q:** Any?
**A (auto):** None. Read-only, single process.

## Q16 — Integration points
**Q:** What does this touch?
**A (auto):** `template-autosync.sh` lists only. The `--unlisted` tick gate requires new scripts to be in CORE_SCRIPTS or TEMPLATE_ONLY_SCRIPTS; both new scripts go in CORE.

## Q17 — Portability
**Q:** Platforms?
**A (auto):** Bash 3.2 wrapper with python3 for the scan, the same pattern other CORE scripts use; must pass `validate-portability.sh`.

## Q18 — Acceptance criteria
**Q:** Measurable done?
**A (auto):** SC-A..N green, the real-repo arm red on HEAD, hand mutations of the validator killed, portability clean.

## Q19 — Stryker evidence
**Q:** Does the rule claim Stryker counts timeouts as detected?
**A (auto):** Yes. project-maintenance.sh already records a measured case (strict 97.69, Stryker 100.00), and Stryker defines its score as detected/valid with detected = killed + timeout.

## Q20 — Reversibility
**Q:** Rollback story?
**A (auto):** Revert the commit. Nothing is migrated, and projects lose the rule on the next sync.
