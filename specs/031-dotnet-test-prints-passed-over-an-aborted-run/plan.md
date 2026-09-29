# Plan — 031

1. Tests first: test-run-verdict.sh (helper, both directions), an abort arm in test-pipeline-hooks.sh, and a --suite abort arm in test-project-maintenance.sh. Confirm the new arms are red on HEAD.
2. `scripts/run-verdict.sh`: `run_aborted` and `run_verdict` (FR-01).
3. repeat-failure-guard-hook.sh: source the sibling helper and check for an abort before any success pattern (FR-02).
4. project-maintenance.sh --suite: verdict from run_verdict, aborted → named finding, never stamped (FR-03).
5. template-sync-verify.sh: an aborted run at rc 0 → exit 4, obligation stands (FR-04).
6. CORE_SCRIPTS + sync-prompt.md prose (FR-05). Then verify: all touched self-tests are green and the parity test is green.
