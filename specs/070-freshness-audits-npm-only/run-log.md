# Run log — 070-freshness-audits-npm-only

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-30T14:52Z · harness 194/194 macOS bash 3.2, 186/186 alpine (12/12 spec-070 asserts), red 22 before; sabotage lockfile-rule + not-scanned-join both red; real ekofak run names backend/pom.xml UNCHECKED; diagnosis was half-stale (osv+dotnet passes already existed)
