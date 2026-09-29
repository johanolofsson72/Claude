# Plan — 041

1. Tests first: `scripts/test-validate-rule-citations.sh`, fixture arms SC-A..K, the real repo (SC-L), the rule shape (SC-M) and `--list-rules` (SC-N). Confirm red on HEAD.
2. `scripts/validate-rule-citations.sh`: bash wrapper, python3 scan over `git ls-files` minus `specs/`; missing path, fixture exemption, trap resolution over a two-line window, exit 0/1/2/3.
3. `.claude/rules/mutation-timeouts.md`: five traps, path-scoped, evidence per trap.
4. `template-autosync.sh`: rule into CORE_RULES, both scripts into CORE_SCRIPTS.
5. Pointers: `spec-hardening.md` mutation gate, `testing.md` mutation section.
6. Verify: new test, hand mutations, portability check, autosync unlisted/owed tests, humanizer on prose.
