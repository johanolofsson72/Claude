# Plan — 032

1. Tests first: `scripts/test-spec-dir-absent.sh` covering SC-032-01..06. It reads verdicts through `hook_verdict`. Confirm SC-032-02/04 are red on HEAD and the rest green.
2. Add `html|htm|css|scss|sass|less` to `SOURCE_EXTS` in `spec-register-guard-hook.sh`, `pipeline-state-guard-hook.sh` and `spec-interview-guard-hook.sh` (FR-02, FR-03).
3. Update the extension list in `.claude/docs/spec-register-rationale.md` (FR-05).
4. Verify: new self-test green, plus test-pipeline-hooks.sh, test-active-spec-resolution.sh, test-bash-write-guard.sh and test-hook-channels.sh.
