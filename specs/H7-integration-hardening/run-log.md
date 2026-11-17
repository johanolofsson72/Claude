# Run log — H7-integration-hardening

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-11-17T09:19Z · 2026-11-17 start: suite via project-maintenance.sh --full --suite (log scratchpad/h7-suite.log); mutation after suite; scanner sweep over 100-104 in parallel.
- 2026-11-17T09:24Z · §2 done: freshness clean; scanner 10 items -> F247-F255 recorded, item 5 (F235 twin check passes on jq error) fixed in place in test-hook-channels.sh. §3 n/a. §4 pending: MUTATION_TARGETS=scratchpad/h7-targets.txt (autosync, template-identity, validate-fixture-map-ids), seed 7, after suite.
- 2026-11-17T10:11Z · suite 2026-11-17 green + stamped (exit 1 = hygiene only). §4: default 88.0% (13 survivors) + spot-check seed 7 17/20 = 85.0% -> F256 F257. Next: checkpoint.md, commit, tick, push, summary.
