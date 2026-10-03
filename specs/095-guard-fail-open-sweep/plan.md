# Plan — 095

| R | Files | Test |
|---|---|---|
| R1 | `scripts/settings_guard.py` (new `git_tree_verdict`), hook pre-check | `test-settings-edit-guard.sh` [095-R1] fixture repo, 095-AC-1 |
| R2 | `settings_guard.py` `GUARDED_KEYS` → safe list, `changed_keys`, hook reason text | [095-R2], 095-AC-2 |
| R3 | `settings_guard.py` `mcp_verdict`; `trust-anchor-guard-hook.sh` MCP scan; both pre-checks | [095-R3] in both tests, 095-AC-3 |
| R4 | `.claude/settings.json` matchers (developer applies) | `test-hook-channels.sh` matcher section, 095-AC-3 |
| R5 | `scripts/acceptance_cases.py` `_git`, scan env, backing timeout; `spec-interview-guard-hook.sh` announce | `test-acceptance-cases.sh` [095-R5] |
| R6 | `scripts/guard-lib.sh` walk | `test-guard-lib.sh` [095-R6]; spec-interview end to end, 095-AC-4 |
| R7 R8 | `settings_guard.py` `reads`, `bash_verdict`; `shell_glob.py` `sed_script_pure`; trust-anchor's trust option | [095-R7] [095-R8], 095-AC-5 |
| R9 | `scripts/bash_write_targets.py` sed | `test-bash-write-guard.sh` [095-R9] |
| R10 | `scripts/destructive_command.py` `judge_git_trust` | `test-trust-anchor-guard.sh` [095-R10], 095-AC-5 |
| R11 | `scripts/update-template.sh` REVIEW | `test-update-template.sh` [095-R11] |
| R12 | guard headers, `finding.sh --close` | — |
| R13 | sabotage arms; mutation gate on the changed modules | `run-mutation-gate.sh` |

Order: shared helper (sed parser) → settings guard (R2, R7, R8, R1, R3) → trust-anchor (R3, R8, R10) →
bash-write (R9) → acceptance (R5) → guard-lib (R6) → update-template (R11) → matchers (R4, developer)
→ suite, mutation, adversarial review, /tla.
