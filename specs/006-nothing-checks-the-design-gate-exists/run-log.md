# Run log — 006-nothing-checks-the-design-gate-exists

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-29T05:40Z · 006: 38 self-tests; 10 mutations all killed after fixing M1 (a non-exec freshness stub masked add->note). Clarify auto-picked 3; spec-only, no allium/tla/simplify.
