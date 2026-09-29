# Plan — 042

1. `scripts/lane_status.py`: `runnable(rows, ticked)` resolves each `needs` entry against the set of
   all row ids. An entry naming no row does not block. New `unresolved_needs(rows)` returns
   `(row id, entry)` for open rows (`[ ]`, `[/]`, `[!]`) whose `needs` names no row.
2. `render()`: after the runnable list, under the same gate (full, or multi-lane brief), print
   `  needs names no row: 012 → inget; …` when there is anything to print.
3. `scripts/test-lane-orientation.sh`: case 7 (known positives, blocking still blocks, mixed clause,
   typo, single-lane silence).
4. Hand mutants on the new branch; the test must kill each non-equivalent one.
