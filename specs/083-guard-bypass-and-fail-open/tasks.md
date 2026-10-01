# Tasks — 083 guard bypass and fail-open

## Phase 1 — tests first (each names its AC/R)
- [x] T001 test-guard-lib.sh: R1 parser fallback, JSON escaping, canon matrix
- [x] T002 test-guard-fail-closed.sh: R2 no parser / malformed / no python3 (083-AC-1), R3 announce, R4 path matrix (083-AC-2), R5 nested scripts (083-AC-3), R6 split tick (083-AC-4), R7 cp byte-identical
- [x] T003 test-guard-exit-codes.sh: R8 sweep over every wired guard + sabotage arm
- [x] T004 test-destructive-command-guard.sh: R9 deny/allow matrix (083-AC-5)
- [x] T005 test-sensitive-file-guard.sh: R10 tools × paths, O1, size, unparseable, retire (083-AC-5)
- [x] T006 R11 arm: orientation hook notice with jq or python3 hidden, silent with both

## Phase 2 — implementation
- [x] T010 guard-lib.sh R1
- [x] T011 three pipeline guards R2 R4 R5
- [x] T012 core-machinery R3 R4; core-owed-tick R3 R4 R6
- [x] T013 bash-write-guard + bash_write_targets.py R3 R7
- [x] T014 destructive-command guard R9
- [x] T015 sensitive-file guard R10, settings.json, sync-core-hooks retire
- [x] T016 orientation hook R11
- [x] T017 CORE_SCRIPTS registration

## Phase 3 — docs and verification
- [x] T030 security.md R12 (humanizer pass)
- [x] T031 full template suite green; adversarial review (security-scanner, /security-review); threat-model residuals final
- [x] T032 /tla on the guard verdict decision; Allium drift check
