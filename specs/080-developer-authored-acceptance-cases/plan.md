# 080 — plan

1. `scripts/acceptance_cases.py` — the one parser (64 KB cap, `## AC-<n> — title`, Given/When/Then with
   continuation lines, numbering 1..N, band 3-5, Confirmed line), the digest (SHA-256 of the
   normalised cases, 12 hex), test-path recognition, the coverage scan (`git grep -E` over tracked
   and untracked files, 5 s timeout → fail open, test paths only), the digest-keyed cache under
   `.claude/state/acceptance/`, and `gate()` returning allow/deny plus the reason. CLI subcommands
   `check`, `digest`, `confirm`, `coverage`, `is-test`. Python 3 stdlib only (R1-R5, O3, O6).
2. `scripts/acceptance-cases.sh` — bash wrapper with the `--check/--digest/--confirm/--coverage` flags (R3).
3. `scripts/spec_active.py` — `hardened` in `resolve()` (R6).
4. `scripts/spec-interview-guard-hook.sh` — after the interview count passes, import the module and
   call `gate()`; exit 96 carries the deny reason (R4-R8). Unreadable acceptance.md denies; a crash
   inside the scan allows.
5. `scripts/test-acceptance-cases.sh` — written first: one block per 080-AC-n, then unit tests of the
   parser/digest/test-path rules and the destructive set. `test-pipeline-hooks.sh` interview
   fixtures move to a light row so they keep testing only the count.
6. Rules/docs: `spec-interview.md` short section, `spec-register.md` summary field,
   `spec-interview-rationale.md` and `testing.md` long form (R9).
7. CORE: `acceptance_cases.py`, `acceptance-cases.sh`, `test-acceptance-cases.sh` (R10).
8. Hardening: threat model (spec.md), security-scanner adversarial pass, `/security-review`, sabotage set
   in scratchpad (Stryker has no bash/python target here; proxy as in 077/075), timing measurement.
