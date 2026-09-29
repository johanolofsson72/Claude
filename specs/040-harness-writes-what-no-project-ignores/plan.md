# Plan — 040

1. Tests first: `scripts/test-harness-gitignore.sh`, helper arms (SC-040-01..11, 15) against fixture repos, sync arms (SC-040-12..14) through `drive-sync.sh`, the template-dogfood check, and D's falsification (SC-040-16). Confirm red on HEAD.
2. `scripts/harness-gitignore.sh`: the `pattern%reason` list, `--list`, `--apply`/`--check` (awk splits the file into before/block/after, refuses malformed pairings, temp file + mv), `--tracked` (`git ls-files -ci --exclude-from`, collapsed in awk).
3. `template-autosync.sh`: add both scripts to CORE_SCRIPTS, run the helper before the check-block exit, `report_tracked` at the three exits.
4. `test-runtime-markers-ignored.sh`: D reads the helper, `covered_by` handles unanchored patterns, MACHINE_LOCAL gains five paths, fixtures ship a stub helper.
5. Docs: SKILL.md 3a and sync-prompt.md point at the helper. Template `.gitignore` gets the block, with the duplicated managed lines moved into it.
6. Verify: new test, markers test + self-test, the autosync suites, sync-prompt parity, portability check, a read-only `--check`/`--tracked` sweep over ~/repos.
