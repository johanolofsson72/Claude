# Tasks — 092 kill surviving mutants

## Phase 1 — tests (each names its line or its 092-AC)
- [x] T001 R1 no-marker fixtures in test-guard-canonical-paths.sh (092-AC-1)
- [x] T002 R2 hook_verdict rc argument + section 13 + rc-capturing helpers (092-AC-2)
- [x] T003 R3 four spec-interview deny routes at exit 0 (092-AC-2)
- [x] T004 R4 autosync cases: 938 2002 2310 2533 2613 3107 3526 3764
- [x] T005 R5 maintenance cases: 236 264 327 352 659 1081 1098 1150
- [x] T006 R6 traceability --dir; freshness bounded EOF case (092-AC-4)

## Phase 2 — production code
- [x] T010 not needed: no survivor was dead code (F137, F138 recorded instead)

## Phase 3 — verification
- [x] T020 every touched suite green alone
- [x] T021 R7 --lines re-measure ≥ 95%, no timeout (092-AC-3)
- [x] T022 full template suite
- [x] T023 adversarial review + /security-review
- [x] T024 /tla: skipped by its triviality gate — hook_verdict is a pure function, no state or concurrency
