# Plan — 086

Small independent changes, each with its self-test case written red first.

| R | Files | Test |
|---|---|---|
| R1, R2, R5, R6 wiring | `scripts/project-maintenance.sh` | `scripts/test-project-maintenance.sh` |
| R3 | `scripts/stryker_guard.py` (`break` mode), `project-maintenance.sh` | `test-stryker-guard.sh`, `test-project-maintenance.sh` |
| R4 | `scripts/bash_write_targets.py`, `scripts/stryker_guard.py` | `test-stryker-guard.sh`, `test-bash-write-targets*.sh` |
| R6 | new `scripts/validate-hooks.sh`, `scripts/hook_audit.py`; CORE list in `template-autosync.sh` | new `scripts/test-validate-hooks.sh` |
| R7 | `scripts/spec-register-orientation-hook.sh`, `scripts/lane_status.py` (needs parsing) | `test-spec-register-orientation*.sh` / `test-lane-orientation.sh` |
| R8 | `scripts/validate-no-sigpipe-assertions.sh` | `test-no-sigpipe-assertions.sh` |
| R9 | `scripts/validate-scenario-traceability.sh` | `test-validate-scenario-traceability.sh` |
| R10, R11 | `scripts/detect-verify-command.sh` | `test-detect-verify-command.sh` |
| R12 | `scripts/install-nightly-maintenance.sh` | `test-install-nightly-maintenance.sh` |
| R13 | `scripts/tlc-cleanup.sh` | `test-tlc-cleanup.sh` |
| R14, R15 | `test-stryker-guard.sh` header, `.claude/docs/testing.md` | `validate-rule-citations.sh` |

Every new CORE file goes into `CORE_SCRIPTS` and `sync-prompt.md` in the same commit
(`test-sync-prompt-core-parity.sh`). Docs through humanizer. Verify: every touched self-test, then
the declared suite.
