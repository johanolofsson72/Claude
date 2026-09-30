# Plan — 065

1. Tests first: `scripts/test-install-nightly-maintenance.sh` with a stub `crontab` (file-backed),
   AC1-AC11. Run on HEAD, see the fixed behaviours red.
2. `install-nightly-maintenance.sh`: PATH capture + hygiene, quoting helper, `%`/newline refusal,
   log-first line with heartbeat, `sh -n` pre-check via `NIGHTLY_PARSE_SHELL`, tool report, stale flag
   in `--list`.
3. Add the test to the core list in `template-autosync.sh`.
4. Verify: suite green, `/bin/bash -n` (3.2), `--dry-run` on this repo.
