# 075 — plan

1. `scripts/workload-placement.tsv` — the decided table (project override `.claude/workload-placement.tsv`) (R1, R2), filled from `maintenance_ledger.py report --all` after the 2026-10-01 measurement batch (agentcrm, ighweld-2026, iskvalp, rocky).
2. `scripts/workload-placement.sh` — one reader for the table: `--place JOB` prints local|cloud (exit 3 + message on an unknown place), `--here` prints where this process runs, `--list` prints the effective table. Bash 3.2, no python. Used by both scripts below so they cannot disagree.
3. `scripts/project-maintenance.sh --placed` — before each heavy job (similarity, mutation, suite) ask the reader; skip with one line, or refuse on unknown (R3).
4. `scripts/maintenance-due.sh` — mark cloud-placed due jobs "(Claude cloud)" and add the `--placed` / cloud lines (R4).
5. `scripts/cloud-setup.sh` — idempotent .NET SDK install via dotnet-install.sh when a solution exists and dotnet is missing (R5).
6. `scripts/cloud-maintenance.sh` — `run` (cloud guard, setup, pass with --full --suite --placed, publish) and `--pull` (fetch, import unseen, stamp, record) (R5, R6). Publish uses a temporary worktree so the session's checkout is never switched.
7. `spec-hardening.md` + rationale doc line; `workload-placement.md` to "decided" (R7).
8. CORE list in `template-autosync.sh` (R8).
9. `scripts/test-workload-placement.sh` — fixture repos with a bare remote; sabotage set in scratchpad.
