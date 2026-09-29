# Run log — 017-canary-and-row-budget-do-not-compose

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-29 · spec, interview (20 auto, 0 overflow), clarify (3 auto), plan, tasks; spec-only, not hardened; live: msroute 75% done rows 0 over budget, agentcrm 55% prose
- 2026-09-29 · impl: register-bytes.sh + test 51/51, 13 hand mutations 12 killed (CR survivor → CRLF-300 case added); prose inside the history section reclassified as prose (the canary fixture exposed it)
- 2026-09-29 · verify: canary suite green (+15 arms), maintenance 80/80, pipeline hooks 165/165, core-gates 22/22, unlisted 31/31, parity 8/8, portability clean; live copies: msroute info line, agentcrm prose→rows; F024 (ticked-row fold) recorded
