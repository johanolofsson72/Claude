# Plan — 038

1. Tests first: K29 in `scripts/test-project-freshness.sh` for SC-038-01..07. Confirm 03/04/06 red on HEAD.
2. A `run_trufflehog` helper in `project-freshness.sh` section 1: capture exit and stderr, branch 0 / 183 / other, used by both call sites.
3. Verify: the freshness self-test, `validate-portability.sh` on the changed script, the maintenance self-test (it runs freshness stubs).
