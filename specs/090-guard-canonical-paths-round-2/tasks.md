# Tasks — 090 guard canonical paths, round 2

## Phase 1 — tests first (each names its AC/R)
- [x] T001 test-guard-canonical-paths.sh: R1 R2 R3 R4 R6 R7, 090-AC-1/2/3, sabotage arms
- [x] T002 test-destructive-command-guard.sh arms: R5, 090-AC-4, sabotage arm
- [x] T003 test-sensitive-file-guard.sh arms: R8(a), 090-AC-5, sabotage arm
- [x] T004 test-trust-anchor-guard.sh arms: R8(b), 090-AC-5

## Phase 2 — implementation
- [x] T010 R1 guard-lib stored names (_guard_pwd, final name, anchor)
- [x] T011 R2 guard-precheck.sh; the five prechecks
- [x] T012 R3 guard_ext_of, SOURCE_EXTS in the three guards
- [x] T013 R4 notebook_path fallback; matcher applied by the developer
- [x] T014 R6 R7 guard_git_boundary kinds; the three walks inherit past a worktree
- [x] T015 R5 destructive_command.py push forms
- [x] T016 R8 sensitive_paths.py sed scripts; trust-anchor glob expansion
- [x] T017 R9 CORE_SCRIPTS

## Phase 3 — docs and verification
- [x] T030 R9 docs (humanizer pass)
- [x] T031 full template suite green; threat model final; adversarial review (security-scanner, /security-review)
- [x] T032 mutation gate on the changed modules; /tla on the walk; Allium drift check
- [x] T033 findings: F082 F083 F084 F085 F096 F105 F106 F112 F122 closed; residuals recorded
