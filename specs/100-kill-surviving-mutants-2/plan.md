# Plan — 100

| R | Files | Check |
|---|---|---|
| R1 | `scripts/test-core-owed-tick-guard.sh`, `scripts/test-core-machinery-guard.sh`, `scripts/test-settings-edit-guard.sh`, `scripts/test-trust-anchor-guard.sh` (run helpers pass `$?` to `hook_verdict`) | suites green; F151 lines killed |
| R2 | the owning suite per module (see spec line map); `# mutant-equivalent:` markers on confirmed equivalents | `--lines` per site |
| R3 | none expected | — |
| R4 | `run-mutation-gate.sh --lines …` with the scratch `MUTATION_TARGETS` table | ≥ 95%, 0 timeouts |

Order: baseline `--lines` → R1 → per-survivor cases / markers → touched suites → re-measure →
simplify → full template suite → archive, tick, commit, push.
