# Plan — 043

1. Tests first: arms C54–C60 in `scripts/test-project-maintenance.sh`; the stub `dotnet` writes a report. Confirm red on HEAD.
2. `project-maintenance.sh` section 5: marker before the run, find reports newer than it, python3 merge per mutant, list files under the limit; fold into the three scored branches; missing-report finding.
3. Contract comment: the report half.
4. Verify: full maintenance suite, hand mutations, portability check, autosync tests.
