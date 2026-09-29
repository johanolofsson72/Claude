# Plan — 023

1. Seam: `TRUFFLEHOG_BIN` (`FRESHNESS_TRUFFLEHOG`) through `ensure_trufflehog` and both scan calls.
   Reword the trufflehog OK line and the SUMMARY (`Secrets:` = verified credentials).
2. `classify_key_blob` — one awk program on stdin → `FINDING<TAB>label`, `NOTE<TAB>label` or nothing
   (FR-04). `LC_ALL=C`, POSIX awk only.
3. `key_shape_scan` — collect candidates (git: rev-list --objects name filter + pickaxe paths +
   untracked; non-git: find + grep -l), size-gate, classify, dedup worst-per-path, locate, allow
   file, print, set KEYS_STATUS and FINDINGS (FR-02, 03, 05–08).
4. Sections renumbered to [n/5]; SUMMARY gains `Keys:`; header comment documents the arm.
5. Tests in `test-project-freshness.sh`: fixture git repos built at runtime (no key-shaped bytes
   committed to the template), every verdict + negatives + allow + spaces + history + untracked +
   non-git + leak assertion. Sabotage arms by hand (run-log).
6. Docs: spec-hardening rule + security doc mention of what the freshness secret scan covers.
7. Hardening: STRIDE (in spec), security-scanner adversarial pass, `/security-review`, reviewer pass,
   stress (rocky-size history, 5 MB blob, 2000 candidates), live fleet run.
