# Plan — 102

| R | Files | Check |
|---|---|---|
| R1 | `scripts/template-autosync.sh` (scripts copy loop: non-.sh/.py CORE_SCRIPTS names by name) | sandbox: core-parity green; `[102]` autosync case |
| R2 | `scripts/test-local-llm-host.sh`, `scripts/test-sync-prompt-zsh.sh` (downstream skip) | sandbox green; template still runs the checks |
| R3 | `scripts/template-autosync.sh` (docs loop: drop web withholding, mobile writes own name too) | sandbox: validate-rule-citations 0 dangling |
| R4 | `scripts/validate-fixture-map-ids.sh` (owned set via `scenario_map_files`) | `[102]` split-layout case in test-fixture-map-ids.sh |
| R5 | `scripts/project-freshness.sh` (built-in allow), `.secret-shapes-allow` (drop two lines) | `[102]` case in test-project-freshness.sh; sandbox `--secrets` clean |
| R6 | the suites above, sandbox rerun | zero reds over 93 gates |

Hardening: threat model in spec.md; security-scanner adversarial pass on R5; mutation pass on the
changed lines; stress is n/a (two string compares per hit).

Order: R1 → R3 → R2 → R4 → R5 → tests → sandbox rerun → mutation → review → simplify → full suite → tick, commit, push.
