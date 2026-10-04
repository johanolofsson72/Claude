# Plan — 099

| R | Files | Test |
|---|---|---|
| R1 | `scripts/project-maintenance.sh` §6e (exit 77 → precondition skip, failure text names both ways out), header comment | `scripts/test-project-maintenance.sh` [099-R1] arms |
| R2 | `scripts/carve_audit.py` (parse `Carve accepted:`, accepted/over/malformed), `project-maintenance.sh` §6b text, `.claude/docs/carve-budget-rationale.md` | `scripts/test-register-convergence.sh` [099-R2] arms |
| R3 | `.claude/rules/{spec-interview,spec-register,feature-pipeline,carve-budget,spec-hardening,github-actions}.md` → their `-rationale.md`; `scripts/context-budget.sh` split line + synced message; `scripts/context-budget.baseline` | `scripts/test-context-budget.sh` [099-R3] arms + template rules cap |
| R4 | `scripts/archive-completed-rows.sh` (verbatim-line membership, honest counts), header comment | `scripts/test-archive-completed-rows.sh` [099-R4] arms |
| R5 | `.gitignore` (`specs/*/tla/states/`), drop 098's committed state files | — |

Order: R4 → R2 → R1 → R3 (rule trim last, measured) → R5 → converge, simplify, touched suites, full
self-test sweep, archive, tick, commit, push.
