# Plan — 047

1. `scripts/stryker_guard.py`: `patterns <root> <source> <pattern>...`, `configs <root>`, `command <root> <cmd>`, `live <root>`. TSV out.
2. Tests first: `scripts/test-stryker-guard.sh` (helper + hook, real processes for live) and arms C63–C70 in `scripts/test-project-maintenance.sh`. Red on HEAD.
3. `project-maintenance.sh` §5: pattern check every pass; live refusal before `--full`.
4. `scripts/stryker-guard-hook.sh` + wiring in `.claude/settings.json` (PreToolUse Bash).
5. `.claude/docs/testing.md`: three facts.
6. Hardening: stress arms, hand mutants (≥80%), security-scanner adversarial pass, /security-review.
7. Verify: both suites, portability check, hook wiring tests.
