# Plan — 078

1. Re-draw the sample: the six H1-named sites at today's line numbers plus six new operator
   mutants. Measure it against all 20 suites that mention the sync, in detached worktrees under
   `$HOME` (test-drive-sync is red outside it), driven from a bash script (not zsh; the H1 trap).
2. Classify each survivor: find the behaviour it changes, or prove it is equivalent.
3. Write `scripts/test-template-autosync-arms.sh`: one arm per non-equivalent survivor, with
   positive controls, plus `--sabotage` driven by an anchored mutant list.
4. List the suite in CORE_SCRIPTS.
5. Verify: arms green, sabotage all red, the full 12-mutant re-measure, no green suite turns red,
   bash 3.2 parse, Linux container run.
