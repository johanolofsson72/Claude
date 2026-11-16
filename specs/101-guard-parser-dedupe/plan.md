# Plan — 101

| R | Files | Check |
|---|---|---|
| R1, R2 | `scripts/shell_glob.py` (`sed_script_words` pairs, `sed_args` on top), `scripts/sensitive_paths.py` (drop `_SED_PURE`, `sed_scripts`) | test-sensitive-file-guard.sh, test-bash-write-guard.sh, test-settings-edit-guard.sh green |
| R3 | `scripts/settings_guard.py` (`_bash_verdict` by_name per command, `pattern_indices` xargs only) | test-settings-edit-guard.sh + `[101]` cases |
| R4 | `scripts/sync-prompt.md` Step -1 | test-sync-prompt-bootstrap.sh |
| R5 | the three suites above | `[101]` cases, sabotage arm retargeted |

Order: R1/R2 → R3 → R4 → suites → mutation `--lines` → simplify → full suite → tick, commit, push.
