# Plan — 039

1. Tests first: new arms in `scripts/test-core-machinery-guard.sh` for SC-039-01..12, with a fixture template dir under `$WORK` passed as `CLAUDE_TEMPLATE_DIR` and `HOME` pointed away from the real clone. Confirm the allow arms red on HEAD.
2. `core-machinery-guard-hook.sh`: after RC=0, resolve the template (moved above the comparison), compute the resulting bytes in jq (`--rawfile` for the current file, split/join for replacement so offsets stay codepoint-safe), `cmp` against the template copy, allow on equal.
3. One line in the deny text (FR-08).
4. Verify: the guard self-test, `test-bash-write-guard.sh`, `validate-portability.sh` on the changed scripts.
