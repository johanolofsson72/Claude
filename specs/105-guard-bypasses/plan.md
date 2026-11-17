# Plan — 105

| R | Files | Test |
|---|---|---|
| R1 | `trust-anchor-guard-hook.sh` GIT_META verbs; `guard-lib.sh` walk fallback (no `.git` at a registered root) | `test-trust-anchor-guard.sh`, `test-guard-lib.sh` [105-R1], 105-AC-1, 105-AC-2 |
| R2 | `trust-anchor-guard-hook.sh` notice-dir and git-dir-substitution text rules | `test-trust-anchor-guard.sh` [105-R2], 105-AC-1 |
| R3 | `guard-lib.sh` `_guard_notice_base`; `harness-state-gc.sh` sweep | `test-guard-lib.sh`, `test-harness-state-gc.sh` [105-R3] |
| R4 | `trust-anchor-guard-hook.sh` PATH-directory writes (pre-check + verdict) | `test-trust-anchor-guard.sh` [105-R4], 105-AC-3 |
| R5 | `template-identity.sh` `_ti_git` | `test-template-identity.sh` [105-R5] |
| R6 | `trust-anchor-guard-hook.sh` parse check of scripts/*.sh, *.py | `test-trust-anchor-guard.sh` [105-R6], 105-AC-3 |
| R7 | `settings_guard.py` split_commands input redirect, runner names, handed-on names | `test-settings-edit-guard.sh` [105-R7], 105-AC-4 |
| R8 | `settings_guard.py` installer word + nested re-judge; `install-guard-notice-mod.sh` `--accept` pin | `test-settings-edit-guard.sh`, `test-guard-notice-mod.sh` [105-R8] |
| R9 | `acceptance_cases.py` `record_answers`, `answer_bound` spec-bound tokens | `test-acceptance-cases.sh` [105-R9], 105-AC-5 |
| R10 | `acceptance_cases.py` `check`, `_add_commit --topo-order` | `test-acceptance-cases.sh` [105-R10] |
| R11 | `hook_audit.py` wiring audit | `test-validate-hooks.sh` [105-R11] |
| R12 | headers, mod doc; `finding.sh` closes the row's findings | — |
| R13 | `guard-precheck.sh` walk ends by depth | `test-guard-canonical-paths.sh` [105-R13] |

Order: R13 (done, blocks the rest) → tests first per R → guard-lib (R1, R3) → trust-anchor (R1, R2, R4, R6;
`bash -n` after every edit, no backtick in its python program) → template-identity (R5) → settings guard
(R7, R8) → installer pin (R8) → acceptance (R9, R10) → hook audit (R11) → headers → suite, bench,
mutation, adversarial review, /tla.
