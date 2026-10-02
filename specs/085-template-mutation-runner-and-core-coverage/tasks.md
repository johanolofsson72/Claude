# Tasks — 085 template mutation runner and core coverage

## Phase 1 — tests first (each names its AC/R)
- [x] T001 test-run-mutation-gate.sh: R1, 085-AC-2, 085-AC-4, sabotage arm
- [x] T002 test-maintenance-ledger.sh arms: R5, 085-AC-5

## Phase 2 — implementation
- [x] T010 R1 scripts/run-mutation-gate.sh
- [x] T011 R5 maintenance_ledger.py readiness
- [x] T012 R3 re-measure F048 F049 F071 F072 sites; arms or equivalence marks (085-AC-3)
- [x] T013 R4 F073 diagnosis

## Phase 3 — docs and verification
- [x] T030 docs (humanizer pass)
- [x] T031 R2 project-maintenance.sh --full in the template stamps mutation (085-AC-1)
- [x] T032 full template suite green; bash 3.2; Linux run; adversarial review; /security-review
- [x] T033 /tla; Allium drift check
- [x] T034 findings: F047 F048 F049 F058 F071 F072 F073 resolved; new survivors recorded
