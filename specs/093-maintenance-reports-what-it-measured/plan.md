# Plan — 093

| R | Files | Test |
|---|---|---|
| R1 | `scripts/project-maintenance.sh` section 5 | `scripts/test-project-maintenance.sh` (stub runner) |
| R2 | `scripts/maintenance_ledger.py`, `scripts/maintenance-due.sh`, `scripts/install-nightly-maintenance.sh` | `test-maintenance-ledger.sh`, `test-maintenance-due.sh` |
| R3 | `scripts/maintenance-due.sh` | `test-maintenance-due.sh` |
| R4 | `.claude/.suite-command`, `scripts/project-maintenance.sh` suite section | `test-project-maintenance.sh` |
| R5 | the 52 files `validate-no-sigpipe-assertions.sh --leaks` names | `test-no-sigpipe-assertions.sh` (real-tree arm), each file's own self-test |
| R6 | every production `cd "$(dirname …)"`, `scripts/portability_audit.py` | `test-validate-portability.sh` (or its arm in the portability test) |

Docs through humanizer. Verify: touched self-tests, then the declared suite.
