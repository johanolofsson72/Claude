# Plan — 052

1. Tests first: C88-C97 in `scripts/test-project-maintenance.sh` (AC1-AC9); run, see them red on HEAD.
2. `project-maintenance.sh` new §6e: loop `scripts/check-*.sh`, skip marker, timeout, `[RATCHET]` findings, notes.
3. A shared `dotnet_solutions` helper near the top. §5 refuses a bare `dotnet stryker` when it lists
   more than one. §7 refuses a detected `dotnet test` the same way.
4. Header usage lines.
5. Verify: full maintenance test file, `/bin/bash -n` (3.2), and a live pass on this repo.
