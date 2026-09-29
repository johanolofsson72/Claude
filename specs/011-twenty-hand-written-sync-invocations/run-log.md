# Run log — 011-twenty-hand-written-sync-invocations

One line per event. Not pipeline input.

- 2026-09-29T07:33Z · spec, interview (21 auto + 3 carried + 2 overflow answered 2026-09-29: cap 4, delete 026), allium (ported, 0 errors), plan, tasks; hardened by size trigger (11 CORE files)
- 2026-09-29T07:33Z · baseline: drivers 36/21/36/34/45/31, gate harness 84/0; consultpilot H7bo gate unmodified on this tree: 28 violations in 9 files
- 2026-09-29T07:33Z · analyze: H7bo gate still misses F014 /bin/bash, zsh, and a trailing '# --is-core' comment exempting a real call — port must close them (AC-6)
- 2026-09-29T07:40Z · T2 is live: unlisted.sh:253 SAB2=sabotaged-optout.sh (copy, no -autosync.sh name); consultpilot's gate caught :267 only by prefix accident ($SAB2 matched $SAB). Lexer is correct; census covers it
- 2026-09-29T07:57Z · gate sabotage: 14 mutations, 11 red first pass; M02 (here-string guard) + M05 (redirect skip) were dead code, removed; M08 (loose handle derivation) was untested, fixture added -> 12/12 red. Gate harness 161/0 (010 baseline 84), helper 59/0 with 12/12 arms
- 2026-09-29T08:11Z · gate rebuilt as one awk pass (was ~7 procs/file): CPU 0.6s vs old 1.1s; sabotage 14/14 red after adding AC-48b (definition inside an excluded file); harness 164/0; ambient CLAUDE_PROJECT_DIR run: 8 suites green, decoy clone byte-identical
- 2026-09-29T08:40Z · adversarial review: /security-review 0 findings; security-scanner 16 items, 14 gate repros + 2 helper repros all confirmed (exit 0 / rc 0 where 1/64 expected). Fixed in spec: 1-5,8,9,10,11,12,13,14,16 with fixtures AC-62 + helper J; gate sabotage 27/27, helper arms 15/15; gate harness 196/0, helper 72/0. Open for decision: #6 hook route, #7 invert rule
- 2026-09-29T09:13Z · findings stop: #6 hook route -> F018, #7 invert -> F019 (developer); Allium open question dismissed; invariant rewritten to 0 edits per compliant driver; F012, F014 resolved by 011
- 2026-09-29T09:25Z · /simplify: 4 reviewers; fixed CDPATH-unsafe helper path, dead script lookup, stale headers, HELPER_HARNESS_REL removed (harness uses a sed copy), AC-56 real broken-scanner probe, AC-60 one run, tick-guard gtimeout guard; found+fixed FP (word flushed in a quote frame lost its command); skipped readonly removal (Q18), behaviour-changing refactors. gate 199/0, sabotage 27/27
- 2026-09-29T09:27Z · ambient CDPATH at a decoy: harness entry cd resolves into the decoy (pre-existing, all self-tests) -> F020; decoy untouched. Ambient CLAUDE_PROJECT_DIR alone: 8 suites green on final code
