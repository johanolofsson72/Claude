# Run log — 039-core-guard-blocks-its-own-first-install

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-29T17:35Z · specify · spec.md written
- 2026-09-29T17:39Z · spec 039: guard allows a Write/Edit/MultiEdit whose result is byte-identical to the local template clone; fail closed otherwise; SC-039 6 red on HEAD, 36/36 after; F035 (Bash cp route still denied, no bytes)
