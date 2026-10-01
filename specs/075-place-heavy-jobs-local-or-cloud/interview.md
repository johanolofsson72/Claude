# Spec interview — 075-place-heavy-jobs-local-or-cloud

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. The direction is the developer's (2026-09-29: heavy jobs that need no local setup go
to Claude cloud; 2026-10-01: have it in place by morning). Hardened by size, so overflow questions
are due. The developer was asleep when they came up; each overflow answer below is the most
conservative option, chosen so that nothing durable happens before the developer confirms it, and
is listed for confirmation in the status summary. That is recorded here rather than presented as
the developer's answer.

## Q1 — Scope boundary
**Q:** Does 075 create the cloud routine?
**A (auto):** No. Creating a routine is an account-level action that spends plan usage on a
schedule. 075 ships everything the routine runs and the one command that creates it.

## Q2 — Scope boundary
**Q:** Which jobs are candidates?
**A (auto):** The ones 074 measures: secrets, traceability, similarity, mutation, suite,
portability. The findings/carve review is a human decision batch and is local by definition.

## Q3 — Primary actor
**Q:** Who runs the cloud half?
**A (auto):** A routine (scheduled or "Run now") or a cloud session started by hand, both running
`scripts/cloud-maintenance.sh`.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** The Mac's due banner says mutation runs in the cloud; the routine runs it; `--pull`
brings back the ledger line and the stamp; the banner stops saying mutation is due.

## Q5 — Data model
**Q:** Where is the decision stored?
**A (auto):** A tracked TSV, `scripts/workload-placement.tsv` (CORE, so it reaches projects), `job<TAB>place<TAB>reason`. Plain
text that bash 3.2 and Git Bash read without python.

## Q6 — Data model (override)
**Q:** Can a project place a job differently from the template?
**A (auto):** Yes, `.claude/workload-placement.tsv`, line-by-line override. agentcrm's suite
peaks near the VM ceiling while another project's may not.

## Q7 — Validation
**Q:** What happens with a place other than local/cloud?
**A (auto):** The script names the line and the value and treats the job as not runnable here. A
typo must not silently keep Stryker on the laptop or silently skip it.

## Q8 — Decision rule
**Q:** What thresholds decide cloud?
**A (auto):** Needs nothing local, max RSS < 12 GB (4 GB headroom on 16), median >= 5 min locally.
Below 5 minutes the cloud session's own start-up and clone cost more than it saves.

## Q9 — Missing data
**Q:** A job with no measurements?
**A (auto):** Local. "Not measured" is not "cheap" (074's rule).

## Q10 — Observable states
**Q:** What does each state look like for `--placed`?
**A (auto):** Success: the job runs and is stamped. Error: unknown place, named. Empty: nothing
placed here, one line saying so. Loading: the jobs' own progress output, unchanged.

## Q11 — Error semantics
**Q:** What if the cloud run cannot install .NET?
**A (auto):** Fatal for the dotnet jobs, reported in the results file with rc and reason, so the
Mac sees a failed run rather than no run.

## Q12 — Authorization
**Q:** What may the cloud run write?
**A (auto):** Only `claude/maintenance-results`, and only under `.claude/cloud-results/`. The
routine platform already refuses the default branch; the script also refuses it.

## Q13 — Concurrency
**Q:** Two cloud runs at once?
**A (auto):** Each writes its own timestamped file, so commits never conflict on content; a push
race is retried once after a rebase, then reported.

## Q14 — Integration
**Q:** Does SessionStart fetch the results branch?
**A (auto):** No. SessionStart does no network calls today; the banner names `--pull` instead.

## Q15 — Idempotence
**Q:** What if `--pull` runs twice?
**A (auto):** Second run imports nothing: imported file names are recorded in
`.claude/state/cloud-imported`.

## Q16 — Edge case
**Q:** A results file with a malformed line?
**A (auto):** The line is skipped with a warning naming file and line; the rest imports.

## Q17 — Non-functional
**Q:** How long may a cloud run take?
**A (auto):** Not documented (2026-10-01). The first Stryker run in the cloud is the proof; until
then the doc says so.

## Q18 — Reversibility
**Q:** How is a placement undone?
**A (auto):** Edit the TSV line to `local`. Nothing else holds state about the place.

## Q19 — Non-goals
**Q:** Ollama jobs in the cloud?
**A (auto):** No. The VM has 16 GB and no model; similarity is 16.6 s locally.

## Q20 — Overflow (threat surface): what may the results file make the Mac do?  (overflow — developer asleep, conservative pick)
**Q:** The Mac imports a file a cloud session wrote. What can that file change?
**A (auto):** Only ledger lines and stamps, parsed field by field against fixed job names and
numeric fields. Nothing in it is executed or sourced. Confirm in the morning.

## Q21 — Overflow (tampering): who else can write that branch?  (overflow — developer asleep, conservative pick)
**Q:** Anyone with push access can write `claude/maintenance-results`. Is a forged stamp a risk?
**A (auto):** It can at worst make a job look done when it was not. Accepted: the same people can
already edit the local stamp file. The import prints every stamp it applies. Confirm in the morning.

## Q22 — Overflow (disclosure): does the results file leak anything?  (overflow — developer asleep, conservative pick)
**Q:** Could a results file carry secrets?
**A (auto):** It carries ledger fields only (timestamps, job names, numbers). Job output is not
copied into it. Confirm in the morning.

## Q23 — Overflow (exhaustion): what stops a runaway routine?  (overflow — developer asleep, conservative pick)
**Q:** A schedule that fires too often burns plan usage.
**A (auto):** 075 does not create the routine; the doc recommends daily at most, and the routine
skips when nothing is due (`--if-due`). Confirm in the morning.
