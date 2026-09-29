# Plan — 017 canary and row budget do not compose

1. `scripts/register-bytes.sh`: one LC_ALL=C awk pass that splits the file into rows / history /
   prose, counts over-budget rows and history entries, and prints the `move=` lines (R1–R3).
2. `scripts/test-register-bytes.sh`: arithmetic, each move rule at both sides of its threshold,
   continuation lines, CRLF, missing file, usage errors.
3. Orientation hook: the INDEX.md branch asks the helper; with moves it prints the breakdown and
   moves, with none a `SIZE_NOTE` outside ACTIONABLE; if the helper fails it uses the old text (R4).
4. project-maintenance.sh: the same split for the INDEX.md `[CONTEXT-COST]` line; compliant → `note` (R5).
5. Canary test cases (A2), CORE_SCRIPTS + core-gates partition (R8), rule bullet (R7).
6. Live check on agentcrm, msroute and the template (A3); run the touched suites (A4).
7. Finding: ticked-row fold, with the 13-consumer evidence. Register tick, archive the row, push.
