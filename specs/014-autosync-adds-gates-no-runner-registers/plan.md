# Plan — 014 autosync adds gates, no runner registers them

1. Measure (R8): run all 53 CORE gate-shaped scripts in the template (no args, stdin closed) and
   record rc + runtime. Read the header of each one that is not green-and-standalone.
2. `scripts/core-gates.sh` (shape + non-gate table, reasons from step 1); it and
   `test-core-gates.sh` added to `CORE_SCRIPTS`.
3. (Dropped: no new query mode. The query-mode cap of four is a developer decision.)
4. `scripts/test-core-gates.sh`: partition checks R6a–e plus sabotage arms (R6f) on a
   copy of `template-autosync.sh` in a mktemp dir.
5. Verify A1–A5 and run the suites of the touched scripts.
6. Findings: consultpilot adoption (R-adopt) + default projects run no CORE gates. Mark F004 fixed.
7. Register: tick, archive row, run-log, commit, push.
