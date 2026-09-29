# Plan — 024

1. Baseline: every self-test that drives a touched script, run on a worktree of HEAD (`run-log.md`).
2. Per file, by hand: rewrite each reported line (FR-01/02), `bash -n`, run that file's self-tests;
   files with no self-test get a differential run, old vs new, on the same inputs.
3. `validate-no-sigpipe-assertions.sh`: correct the backlog message and header (FR-05).
4. `test-no-sigpipe-assertions.sh`: `--all --strict` arm in template mode (FR-04) and the
   SIG_IGN mechanism arm (FR-06).
5. Verify: default gate 0, `--all --strict` 0, full touched-test list green vs baseline.
