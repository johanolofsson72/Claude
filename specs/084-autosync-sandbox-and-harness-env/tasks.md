# Tasks — 084 autosync sandbox and harness environment

## Phase 1 — tests first (each names its AC/R)
- [x] T001 test-root-walk-terminates.sh: R1, 084-AC-1, sabotage arm
- [x] T002 test-template-autosync-sandbox-writes.sh: R2 R3, 084-AC-2, 084-AC-3, sabotage arm
- [x] T003 test-self-test-prologue.sh: R4, 084-AC-4, decoy pass
- [x] T004 test-validate-sync-sandbox-declarations.sh arms: R5 R6, 084-AC-5
- [x] T005 test-drive-sync.sh arms: drive_hook refusals and no leak

## Phase 2 — implementation
- [x] T010 R1 root walk in the sync and the eleven other walkers
- [x] T011 R2 push decision, R3 refresh skip in template-autosync.sh
- [x] T012 R5 drive_hook in drive-sync.sh; hook callers migrated
- [x] T013 R5 R6 gate: hook target, census, wrapper table
- [x] T014 R4 prologue in every scripts/test-*.sh
- [x] T015 CORE_SCRIPTS registration of the new tests

## Phase 3 — docs and verification
- [x] T030 template-autosync.md R8 (humanizer pass)
- [x] T031 full template suite green; adversarial review (security-scanner, /security-review); threat-model residuals final
- [x] T032 /tla on the declared-run write decision; Allium drift check
- [x] T033 findings: F013 F015–F020 closed; CDPATH in production scripts recorded
