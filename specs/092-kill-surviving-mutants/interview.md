# Spec interview — 092-kill-surviving-mutants

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened on file count only (trigger 4). Threat-surface overflow is covered by Q16–Q18. The
open policy decision (what counts as a kill for a hang mutant) goes to the developer as O1.

## Q1 — Scope boundary
**Q:** Which findings does 092 close?
**A (auto):** F099 F100 F101 F102 F108, the five folded into the row at the 2026-10-02 review. Fresh survivors from tonight's sample are out of scope and get recorded.

## Q2 — Which survivors: the recorded ones or today's?
**Q:** The findings name H3/085 line numbers that have moved. Arm the old list or the re-measured one?
**A (auto):** The re-measured one. Each recorded line was mapped by content to 0f9a90c, and every site on it was measured (41 survivors + 1 timeout). Arming what no longer survives would be theatre.

## Q3 — Primary actor
**Q:** Who benefits, and from where?
**A (auto):** The template author, through the nightly mutation gate and `project-maintenance.sh --full`, plus every project whose guards and sync come from these scripts.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** The same `--lines` invocation scores ≥ 95%, every remaining site carries a defensible `# mutant-equivalent` reason, and the full template suite is green.

## Q5 — Data model
**Q:** Does anything persisted change?
**A (auto):** No. Fixtures are temp dirs. `hook_verdict` gains an optional second argument and keeps its output vocabulary, plus `exit-<n>`.

## Q6 — Validation rules for hook_verdict's rc
**Q:** What does `hook_verdict OUT RC` do with an rc that is not a number?
**A (auto):** Treat anything other than the literal `0` as non-zero: `exit-<RC>`. A helper that passes garbage gets a red test, not a silent pass.

## Q7 — Four states, as they apply to scripts
**Q:** Success, error, empty and loading for test changes?
**A (auto):** Success: a case passes on the real script. Error: the case fails, naming the mutant's symptom. Empty: R1 is the "empty" project (no marker), and R4's never-synced `[check]` line. Loading: R6 bounds a hang so it reports instead of stalling.

## Q8 — Error semantics
**Q:** How does a case report a failure?
**A (auto):** Each suite's existing `bad`/`fail` line, with the wanted and got values, e.g. `want deny, got exit-1`.

## Q9 — Authorization
**Q:** Any authorization surface?
**A (auto):** None new. The guard cases assert the existing deny decisions more strictly (exit code included).

## Q10 — Concurrency
**Q:** Can the new cases collide with parallel mutation workers?
**A (auto):** No. Each suite works in its own `mktemp -d` with `HOME` redirected, as the runner already requires; nothing writes outside it.

## Q11 — Integration points
**Q:** Which suites change?
**A (auto):** test-guard-canonical-paths (R1), hook-verdict.sh + test-hook-channels + test-guard-root-anchor + test-pipeline-hooks (R2), test-guard-fail-closed (R3), the autosync suites (R4), test-project-maintenance / test-maintenance-trust (R5), test-validate-scenario-traceability and test-project-freshness (R6).

## Q12 — Edge: an equivalent mutant
**Q:** What happens to a site that no test can kill?
**A (auto):** Only a real equivalence gets the `# mutant-equivalent: <reason>` marker, and the reason has to name why no caller can see the difference. A marker also hides every other site on its line, so a line that holds a killable site gets a direct contract test instead (the C106 precedent).

## Q13 — Edge: the hang mutant
**Q:** project-freshness.sh:404's `-n`→`-z` mutant loops forever. Mark it, or arm it?
**A:** Arm it with a self-bounded case (O1, developer answer below).

## Q14 — Non-functional limits
**Q:** How much may the suites slow down?
**A (auto):** Each new case under 2 s except R6's bound. Total under 30 s added across all suites. The runner's per-mutant limit is 3× baseline, so a slow case directly slows the gate.

## Q15 — Acceptance criteria
**Q:** What is measurable?
**A (auto):** The `--lines` score ≥ 95% on the same line set. The full template suite is green. Each case is named with its line or its 092-AC id.

## Q16 — Threat: a weakened assertion
**Q:** Could the change relax an existing guard expectation?
**A (auto):** It must not. R2 can only turn a pass into `exit-N`. The adversarial review diffs every changed `expect`/`ok` line for a relaxed want.

## Q17 — Threat: fixtures reading real state
**Q:** Can a new fixture read the developer's real `~/.claude` or `~/repos/Claude`?
**A (auto):** No. Every suite touched already exports `HOME` into its temp dir, and new fixtures stay under it.

## Q18 — Threat: resource exhaustion in the suite
**Q:** Can the R6 bound itself hang on a host without `timeout`?
**A (auto):** No. It uses `timeout`/`gtimeout` when present, otherwise a background `sleep 20; kill` watchdog.

## Q19 — Non-goals
**Q:** What is explicitly not done?
**A (auto):** No fresh survivor hunt, no runner change, no 093 work (section 5's runner report and suite timeouts).

## Q20 — Reversibility
**Q:** Rollback story?
**A (auto):** Tests only, plus one backwards-compatible helper argument. A revert of the commit is complete.

## O1 — What counts as a kill for a mutant that hangs  (overflow — developer)
**Q:** project-freshness.sh:404 `-n`→`-z` never ends; the runner reports a timeout, which is not a kill. Arm it with a self-bounded case, or mark it equivalent?
**A:** Arm it, self-bounded. A suite case runs freshness under its own 20 s bound, so the looping mutant fails that case, and the runner counts a kill rather than a timeout.
