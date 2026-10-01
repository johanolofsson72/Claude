# Run log — 020-quality-gate-hooks-unwired-for-latency-we-no-longer-pay

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-10-01 · unheld: developer had Ollama re-enabled (LaunchAgent, loopback) and LOCAL_LLM_DISABLE removed from ~/.claude/settings.json; this session still carries the old env (=1) — tests run hooks with LOCAL_LLM_DISABLE=0
- 2026-10-01 · spec + interview (20: 16 auto, 4 developer overflow incl. 2 threat) + AC-1..4 confirmed + clarify (4 auto) + threat model
- 2026-10-01 · first real bench: 10 nightly / 5 off, but secret-scan, async-audit (and a clean pair) never reached the model — corpus defects, not misses; bench now refuses unfired seeded defects and runs each fixture 3x (temperature 0.2)
- 2026-10-01 · adversarial scan 8 findings + code review 11 + 5 suggestions: all fixed except review #10 (monorepo root) dismissed — maintenance-due.sh and project-maintenance.sh both resolve the git toplevel, so table, state and banner agree
- 2026-10-01 · second bench had a 0.4 s median everywhere: the 3 runs shared one cache (runs 2-3 were cache hits) — fresh cache per call; third bench is the committed table: 13 nightly, 2 off (dockerfile-review 2/2 false flags, plan-feasibility 1/2 caught)
- 2026-10-01 · real pass on this repo: 50 files in ~1 min, 11 flags, 155 skipped over the cap; banner line verified at SessionStart (--brief)
- 2026-10-01 · tla: PassLock.tla GAP-1 (two passes take over one stale pid lock) -> developer: fix now; OS lock (flock/msvcrt), PassLockOS.tla clean (54 states). Allium drift D1/D2 -> spec updated (developer)
- 2026-10-01 · /security-review: nothing >= 8
