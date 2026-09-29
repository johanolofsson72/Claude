# Spec interview — 014-autosync-adds-gates-no-runner-registers

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with the recommended option). No hardened trigger fires (four files,
no entity, no auth/PII/upload, no concurrency), so there are no overflow questions. No question
lacked a defensible recommendation.

## Q1 — Scope boundary
**Q:** Does the spec change consultpilot's `run-gates.sh`?
**A (auto):** No. That runner is project-owned. The template publishes the answer, and adoption is a finding with the consumer contract written out (spec § R-adopt).

## Q2 — Scope boundary
**Q:** Does the sync refuse to deliver a gate that no registry names?
**A (auto):** No. H7be rejected that (a second oracle in CORE that cannot see the registry), and the rejection still holds.

## Q3 — Scope boundary
**Q:** Is F004 (`test-coverage-hook.sh` matches the gate pattern) in scope?
**A (auto):** Yes. It is the same classification question for a template-only file, and a line in `the `core-gates.sh` table` closes it.

## Q4 — Primary actor & trigger
**Q:** Who is hurt, and when?
**A (auto):** A developer on a project with a gate registry, right after a sync that ships a new gate-shaped CORE script. From then on every run reports DRIFT until someone edits the registry by hand.

## Q5 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** The template names every one of its gate-shaped scripts as a gate or as a non-gate with a reason. A runner that asks gets both lists, so a new CORE gate is registered in the same sync that ships it.

## Q6 — Data model
**Q:** Where does the classification live?
**A (auto):** In a CORE tool, `scripts/core-gates.sh`, as a table of `name|reason` lines. Gates are derived (`--list-core-scripts` filtered by shape, minus the table) and never listed. Two alternatives were dropped: a new query mode on the sync (the query-mode cap of four is a developer decision) and a `.txt` data file (the sync copies only `*.sh`, `*.py` and `speckit-version`).

## Q7 — Data model
**Q:** Gate by default, or excluded by default?
**A (auto):** Gate by default. A CORE test is green in the template before it ships, so a red one downstream is a real finding about that project. H7aw found `test-runtime-markers-ignored.sh` red on that basis. Excluded by default is the state that hid it.

## Q8 — Validation rules
**Q:** What is "gate-shaped"?
**A (auto):** A basename matching `^(test|validate|verify|check)-.*\.sh$`, the same pattern consultpilot's runner discovers with. `.py` tests and `*-census.sh` are not gate-shaped, so neither list covers them.

## Q9 — Validation rules
**Q:** What makes a `the `core-gates.sh` table` line invalid?
**A (auto):** A name that is not gate-shaped, a name that is in neither `CORE_SCRIPTS` nor `TEMPLATE_ONLY_SCRIPTS`, an empty reason, or a duplicate name.

## Q10 — Four states
**Q:** What does the self-test report in each state?
**A (auto):** Success: PASS lines with counts. Error: FAIL naming the offending line. Empty: a gate-shaped CORE set of zero is a FAIL, never a pass. Loading: n/a (batch).

## Q11 — Error semantics
**Q:** What should a runner do when the query fails?
**A (auto):** Report drift and never read the failure as an empty list. That is written into the consumer contract.

## Q12 — Authorization
**Q:** Who may add an exclusion?
**A (auto):** Anyone editing the template, but only with a written reason. The self-test refuses an empty one. There is no runtime authz surface.

## Q13 — Concurrency / ordering
**Q:** Any ordering concern between the sync and the runner?
**A (auto):** None new. The runner reads the lists at run time from the `template-autosync.sh` the last sync delivered, so the lists and the delivered files come from the same commit.

## Q14 — Integration points
**Q:** What else reads the query-mode names?
**A (auto):** `drive-sync.sh` and `validate-sync-sandbox-declarations.sh` enumerate the query modes and cap them at four. Because this spec adds no mode, neither changes. The consumer uses the existing `--list-core-scripts`.

## Q15 — Edge cases
**Q:** A CORE gate-shaped name that has no file in the template?
**A (auto):** FAIL (R6e). A runner cannot run a gate that has no bytes, and the rocky F041 incident was this exact shape.

## Q16 — Edge cases
**Q:** What about a template-only gate-shaped script a project still holds a stale copy of?
**A (auto):** Every gate-shaped template-only name has to be in `the `core-gates.sh` table` (R6d), so a runner that asks never runs one.

## Q17 — Non-functional limits
**Q:** How fast must the modes and the self-test be?
**A (auto):** `core-gates.sh` is one existing query plus a grep, well under a second. The self-test is offline, under ~5 s, and makes no network calls.

## Q18 — Acceptance criteria
**Q:** How is "the classification is right" proven, and not just "the lists are consistent"?
**A (auto):** By measurement (R8). Every gate-shaped CORE script runs once in the template with stdin closed, and its exit code and runtime go in the run-log. Each non-gate reason cites that measurement or the file's own header.

## Q19 — Non-goals & assumptions
**Q:** Is a generic runner for projects that have none in scope?
**A (auto):** No. Only consultpilot has a runner. A default project running no CORE self-test at all is a separate gap, recorded as a finding.

## Q20 — Reversibility
**Q:** How is it undone?
**A (auto):** Revert the commit. The modes are additive and nothing downstream reads them yet.
