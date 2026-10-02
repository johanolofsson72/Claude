# Run log — 085-template-mutation-runner-and-core-coverage

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-10-01T19:31Z · 085 runner + self-test (39 ok, sabotage 7/7) + ledger R5 done; F073 not a hang (189s solo, mutant survived: no --help case) -> case0-help kills it; --lines re-measure: fresh 4/11, maint 8/23, sync 2/9; 3 agents arming survivors
- 2026-10-01T21:18Z · specify · spec.md written
- 2026-10-02T04:12Z · interview · interview.md written
- 2026-10-02T04:12Z · specify · spec.md written
- 2026-10-02T04:12Z · allium:elicit · spec.allium written
- 2026-10-02T04:25Z · specify · spec.md written
- 2026-10-02T04:25Z · /security-review: 0 findings >=8; review #4 '/' guard never matched ('//' spelling) -> fixed + S12; TLC clean 1252 states; Linux: runner 57/57, ledger 58/58 (non-root+procps); suite running
