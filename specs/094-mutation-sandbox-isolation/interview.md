# Spec interview — 094-mutation-sandbox-isolation

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: spec-only, no hardened trigger (no auth, PII, upload, new external
surface, state machine or entity). The change removes reach from tests and adds none. Every
question below had a defensible recommendation.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F117 as R1–R4 in `run-mutation-gate.sh`, F128 as a verification (R5). Out:
non-git network isolation, the ordinary suite run, F132 (sync-prompt reuse, kept as debt).

## Q2 — Primary actor and trigger
**Q:** Who runs the code this changes, and when?
**A (auto):** The developer or the nightly, through `run-mutation-gate.sh` directly or through
`project-maintenance.sh --full`. Every baseline and mutant test run goes through `run_test`.

## Q3 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** Same scores and same reports as before, with each test unable to see the
developer's home, template clone or git credentials.

## Q4 — Data model
**Q:** What new state exists?
**A (auto):** One directory per worker copy, `<copy>.home`, holding one `.gitconfig`. It lives
under `$RUN` and is removed with it.

## Q5 — Validation
**Q:** What does the runner check before using the sandbox home?
**A (auto):** That it was created. A failed `mkdir` or write is `die`, the same as a copy that
could not be prepared, because a test run without isolation is the thing this spec removes.

## Q6 — Four observable states
**Q:** Success, error, empty and loading for a CLI gate?
**A (auto):** Success: unchanged score output. Error: a sandbox that cannot be built dies with a
message naming the path. Empty: no modules selected is unchanged. Loading: the existing progress
lines. No new UI.

## Q7 — Error semantics
**Q:** A test that fails only because it needed the real home?
**A (auto):** It shows up as a red baseline, and the run is UNMEASURED with the test named. That
is the existing fail-closed path. The fix is the test's, not a fallback to the real home.

## Q8 — Authorization
**Q:** Does anything gain or lose permission?
**A (auto):** Tests lose access to the developer's git identity, credential helpers and template
clone. Nothing gains anything.

## Q9 — Concurrency
**Q:** Parallel workers?
**A (auto):** One home per copy, so no two workers share a writable home.

## Q10 — Integration points
**Q:** Who else is affected?
**A (auto):** `project-maintenance.sh` (it runs the gate), the nightly, and `test-run-mutation-gate.sh`.
The runner's CLI and report formats do not change.

## Q11 — Edge: a test sets its own HOME
**Q:** Does isolation survive it?
**A (auto):** No, and it doesn't need to. Such a test has left the developer's home too, so
`template_candidates()` no longer finds the real clone. It loses the protocol block, which is
defence in depth here, not the fix.

## Q12 — Edge: the self-test prologue
**Q:** Does `self-test-env.sh` undo any of it?
**A (auto):** It unsets `GIT_CONFIG_COUNT`, `GIT_CONFIG_GLOBAL`, `GIT_SSH_COMMAND` and
`CLAUDE_TEMPLATE_DIR`, and leaves `HOME` alone on purpose. So the protocol block goes in the
sandbox `.gitconfig`, and `HOME` carries the isolation.

## Q13 — Edge: local remotes
**Q:** Do fixtures that clone or push to a path still work?
**A (auto):** Yes. `file` and plain paths are not in the refused list.

## Q14 — Non-functional
**Q:** Cost?
**A (auto):** One `mkdir` and one small file per worker per run. No change per test.

## Q15 — Acceptance
**Q:** Measurable definition of done?
**A (auto):** SC-A to SC-E: probe arm green, sabotage arm red against the mutant, real baseline
green.

## Q16 — Reversibility
**Q:** Rollback?
**A (auto):** Revert the commit. No state persists beyond a run.

## Q17 — Non-goals and assumptions
**Q:** What is assumed?
**A (auto):** Any git that reads `~/.gitconfig` and knows `protocol.<name>.allow` (2.12, from
2017). Git Bash and Linux are covered. `mkdir` and `printf` only, so nothing new on Windows.

## Q18 — F128
**Q:** Fix or verify?
**A (auto):** Verify. Line 586 already checks `hookEventName`, and section 14 is green.
