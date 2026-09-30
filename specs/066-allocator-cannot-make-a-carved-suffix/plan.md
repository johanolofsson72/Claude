# Plan — 066

1. Tests first: extend `scripts/test-next-register-id.sh` with AC1-AC13. Run on HEAD, see them red.
2. `next-register-id.sh`: parse `--suffix`, reject flag conflicts and malformed parents in bash,
   add a `suffix` branch in the python block (parent known, single-letter children, append, a-z bound).
3. Help text, the rule line in `.claude/rules/spec-register.md`, the rationale doc line.
4. Verify: test suite green, `/bin/bash -n` (3.2), a live run on this register.
