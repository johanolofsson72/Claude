# Tasks — 088 guard trust anchors

## Phase 1 — tests first (each names its AC/R)
- [x] T001 test-guard-root-anchor.sh: R1, 088-AC-1, sabotage arm
- [x] T002 test-maintenance-trust.sh arms: R2, 088-AC-2
- [x] T003 test-trust-anchor-guard.sh: R3, 088-AC-3, bash-write-guard route, sabotage arm
- [x] T004 test-developer-answers.sh: R4 R5, 088-AC-4, sabotage arm
- [x] T005 test-acceptance-cases.sh arms: R6, 088-AC-5

## Phase 2 — implementation
- [x] T010 R1 guard_anchor_for / guard_git_boundary; the five guards
- [x] T011 R2 project-maintenance.sh trust prompt
- [x] T012 R3 trust-anchor-guard-hook.sh; bash-write-guard delegate
- [x] T013 R4 developer-answers-hook.sh
- [x] T014 R5 R6 acceptance_cases.py confirm binding and ancestry grandfathering
- [x] T015 R7 settings.json wiring, CORE_SCRIPTS

## Phase 3 — docs and verification
- [x] T030 R8 docs (humanizer pass)
- [x] T031 full template suite green; threat-model residuals final; adversarial review (security-scanner, /security-review)
- [x] T032 /tla on the trust and confirm decisions; Allium drift check
- [x] T033 findings: F090 F091 F093 F094 closed; new residuals recorded
