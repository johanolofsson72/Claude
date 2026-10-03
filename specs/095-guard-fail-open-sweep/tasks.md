# Tasks — 095

## Phase 1 — tests first (each names its R / AC)
- [x] T001 test-settings-edit-guard.sh: R2 safe list, 095-AC-2
- [x] T002 test-settings-edit-guard.sh: R7 R8 reads, 095-AC-5 (settings half)
- [x] T003 test-settings-edit-guard.sh: R1 git tree verbs in a fixture repo, 095-AC-1
- [x] T004 test-settings-edit-guard.sh + test-trust-anchor-guard.sh: R3 MCP, 095-AC-3
- [x] T005 test-trust-anchor-guard.sh: R8 trust option in prose, R10 exec keys, 095-AC-5 (trust half)
- [x] T006 test-bash-write-guard.sh: R9 sed script word
- [x] T007 test-acceptance-cases.sh: R5 env scrub, timeout split
- [x] T008 test-guard-lib.sh + spec-interview end to end: R6, 095-AC-4
- [x] T009 test-update-template.sh: R11
- [x] T010 test-hook-channels.sh: R4 matcher coverage

## Phase 2 — implementation
- [x] T020 R2 R7 R8 settings_guard.py + shell_glob.sed_script_pure
- [x] T021 R1 settings_guard.py git_tree_verdict + hook pre-check
- [x] T022 R3 settings_guard.py + trust-anchor MCP scan, pre-checks
- [x] T023 R8 R10 trust-anchor trust option, destructive_command exec keys
- [x] T024 R9 bash_write_targets.py
- [x] T025 R5 acceptance_cases.py + spec-interview-guard announce
- [x] T026 R6 guard-lib.sh
- [x] T027 R11 update-template.sh
- [x] T028 R4 matcher change applied by the developer with a ! command

## Phase 3 — verification
- [x] T030 R12 headers and docs (humanizer pass)
- [x] T031 full template suite; mutation gate on changed modules (hard gate)
- [x] T032 adversarial review: security-scanner (assume exploitable), /security-review
- [x] T033 /tla on the git tree-write decision; Allium drift check
- [x] T034 findings closed; register tick, archive, commit, push
