# Spec interview — 031-dotnet-test-prints-passed-over-an-aborted-run

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no hardened trigger fires (no auth/PII/upload/new surface, no state machine, 5 files of code).

## Q1 — Scope boundary
**Q:** Only `dotnet test`'s abort line, or every runner's crash wording?
**A (auto):** The vstest lines and the Microsoft.Testing.Platform summary. Other runners already fail loudly on a crash (jest, pytest and cargo all exit non-zero and print no success word). No measurement says otherwise.

## Q2 — Primary actor
**Q:** Who is hurt?
**A (auto):** The developer, or the retry guard, who reads `Passed!` and moves on. On rocky 45% of the suite was unrun behind that word.

## Q3 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** At each of the three call sites, the rocky transcript reads as aborted or failed, and a clean green transcript still reads as passed.

## Q4 — Call sites
**Q:** Which call sites are in scope?
**A (auto):** repeat-failure-guard-hook.sh, project-maintenance.sh --suite and template-sync-verify.sh. These are the three that judge a run's output. e2e-wait-audit.sh is not in the template.

## Q5 — Helper shape
**Q:** Is it an executable or a sourced library?
**A (auto):** Sourced, like hook-verdict.sh. The hook runs on every Bash call, so a subprocess for each check is not worth it.

## Q6 — Precedence
**Q:** What wins: the abort line, the exit code or the summary word?
**A (auto):** The abort line, then a non-zero exit code, then the failure summary. The summary word never makes a run green on its own.

## Q7 — Abort pattern
**Q:** What is the exact pattern?
**A (auto):** Case-insensitive `test run (was )?aborted|summary: aborted`. This covers `The active test run was aborted.`, `Test Run Aborted.` and MTP's `Test run summary: Aborted!`.

## Q8 — False positives
**Q:** Can a passing run print one of those phrases?
**A (auto):** Only a test whose own name or output contains it. That is rare. It would also go red loudly, which is the safe direction for a false call.

## Q9 — Hook verdict
**Q:** Is an abort a failure or unknown to the retry guard?
**A (auto):** A failure. The run did not succeed, and three aborts in a row are the spiral the guard exists to break.

## Q10 — Four states
**Q:** What are success, error, empty and loading for these scripts?
**A (auto):** Success: green stays green. Error: the aborted run is a named finding or a refusal, never silence. Empty: output with no summary keeps today's behaviour at each site. Loading does not apply.

## Q11 — Error message
**Q:** What does the maintenance finding say?
**A (auto):** `[SUITE] ... aborted — the test host did not finish; the summary above counts only the tests that ran.` It is followed by the tail, and it is not stamped.

## Q12 — template-sync-verify exit
**Q:** Which exit code does an aborted verify use?
**A (auto):** Exit 1 with result=failed when rc ≠ 0 (today's path). When rc = 0 but the output shows an abort, exit 4 ("proved nothing, obligation stands"). That is the existing code for the same meaning.

## Q13 — Declared commands
**Q:** Does the abort check apply to a declared command too?
**A (auto):** Yes. The evidence gate judges derived commands, and the abort check judges the run itself.

## Q14 — Concurrency
**Q:** Any ordering concern?
**A (auto):** None. These are pure functions over captured text.

## Q15 — Non-functional
**Q:** Performance?
**A (auto):** One extra grep over the tail the hook already holds, and a sourced file (no fork).

## Q16 — Acceptance criteria
**Q:** What pins it?
**A (auto):** test-run-verdict.sh (the helper, both directions), an abort arm in test-pipeline-hooks.sh's repeat-failure section, and a --suite abort arm in test-project-maintenance.sh. Each new red arm must fail on HEAD.

## Q17 — CORE shipping
**Q:** Does the helper ship to projects?
**A (auto):** Yes. It goes in CORE_SCRIPTS next to hook-verdict.sh. The hook that sources it is already CORE.

## Q18 — Non-goals
**Q:** What is explicitly out?
**A (auto):** Finding why rocky's host crashed, rocky's e2e-wait-audit.sh, and changing the exit-0-on-failure evidence rule.

## Q19 — Reversibility
**Q:** Rollback story?
**A (auto):** One revert. No state format changes.

## Q20 — Docs
**Q:** Which prose changes?
**A (auto):** The sync-prompt.md entry for repeat-failure-guard, one clause about aborts. Nothing else describes the classification.
