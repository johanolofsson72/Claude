# Tasks — 105

## Phase 1 — tests first (each names its R / AC)
- [x] T001 test-trust-anchor-guard.sh: R1 verbs, R2 notice dir + git-dir substitution, R4 PATH writes, R6 parse check; 105-AC-1, 105-AC-3
- [x] T002 test-guard-lib.sh: R1 no-.git fallback, R3 notice base; 105-AC-2
- [x] T003 test-harness-state-gc.sh: R3 sweep follows the base
- [x] T004 test-template-identity.sh: R5 slow git, GIT_* scrub
- [x] T005 test-settings-edit-guard.sh: R7 runners and handed-on names, R8 installer word; 105-AC-4
- [x] T006 test-guard-notice-mod.sh: R8 --accept pin
- [x] T007 test-acceptance-cases.sh: R9 spec-bound tokens, R10 check + topo order; 105-AC-5
- [x] T008 test-validate-hooks.sh: R11 UNWIRED, local mask, substring
- [x] T009 test-guard-canonical-paths.sh: R13 case-mismatched project dir ends

## Phase 2 — implementation
- [x] T020 R13 guard-precheck.sh walk ends by depth
- [x] T021 R1 R3 guard-lib.sh; harness-state-gc.sh
- [x] T022 R1 R2 R4 R6 trust-anchor-guard-hook.sh
- [x] T023 R5 template-identity.sh
- [x] T024 R7 R8 settings_guard.py
- [x] T025 R8 install-guard-notice-mod.sh
- [x] T026 R9 R10 acceptance_cases.py
- [x] T027 R11 hook_audit.py

## Phase 3 — verification
- [x] T030 R12 headers and docs (humanizer pass)
- [x] T031 full template suite; bench-hooks (SC-2); mutation gate on changed modules (hard gate)
- [x] T032 adversarial review: security-scanner (assume exploitable), /security-review
- [x] T033 /tla on the walk fallback and the answer binding; Allium drift check
- [ ] T034 findings closed; register tick, archive, commit, push
