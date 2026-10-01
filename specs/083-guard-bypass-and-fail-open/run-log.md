# Run log — 083-guard-bypass-and-fail-open

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-10-01T14:11Z · spec + threat model + interview (24: 21 auto, 3 developer overflow O1-O3); AC-1..5 confirmed as written; clarify 6 auto; allium 0 errors; plan + tasks
- 2026-10-01T14:42Z · impl: guard-lib + 3 fail-closed guards + core-machinery/tick/bash-write + destructive + sensitive guards + retire + R11; new tests 45/55/81/55/26 green; dogfood found 2 sensitive false positives (glob **, heredoc prose) fixed; tla GuardVerdict 192 states holds, exit-1 variant violates CliHonoursDeny; GAP-1 classifier rc2 silent in core-machinery/tick
- 2026-10-01T15:10Z · adversarial review 15 findings (PoC-verified): fixed 1-12,14, parts of 13/15; recorded F081-F085 (+F086 stryker S1 env, fails at HEAD); GAP-1 fixed (developer) + tests; spec amended
- 2026-10-01T15:15Z · /security-review: 2 findings (lnk/.. canon mismatch with CLI; ?/* glob precheck) fixed + arms; new tests 45/75/71/106/26 green
