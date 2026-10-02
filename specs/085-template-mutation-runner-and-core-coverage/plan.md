# Plan — 085

1. **Runner** `scripts/run-mutation-gate.sh`: bash front end (args, tool checks, snapshot, worktrees,
   trap, baseline, worker pool, timeouts) and one embedded Python program with three verbs:
   `sites` (find sites, sample, `--lines`), `apply` (rewrite one site in a worktree file) and
   `report` (per-module lines, survivors, `mutation score`, the JSON written via temp + rename).
   Workers are background bash subshells, each owning one worktree, pulling mutant ids from a
   shared list by index (`id % jobs`), writing one verdict file per mutant.
2. **Self-test** `scripts/test-run-mutation-gate.sh`: fixture repo with a tiny module, a killing
   test, a weak test, a sleeping test and a red test; `MUTATION_TARGETS` points at it. Arms for
   085-AC-2 and 085-AC-4, sites/heredoc/comment/equivalent filtering, `--lines`, arguments, seed
   reproducibility, JSON shape. `--sabotage` applies anchored mutants to the runner and expects red.
3. **R3** re-measure every F048/F049/F071/F072 site with `--lines` at today's line numbers; for
   each survivor, write an arm in the module's existing self-test or mark it equivalent.
4. **R4** F073: time the H2 mutant alone (in progress at spec time).
5. **R5** `maintenance_ledger.py` readiness plus arms in `test-maintenance-ledger.sh` (085-AC-5).
6. **R2** run `project-maintenance.sh --full` in the template; confirm stamp and ledger (085-AC-1).
7. Docs: testing.md / workflows note that the template has its own runner; humanizer pass.
8. Verify: full suite via `.claude/.suite-command`, a default runner pass, bash 3.2 parse, Linux
   container run of the new self-test, adversarial review, /security-review, /tla.
