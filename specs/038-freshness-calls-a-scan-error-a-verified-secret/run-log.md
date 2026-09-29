# Run log — 038-freshness-calls-a-scan-error-a-verified-secret

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-29T17:30Z · spec 038: real trufflehog 3.95.5 exits 1 on a no-commit repo, 183 on results; branch 0/183/other + --fail-on-scan-errors; K29 12 arms red on HEAD; F033 (maintenance reads NOT SCANNED as clean), F034 (PuTTY fixture trips own key scan)
