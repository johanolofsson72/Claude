# Run log — 047-stryker-spans-fail-silently-and-score-well

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-30T09:07Z · G21 (dotnet test after Stryker stub stopped) failed once with deny, not reproduced in 6 reruns; expect() now prints the reason on mismatch
- 2026-09-30T10:40Z · 047 done: guard 46/46, maintenance 186/186 (C35 red upstream = F053); 43/43 hand mutants; adversarial 10 findings, 9 fixed, L4 kept; /security-review clean; simplify applied, F051/F052 recorded
