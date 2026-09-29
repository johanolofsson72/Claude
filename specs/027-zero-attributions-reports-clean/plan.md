# Plan — 027

1. Tests first: five `--carves` arms in `test-register-convergence.sh`; confirm the new ones are red on HEAD.
2. `carve_audit.py`: count ticked rows; split the no-attribution case into unmeasurable (exit 3) / too young (exit 0).
3. `project-maintenance.sh` §6b: branch on rc 3 and on "could not run".
4. `register-convergence.sh` help + `carve-budget.md` §4b.
5. Verify: the test file is green; `--carves` on the template exits 3; `project-maintenance.sh` shows the finding.
