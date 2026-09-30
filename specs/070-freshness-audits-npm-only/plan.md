# Plan — 070

1. Tests first: new cases in `scripts/test-project-freshness.sh` for AC1–AC8 against the current
   script (red), then the sabotage arms (AC9) via sed over marked regions.
2. Script: pass 6 `dependency coverage` after pass 5, reading `OSV_RC` / osv presence from pass 4.
   A `find` with the shared exclusions + ecosystem build dirs, the git-ignore oracle, and a
   `lock_for` helper that walks from the manifest's dir up to `$ROOT`. Marked regions
   `lockfile-rule` and `not-scanned-join` for the sabotage arms. Rename `Deps:` → `npm:`,
   renumber headers to `/6`, widen the osv skip line, update the header comment.
3. Verify: harness + sabotage, `/bin/bash -n` (3.2), the real script against ekofak (Maven) and
   this repo, and a Linux container run of the harness.
