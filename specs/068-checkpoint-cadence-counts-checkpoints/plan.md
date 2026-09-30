# Plan — 068

1. Tests first: `scripts/test-checkpoint-cadence.sh` with fixture registers for AC1–AC7, run
   against the engine path before it exists (red), plus orientation and project-maintenance cases.
2. Engine: `scripts/checkpoint-cadence.sh` (bash + awk), marked regions `skip-checkpoint`,
   `skip-carved`, `due-at-least` for the sabotage arms.
3. Readers: orientation hook and project-maintenance call the engine; drop `DONE % 5`.
4. Ship: add both files to CORE_SCRIPTS; rule text says "feature specs since the last checkpoint".
5. Verify: harness + sabotage, test-pipeline-hooks, test-project-maintenance, autosync unlisted
   check, `/bin/bash -n`.
