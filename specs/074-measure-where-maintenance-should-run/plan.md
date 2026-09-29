# Plan — 074

1. `scripts/maintenance_ledger.py`: `run JOB -- CMD...` (subprocess, inherit stdio, getrusage, append) and `report [--all] [--ledger PATH]`.
2. `project-maintenance.sh`: a `measured JOB CMD...` shell function that routes through the ledger when python3 is present; wrap the six jobs and record the `pass`.
3. `scripts/test-maintenance-ledger.sh`: fixture-only self-test.
4. CORE list: add both files.
5. `.claude/docs/workload-placement.md`.
6. Verify: new test, existing maintenance tests, one real `--full`, humanizer on the doc.
