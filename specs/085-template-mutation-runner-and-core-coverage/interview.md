# Spec interview — 085-template-mutation-runner-and-core-coverage

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened (trigger 4, and the runner is a command the 082 nightly executes), so three policy questions go to the developer as overflow (O1–O3): the gate threshold, the sample's seed, and where the runner may write.

## Q1 — Scope boundary
**Q:** Which findings does 085 close?
**A (auto):** The mutation half of F047, and F048, F049, F058, F071, F072, F073, the ones the row names. The suite half of F047 was closed by d8cbd3f.

## Q2 — Scope boundary: what gets armed
**Q:** Does 085 arm every surviving operator site in the four modules, or the recorded ones?
**A (auto):** The recorded ones (F048, F049, F071, F072). Arming whole files is the open-ended task F071 warns about. The daily fresh sample keeps measuring the rest and each run's survivors become findings at the next checkpoint.

## Q3 — Primary actor and trigger
**Q:** Who runs the runner, and from where?
**A (auto):** `project-maintenance.sh --full` (attended, or the 082 nightly once the developer has trusted the runner's bytes), an integration checkpoint's mutation spot-check, and a developer re-measuring a survivor with `--lines`.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** `bash scripts/project-maintenance.sh --full` in the template prints a `[MUTATION]` result with a number, the ledger gains a `mutation` row, and the next SessionStart no longer lists "mutation kill rate — never run".

## Q5 — Data model
**Q:** What does the runner persist?
**A (auto):** One file, `.claude/state/mutation/mutation-report.json` (gitignored, overwritten per run), Stryker schema version 1: `files.<path>.mutants[]` with `id`, `mutatorName`, `replacement`, `location`, `status`, `statusReason`. Worktrees under the work dir are removed at exit and are not state.

## Q6 — Validation: what is a mutable site?
**Q:** Which lines are candidates?
**A (auto):** Lines outside comments and outside heredoc bodies (from a `<<WORD`/`<<'WORD'`/`<<-WORD` line to the line that is exactly the delimiter, leading tabs allowed for `<<-`). A token must stand alone (`-eq` bounded by spaces, `&&`/`||` bounded by spaces, `exit 0` followed by end, space, `;` or `}`). Lines marked `# mutant-equivalent:` are skipped.

## Q7 — Validation: arguments
**Q:** What is rejected at the command line?
**A (auto):** An unknown flag, a non-numeric `--sample`/`--jobs`/`--seed`, `--jobs 0`, a `--module` not in the target table, a `--lines` whose module is not in the table or whose line has no mutable site. Each is exit 2 with one line naming the bad argument.

## Q8 — The four states: success
**Q:** What is the success state?
**A (auto):** Per-module lines, survivors listed, `mutation score N%`, exit 0 when N ≥ break.

## Q9 — The four states: error
**Q:** What does an error look like?
**A (auto):** A specific line on stderr and exit 2: `run-mutation-gate: baseline red — <module>: <test> exit <rc>`, `run-mutation-gate: needs timeout or gtimeout`, `run-mutation-gate: not a git repository`. No score line is printed, so section 5 reports "failed to complete" rather than a number.

## Q10 — The four states: empty
**Q:** What if a module has fewer sites than the sample?
**A (auto):** All of its sites are used and the line says so (`12 requested, 7 sites`). A module with zero sites is exit 2: a table entry that mutates nothing is a configuration defect.

## Q11 — The four states: loading
**Q:** What does a long run show while it works?
**A (auto):** One progress line per finished mutant on stderr (`[17/48] killed template-autosync.sh:337`), so a terminal sees motion and the stdout contract stays clean.

## Q12 — Error semantics: a crashing test
**Q:** A test exits 127 because the mutant broke the script's syntax. Kill?
**A (auto):** Yes. Any non-zero exit that is not a timeout is a kill; a syntax-breaking mutant is a real kill (the test noticed). Stryker counts compile errors separately, but bash has no compile step.

## Q13 — Authorization
**Q:** Who may run it unattended?
**A (auto):** Only after the developer trusts its bytes with `project-maintenance.sh --trust` in their own terminal (082, 088). The runner adds no trust path of its own.

## Q14 — Concurrency
**Q:** Can two runs collide?
**A (auto):** Each run makes its own `mktemp -d` under the work dir and names its worktrees inside it, so two runs never share a worktree. The JSON report is written to a temp file and renamed into place, so a reader never sees half a report. Workers within one run each own one worktree; the mutated file is restored from the snapshot before the next mutant.

## Q15 — Integration points
**Q:** What does it touch?
**A (auto):** `git` (temp index, `write-tree`, `commit-tree`, `worktree add --detach`, `worktree remove`), `python3` (site finding, sampling, JSON), `timeout`/`gtimeout`, and the module self-tests. Section 5 of `project-maintenance.sh` reads its stdout and the JSON. Nothing goes to the network.

## Q16 — Edge cases: interrupted run
**Q:** What if the run is killed with Ctrl-C?
**A (auto):** The EXIT trap (with INT, TERM and HUP routed to it, and installed before the run dir exists) removes the run dir. A run killed with SIGKILL leaves its dir behind. The next run removes a `run.??????` dir only if it carries this runner's marker and the pid in the marker is gone, so a live run of any age and a foreign directory are never touched. *(Amended after /tla drift 3: the first answer said "older than a day" and `git worktree prune`. The review replaced both.)*

## Q17 — Edge cases: dirty working tree
**Q:** Does it measure HEAD or the working tree?
**A (auto):** The working tree, through a snapshot commit made with a temporary index. A developer re-measuring a fix before committing sees the fix. The real index and HEAD are untouched.

## Q18 — Non-functional limits
**Q:** How long may a default run take?
**A (auto):** 48 mutants, 4 workers. Measured self-test times are 8–60 s, except the traceability one at about 100–190 s. Order tests fastest first per module and stop at the first kill. The expected run is about 10–20 minutes; that is a `--full` job, not a SessionStart one.

## Q19 — Acceptance criteria
**Q:** What makes 085 done?
**A (auto):** The acceptance cases in `acceptance.md`, every named survivor re-measured and killed or documented as equivalent, the template's `--full` stamping mutation, and the runner's own self-test green with a sabotage mode.

## Q20 — Non-goals and assumptions
**Q:** What is assumed?
**A (auto):** The module self-tests are deterministic enough that a baseline green means green. Flaky tests show up as a red baseline (UNMEASURED) or as false kills; neither is a pass.

## Q21 — Reversibility
**Q:** How is it undone?
**A (auto):** Delete the runner; section 5 falls back to "no mutation runner for this stack" as before. The ledger readiness change is one condition.

## Q22 — Edge cases: F073
**Q:** If the H2 mutant does not reproduce a hang, what then?
**A (auto):** Record the measured time in the run log and FINDINGS, resolve F073 as "slow under load, not a hang", and rely on R1's baseline-relative limit to report such a run as a Timeout, never as a pass.

## O1 — Gate threshold  (overflow, threat surface: a gate that always fails is ignored)
**Q:** The runner's break is 80 like every Stryker gate, but the template's first measured runs were 25–58%. Keep 80, or start lower and ratchet?
**A:** Keep 80. The failure is the backlog signal; a lowered gate would read as a pass.

## O2 — Seed  (overflow: a fixed sample is tuned to, a moving one is not reproducible by default)
**Q:** Should the default seed rotate daily (fresh sample each day, `--seed` reproduces) or stay fixed?
**A:** Rotate daily. The seed is the UTC date; `--seed` reproduces a run.

## O3 — Work directory  (overflow, threat surface: the runner writes outside the repository)
**Q:** Worktrees go under `$HOME/.cache/claude-mutation` because one suite is red outside `$HOME`. Acceptable, or must the runner stay inside the repository?
**A:** `$HOME/.cache/claude-mutation` is fine. `MUTATION_WORKDIR` overrides it, and every run cleans up after itself.
