# Tasks — 095a

## Phase 1 — tests first (each names its R / AC)
- [ ] T001 test-settings-edit-guard.sh: 095a-R1 mod path rules (a)–(e), near misses, case, symlink, cap; PBT
- [ ] T002 test-settings-edit-guard.sh: 095a-R2 Edit route, 095a-AC-1, 095a-AC-2, 095a-AC-4
- [ ] T003 test-settings-edit-guard.sh: 095a-R3 shell route, 095a-AC-1 (heredoc, cp -r), 095a-AC-4 (mv)
- [ ] T004 test-settings-edit-guard.sh: 095a-R4 git route in a fixture repo, 095a-AC-3
- [ ] T005 test-settings-edit-guard.sh: 095a-R5 MCP route, 095a-AC-1
- [ ] T006 test-settings-edit-guard.sh: 095a-R6 pre-check end to end, 095a-R7 deny text
- [ ] T007 test-settings-edit-guard.sh: 095a-R10 claude binary

## Phase 2 — implementation
- [ ] T020 R1 ModZones in settings_guard.py; Guarded consults it
- [ ] T021 R2 edit_verdict mod-file
- [ ] T022 R3 R5 verdict renaming in main(); hooks.json by name
- [ ] T023 R10 claude_cli_verdict
- [ ] T024 R4 git candidates and compare
- [ ] T025 R6 R7 hook pre-check and deny text
- [ ] T026 R8 probe-autoload.py in the spec folder

## Phase 3 — verification
- [ ] T030 R9 headers and docs (humanizer pass)
- [ ] T031 full template suite; mutation gate on the changed lines (hard gate)
- [ ] T032 adversarial review: security-scanner (assume exploitable), /security-review
- [ ] T033 /tla on the verdict; Allium drift check
- [ ] T034 findings recorded; register tick, archive, commit, push
