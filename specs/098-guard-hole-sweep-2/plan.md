# Plan — 098

| R | Files | Test |
|---|---|---|
| R1 | `scripts/trust-anchor-guard-hook.sh` pre-check uses `guard_precheck_link` | `test-trust-anchor-guard.sh` [098-R1], 098-AC-1 |
| R2 | `scripts/acceptance_cases.py`: `_committed_unchanged` removed, gate backs on `answer_bound` only, deny text | `test-acceptance-cases.sh` [098-R2], 098-AC-2 |
| R3 | `core-machinery-guard-hook.sh`, `core-owed-tick-guard-hook.sh`: missing sync in a synced project denies | `test-core-machinery-guard.sh`, `test-core-owed-tick-guard.sh` [098-R3], 098-AC-3 |
| R4 | `guard-lib.sh` `_guard_git` + `GUARD_GIT_UNSURE`; the three pipeline guards deny, the two CORE guards announce | `test-guard-lib.sh` [098-R4], 098-AC-4 |
| R5 | `run-mutation-gate.sh` `run_test` env allowlist, NOSYSTEM, pushInsteadOf, rc 137 | `test-run-mutation-gate.sh` [098-R5] |
| R6 | `guard-lib.sh` `guard_announce` stamp under the git dir; `harness-state-gc.sh` sweep | `test-guard-lib.sh` [098-R6], 098-AC-4 |
| R7 | `settings_guard.py` `split_commands(flow=)`, `_bash_verdict` runner check | `test-settings-edit-guard.sh` [098-R7], 098-AC-5 |
| R8 | `hook_audit.py` matcher check | `test-validate-hooks.sh` [098-R8] |
| R9 | headers; `finding.sh` closes F139–F144 F155 F159 | — |
| R10 | sabotage arms; mutation gate on `settings_guard.py`, `acceptance_cases.py`, `hook_audit.py` | `run-mutation-gate.sh` |

Order: tests first per R → guard-lib (R4, R6) → pipeline + CORE guard consumers (R3, R4) → trust-anchor
(R1) → acceptance (R2) → settings guard (R7) → hook audit (R8) → mutation runner (R5) → headers →
suite, bench, mutation, adversarial review, /tla.
