# Run log — 075-place-heavy-jobs-local-or-cloud

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-10-01T04:45Z · allium:elicit · spec.allium written
- 2026-10-01T04:45Z · spec + interview (23: 19 auto, 4 overflow auto-answered conservatively — developer asleep, confirm in morning) + clarify (4 auto) + allium (2 open questions, surfaced at stop)
- 2026-10-01T05:46Z · implemented: workload-placement.sh/.tsv, --placed, due banner place, --stamp-as, cloud-setup.sh, cloud-maintenance.sh (plumbing publish, strict pull); test-workload-placement 95/95; existing suites green
- 2026-10-01T05:46Z · adversarial review (security-scanner): 1 high + 3 medium + 3 low, all fixed in place; /security-review: 1 medium (int64 overflow past the count check), fixed
- 2026-10-01T05:46Z · sabotage 27/29 killed; 2 survivors equivalent (second layer: python date parse, maintenance-due job list)
- 2026-10-01T05:46Z · agentcrm Stryker local: >1h40m, 4 parallel testhosts ~4.4 GB each (~17 GB tree) — over the 12 GB VM ceiling at Mac concurrency
- 2026-10-01T06:09Z · decided: every job local (Stryker over the 12 GB ceiling at Mac concurrency); batch stopped at its 2 h limit with no mutation ledger line; tla skipped (light track, linear state); allium 2 open questions surfaced at stop
- 2026-10-01T06:22Z · developer 2026-10-01: Q20-Q23 confirmed; allium open questions -> fix now (cloud proof run + setup-script test, both started by the developer in claude.ai)
- 2026-10-01T06:25Z · proof-run prep stopped: agentcrm main is 26 behind origin and ff-pull collides with uncommitted specs/SCENARIOS*.md; agentcrm stryker-config.json has concurrency 4 (= the 4 testhosts, ~17 GB) — set 2 for the proof
