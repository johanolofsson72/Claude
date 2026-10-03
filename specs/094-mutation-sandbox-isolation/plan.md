# Plan — 094

| R | Files | Test |
|---|---|---|
| R1–R3 | `scripts/run-mutation-gate.sh` (worker prep loop, `run_test`) | `scripts/test-run-mutation-gate.sh` new `arm_sandbox_home` + sabotage S13, S14 |
| R4 | `scripts/run-mutation-gate.sh` header | — |
| R5 | none | `bash scripts/test-hook-channels.sh` section 14 |

Verify: the runner's self-test and its sabotage mode, then a real baseline (`--sample 1` over the
default table), then the declared suite.
