# 020 — plan

1. Corpus `scripts/fixtures/quality-gates/<hook>/` (2 bad + 2 clean per hook, trigger-matching names, `expect.tsv`) (R1).
2. `scripts/quality_gates.py` — one module: model reachability (loopback check), corpus + table I/O, flag-line parsing, scoring, the verdict rule, the changed-file walk with caps, the report, secret masking, the lock. CLI: `bench`, `pass`, `banner`. `scripts/quality-gate-bench.sh` and `scripts/quality-gate-pass.sh` are thin wrappers (R2-R4).
3. `scripts/quality-gates.tsv` — written by a real bench run on this machine (R2, R3).
4. `maintenance-due.sh` banner line via `quality_gates.py banner` (R5); `project-maintenance.sh --full` step + `--bench-quality-gates` (R6).
5. `.claude/docs/local-llm.md` section (R7); CORE list (R8).
6. `scripts/test-quality-gates.sh` — 020-AC-1..4 first, with stub hooks and a stub `/api/tags` server; then parser, caps, lock, masking, loopback refusal. Sabotage set; adversarial + `/security-review`.
