# Spec interview — 012-core-file-comments-hold-real-scenario-ids

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with the recommended option). The hardened trigger is size only
(nine files, comment lines). The overflow threat-surface questions are Q16–Q18, auto-answered: the
change alters no executable line outside a self-test, so no answer depends on the developer's call.

## Q1 — Scope boundary
**Q:** Which files does the scrub cover?
**A (auto):** CORE production scripts: `CORE_SCRIPTS` names whose basename does not start with `test-`/`test_`.

## Q2 — Scope boundary
**Q:** Are CORE test files included?
**A (auto):** No. In a test, naming an id is the proof of coverage (R6).

## Q3 — Scope boundary
**Q:** Are `.claude/rules/scenarios.md` and the wizard skill included?
**A (auto):** No. They are documentation under `.claude/`, which no reference root contains.

## Q4 — Primary actor & trigger
**Q:** Who is hurt, and when?
**A (auto):** A developer reading a coverage figure after a test was deleted, on a project whose gate reads `scripts/` (consultpilot's accounting gate, or a declared root).

## Q5 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** The gate, run over the CORE production scripts, finds zero references, and the self-test asserts it.

## Q6 — Data model
**Q:** What replaces a `Covers:` line?
**A (auto):** `Scenario ids: named by scripts/<self-test>, which is the proof (row 012 — a comment here would count as coverage).`

## Q7 — Validation rules
**Q:** What exactly is a forbidden token?
**A (auto):** Whatever the gate's own extractor emits. The case runs the gate, so the rule is its regex by construction.

## Q8 — Four states
**Q:** What does the case report in each state?
**A (auto):** Success: PASS with the file count. Error: FAIL naming each id and the file that holds it. Empty: a CORE list that yields zero files is a FAIL, never a pass. Loading: n/a (it is a batch).

## Q9 — Error semantics
**Q:** What if `template-autosync.sh --list-core-scripts` fails?
**A (auto):** FAIL. "I could not list" is never reported as clean.

## Q10 — Authorization
**Q:** Any authorization surface?
**A (auto):** None. It is a local self-test.

## Q11 — Concurrency
**Q:** Can the case collide with other cases?
**A (auto):** No. It works in its own mktemp dir under the harness TMP.

## Q12 — Integration points
**Q:** What does it depend on?
**A (auto):** `validate-scenario-traceability.sh --roots`, `template-autosync.sh --list-core-scripts`.

## Q13 — Edge cases
**Q:** A CORE name listed with no file?
**A (auto):** Skipped here. `--unlisted` already reports that as its own defect, and it is not an id.

## Q14 — Non-functional
**Q:** Runtime budget?
**A (auto):** One gate run, under 2 s. The harness is already close to its timeout (H7bq), so the run is measured and logged.

## Q15 — Acceptance
**Q:** What proves the case bites?
**A (auto):** The sabotage arm: an id planted in one copied file's comment must turn it red and be named.

## Q16 — Overflow: tampering
**Q:** Can a placeholder be crafted that the gate reads but the case misses?
**A (auto):** No. The case and the gate share one extractor.

## Q17 — Overflow: information disclosure
**Q:** Do the removed ids reveal anything sensitive?
**A (auto):** No. They are row numbers. The concern is coverage integrity, not secrecy.

## Q18 — Overflow: resource exhaustion
**Q:** Can the case be made slow?
**A (auto):** Only by CORE growing. The list is about 60 files and the case is linear in them.

## Q19 — Reversibility
**Q:** How is this undone?
**A (auto):** `git revert`. It touches comments and one test case.

## Q20 — Non-goals
**Q:** Does this admit `scripts/` as a reference root?
**A (auto):** No. That is F005, which stays open.
