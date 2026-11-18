# Plan — 109

| R | Where | Check |
|---|---|---|
| R1 | `run-mutation-gate.sh` `sites()`: parse `mutant-equivalent[...]`, filter per site, stale selector → exit 2; `template-autosync.sh` `[reverted]` line → `[&&]` | arm `arm_per_site_marker`; sabotage |
| R2 | `cmd_sites` `--lines` branch: marked-only lines noted and dropped; nothing left → exit 2 | arm `arm_lines_marked`; sabotage |
| R3 | `py_sites()` via tokenize; `sites()` dispatches on `.py`; `apply` unchanged (line, column, text); default table + 4 modules | arm `arm_python_sites`; sabotage |
| R4 | `portability_audit.py` CHECKS `find -newer@` | `test-portability-audit.sh` cases |
| R5 | tests in each module's suite; per-site markers where a mutant is equivalent; table + hook-notice, trust-anchor | `--lines` re-measure per survivor; full gate after |
| R6 | `test-run-mutation-gate.sh` | arms + `--sabotage` |
