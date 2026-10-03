# Tasks — 095a

## Phase 1 — tests first (each names its R / AC)
- [x] T001 test-settings-edit-guard.sh: 095a-R1 mod path rules (a)–(e), near misses, case, symlink, cap; PBT
- [x] T002 test-settings-edit-guard.sh: 095a-R2 Edit route, 095a-AC-1, 095a-AC-2, 095a-AC-4
- [x] T003 test-settings-edit-guard.sh: 095a-R3 shell route, 095a-AC-1 (heredoc, cp -r), 095a-AC-4 (mv)
- [x] T004 test-settings-edit-guard.sh: 095a-R4 git route in a fixture repo, 095a-AC-3
- [x] T005 test-settings-edit-guard.sh: 095a-R5 MCP route, 095a-AC-1
- [x] T006 test-settings-edit-guard.sh: 095a-R6 pre-check end to end, 095a-R7 deny text
- [x] T007 test-settings-edit-guard.sh: 095a-R10 claude binary

## Phase 2 — implementation
- [x] T020 R1 ModZones in settings_guard.py; Guarded consults it
- [x] T021 R2 edit_verdict mod-file
- [x] T022 R3 R5 verdict renaming in main(); hooks.json by name
- [x] T023 R10 claude_cli_verdict
- [x] T024 R4 git candidates and compare
- [x] T025 R6 R7 hook pre-check and deny text
- [x] T026 R8 probe-autoload.py in the spec folder

## Phase 3 — verification
- [x] T030 R9 headers and docs (humanizer pass)
- [x] T031 full template suite; mutation gate on the changed lines (hard gate)
- [x] T032 adversarial review: security-scanner (assume exploitable), /security-review
- [x] T033 /tla on the verdict; Allium drift check
- [x] T034 findings recorded; register tick, archive, commit, push
