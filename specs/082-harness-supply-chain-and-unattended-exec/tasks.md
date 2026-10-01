# Tasks — 082 harness supply chain and unattended execution

## Phase 1 — tests first (each names its AC/R)
- [x] T001 test-template-autosync-supply-chain.sh: R1 exact-SHA URL, R2 pin valid/invalid/clone-match/fallback, R3 dirty refused + overrides (082-AC-1), R4 symlink skipped
- [x] T002 test-maintenance-trust.sh: R5 untrusted skip + finding + unstamped, --trust then runs (082-AC-2), mutation gate, --trust+--unattended exit 2, derived command needs no trust; R7 guard timeout reads UNCHECKED
- [x] T003 test-lane-catchup.sh: R9 keeps credential denies, removes others, backup, atomic write, malformed JSON untouched (082-AC-3)
- [x] T004 test-prune-agent-worktrees.sh: R10 detached unmerged kept, untracked kept, merged clean removed, agent-memory-only removed (082-AC-4)
- [x] T005 test-local-llm-host.sh: R13 loopback matrix + opt-in (082-AC-5), quality_gates.py + register-similarity.sh, R14 every emitting hook labelled, R15 pins present
- [x] T006 extend test-stryker-guard.sh (R7 matcher equivalence, pathological glob, R8), test-maintenance-ledger.sh (R11), test-install-nightly-maintenance.sh (R6); add test-update-template.sh (R12)

## Phase 2 — implementation
- [x] T010 template-autosync.sh R1–R4
- [x] T011 project-maintenance.sh R5 + R7 bounding
- [x] T012 install-nightly-maintenance.sh R6
- [x] T013 stryker_guard.py R7 matcher + R8
- [x] T014 lane-catchup.sh R9
- [x] T015 prune-agent-worktrees.sh R10
- [x] T016 maintenance_ledger.py R11
- [x] T017 update-template.sh R12
- [x] T018 local-llm-detect.sh, quality_gates.py, register-similarity.sh R13; 38 hooks R14
- [x] T019 sync-prompt.md + tla SKILL.md R15
- [x] T020 CORE_SCRIPTS / TEMPLATE_ONLY_SCRIPTS registration

## Phase 3 — docs and verification
- [x] T030 docs R16 (humanizer pass)
- [x] T031 full template suite green; adversarial review (security-scanner, /security-review); threat-model residuals final
- [x] T032 /tla on the trust/prune/sync decisions; Allium drift check
