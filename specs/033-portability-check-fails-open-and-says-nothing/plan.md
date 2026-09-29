# Plan — 033

1. Tests first: C40-C45 in `scripts/test-project-maintenance.sh` for SC-033-01..06. Confirm 01-04 red on HEAD.
2. `mkfix` gets passing portability stubs so C1-C36 test their own section.
3. Section 6c in `scripts/project-maintenance.sh`: name each missing script as `[SETUP]`; report exits other than 0/1 as could-not-run.
4. `test-skill-reachable.sh` maintenance fixture gets the same stubs (M1a counts findings exactly).
5. Verify: every self-test that runs `project-maintenance.sh`, plus `validate-portability.sh` on the changed scripts.
