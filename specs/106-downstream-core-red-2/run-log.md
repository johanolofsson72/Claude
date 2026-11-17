# Run log — 106-downstream-core-red-2

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-11-17 · baseline: template 92/94 (owed-tick flaky in parallel, fixture-map-ids NOT RUN); agentcrm 11 red, billing 6 red (scratchpad rungates.sh/mkds.sh)
- 2026-11-17 · interview 18 auto + Q19/Q20 developer (ship docs+rule; refuse exit 0)
- 2026-11-17T15:07Z · adversarial review: #1 decision docs kept out of RULE_DOCS (parity lists them), #2 status failure = unreadable, #3 walk continues, #6 --tracked exit 4, #8 mktemp fallback; #4 #5 #7 #9 held
- 2026-11-17T15:22Z · sandbox rerun after review fixes: agentcrm 11→8, billing 6→2 red; all left project-owned (F275) or recorded (F271, F272)
- 2026-11-17T15:37Z · mutation 86.4% (2 equivalents marked), line 1387 100% on default table; simplify applied A B D E M N, skipped L (template_identity says project in mutation copies), redesigns → F276
- 2026-11-17T16:39Z · suite: 96/97 green; tlc-cleanup AC7 timing flake under load (green alone, finding); sigpipe lint fixed in ships test
