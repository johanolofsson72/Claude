# Run log — 044-traceability-gate-cannot-tell-zero-from-broken

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-30T00:00Z · spec 044: zero-refs refusal (exit 4, roots + file counts + scan stderr) and extractor stderr printed on partial reads; cases 41-45 red on HEAD then 50/50; 5 one-row fixtures needed an anchor reference; sabotage f now green (two defences), n/o red, 15 arms surgical
