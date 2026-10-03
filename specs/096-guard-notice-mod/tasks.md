# Tasks — 096-guard-notice-mod

## Tests first
- [x] T001 lib.test.ts: fail-open classify (8 partitions), deny classify (6), Seen dedupe
- [x] T002 lib.test.ts: activeRow (8), maintenanceDue (5), bandText
- [x] T003 test-guard-notice-mod.sh: staged layout loads nothing; install, re-install, foreign refused, uninstall own/foreign, --target with a space, missing staged file; claude plugin validate
- [x] T004 test-settings-edit-guard.sh [096-R6]: installer refused on 4 spellings, cat allowed

## Implementation
- [x] T010 frontend-design pass for the toast and band text
- [x] T011 lib.ts
- [x] T012 register.tsx, types/index.d.ts, plugin.json.staged, hooks.json.staged
- [x] T013 scripts/install-guard-notice-mod.sh
- [x] T014 R6 in settings_guard.py and the hook pre-check
- [x] T015 docs (humanizer pass)

## Close
- [x] T020 converge + simplify; full template suite
- [x] T021 register tick, commit, push
