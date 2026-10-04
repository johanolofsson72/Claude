# Tasks — 098

## Phase 1 — tests first (each names its R / AC)
- [x] T001 test-trust-anchor-guard.sh: R1 link anywhere in the path, 098-AC-1
- [x] T002 test-acceptance-cases.sh: R2 pushed line without a local answer denies, 098-AC-2
- [x] T003 test-core-machinery-guard.sh + test-core-owed-tick-guard.sh: R3 missing sync, 098-AC-3
- [x] T004 test-guard-lib.sh: R4 git missing / slow / answered, R6 stamp location, 098-AC-4
- [x] T005 test-settings-edit-guard.sh: R7 pipeline flow, 098-AC-5
- [x] T006 test-validate-hooks.sh: R8 matcher audit
- [x] T007 test-run-mutation-gate.sh: R5 env allowlist, push by path, rc 137

## Phase 2 — implementation
- [x] T020 R4 R6 guard-lib.sh `_guard_git`, `GUARD_GIT_UNSURE`, announce stamp; harness-state-gc sweep
- [x] T021 R4 pipeline guards deny on unsure; R3 R4 CORE guards
- [x] T022 R1 trust-anchor pre-check
- [x] T023 R2 acceptance_cases.py
- [x] T024 R7 settings_guard.py
- [x] T025 R8 hook_audit.py
- [x] T026 R5 run-mutation-gate.sh

## Phase 3 — verification
- [x] T030 R9 headers and docs (humanizer pass)
- [x] T031 full template suite; bench-hooks (SC-2); mutation gate on changed modules (hard gate)
- [x] T032 adversarial review: security-scanner (assume exploitable), /security-review
- [x] T033 /tla on the R7 flow decision and the R4 split; Allium drift check
- [x] T034 findings closed; register tick, archive, commit, push
