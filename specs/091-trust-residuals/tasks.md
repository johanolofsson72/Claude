# Tasks — 091 trust residuals

## Phase 1 — tests first (each names its AC/R)
- [x] T001 test-template-identity.sh: R1, 091-AC-1, sabotage arm
- [x] T002 test-trust-anchor-guard.sh arms: R2 (remote, update-ref, refspec), R7 placement, 091-AC-1
- [x] T003 test-template-autosync-supply-chain.sh arms: R3, R4, 091-AC-2
- [x] T004 test-update-template.sh arms: R5, 091-AC-3
- [x] T005 maintenance trust / placement / cloud pull arms: R6, R7, 091-AC-4
- [x] T006 test-acceptance-cases.sh + test-developer-answers.sh arms: R8, R9, 091-AC-5

## Phase 2 — implementation
- [x] T010 R1 template-identity.sh and the four callers
- [x] T011 R2 trust-anchor-guard remote/ref verdicts
- [x] T012 R3 pin_on_main
- [x] T013 R4 flagged paths, skills from ls-files
- [x] T014 R5 update-template flags and frontmatter review
- [x] T015 R6 suite_identity files
- [x] T016 R7 placement, pull, guard path
- [x] T017 R8 R9 acceptance_cases.py, --question
- [x] T018 R10 CORE_SCRIPTS

## Phase 3 — docs and verification
- [x] T030 R10 docs (humanizer pass)
- [x] T031 full template suite green; threat model final; adversarial review; /security-review
- [x] T032 mutation gate; /tla on the confirm binding; Allium drift check
- [x] T033 findings closed (F079 F080 F092 F095 F097 F104 F107); residuals recorded
