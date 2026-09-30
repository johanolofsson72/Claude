# Run log — 065-nightly-cron-line-runs-blind

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-30T13:28Z · suite 32/32 (17 red on HEAD); 5 sabotages all caught; implement found BSD cron's 999-char MAX_COMMAND — PATH moved to a file, length refused (FR-07)
