# Tasks — 011

- [x] T001 Port `scripts/drive-sync.sh`; readonly accepts the four query modes; strip SC-ids
- [x] T002 Port the H7bo gate; four query modes; value-anchored handle derivation; EXCLUDED = 4
- [x] T003 `test-template-autosync-stranded.sh` through `drive_sync` (absolute DRIVE_SYNC_SCRIPT)
- [x] T004 `test-template-autosync-owed.sh` through `drive_sync` (DRIVE_SYNC_CWD, both sites)
- [x] T005 `test-template-autosync-eol.sh` through `drive_sync` (two sync sites; the hook site stays)
- [x] T006 `test-template-autosync-unlisted.sh` through `drive_sync` (six sites incl. era/sabotage copies)
- [x] T007 `test-core-owed-tick-guard.sh` `run_sync` through `drive_sync` (DRIVE_SYNC_TIMEOUT)
- [x] T008 `test-sync-count-honesty.sh` through `drive_sync` (six sites)
- [x] T009 Port `scripts/test-drive-sync.sh`; read-only arms for all four modes
- [x] T010 Merge the gate harness: 010 interlock arms kept, H7bo gate arms, AC-45..AC-58, F014 fixtures, exclusion pin
- [x] T011 CORE_SCRIPTS gains `drive-sync.sh test-drive-sync.sh`
- [x] T012 Verify: harnesses green; six drivers at baseline counts; ambient run against a clone leaves it identical; gate time interleaved
- [x] T013 TLA+ model + two falsifying controls
- [x] T014 Adversarial review (security-scanner + /security-review)
- [ ] T015 Delete row 026 with a history line; resolve F012/F014/F016 against this row; tick; commit; push
