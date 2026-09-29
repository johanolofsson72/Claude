# Run log — 040-harness-writes-what-no-project-ignores

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-29T18:00Z · specify · spec.md + interview.md (20 auto) written
- 2026-09-29T18:06Z · spec 040: harness-gitignore.sh owns a marker block in .gitignore, sync applies it + reports [tracked]; 87 arms red on HEAD, 12/12 mutations killed; sweep: 39 of 45 projects track machine-local files
