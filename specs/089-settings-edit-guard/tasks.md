# Tasks — 089 settings edit guard

## Phase 1 — tests first (each names its AC/R)
- [x] T001 test-settings-edit-guard.sh: R1 R2 R3, 089-AC-1, 089-AC-2, 089-AC-4 (Edit/Write/MultiEdit/NotebookEdit)
- [x] T002 test-settings-edit-guard.sh: R4, 089-AC-3 (shell spellings, read list, no echo)
- [x] T003 test-settings-edit-guard.sh: R5, 089-AC-5 (bash-write-guard route)
- [x] T004 test-settings-edit-guard.sh: R6 (crash denies, own files repairable), sabotage arm

## Phase 2 — implementation
- [x] T010 R1–R4 settings_guard.py
- [x] T011 R6 R7 settings-edit-guard-hook.sh
- [x] T012 R5 bash-write-guard delegate
- [x] T013 R8 CORE_SCRIPTS, mutation table, settings.json wiring

## Phase 3 — docs and verification
- [x] T030 R8 docs (humanizer pass)
- [x] T031 full template suite green; mutation gate on the hook; adversarial review (security-scanner, /security-review)
- [x] T032 /tla on the edit/shell decision; Allium drift check
- [x] T033 findings: F081 F103 closed; new residuals recorded
