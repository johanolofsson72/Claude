# Run log — 023-secret-scan-misses-signing-material

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-29T14:22Z · specify+interview(20: 3 developer overflow, 17 auto)+clarify; allium skipped (pure classifier, rules as tests)
- 2026-09-29 — v1 caught both filed DP keys; code review + adversarial review found Ed25519 miss (threshold 120), per-path location bug, staged gap, 1 MiB downgrade, SIGPIPE false NOTE
- 2026-09-29 — v3: one cat-file --batch + one awk, location per blob, -z, --text under -diff; stress 2000 candidates 158 s → 4.2 s; fundit pickaxe 29 s (accepted)
- 2026-09-29 — tests 146/146; sabotage 30/30 killed (scratchpad sabotage.py, not in suite); /security-review: none ≥8
- 2026-09-29 — fleet: new real keys in ighweld-2026 (ssh.txt), caseflow (untracked DP ring), hireflow (.pfx) — reported to developer, not this spec's work
