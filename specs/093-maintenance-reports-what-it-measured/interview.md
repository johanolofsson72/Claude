# Spec interview — 093-maintenance-reports-what-it-measured

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: spec-only, no hardened trigger (no auth, PII, upload, new external
surface, state machine or entity). Every question below had a defensible recommendation.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F087, F109, F110, F111, F113 as R1–R6, plus the banner's missing `--suite` (R3)
found while reading F110. Out: a time budget that refuses work, the runner's sample size, relative
`cd` arguments not built from `dirname`, leaks in self-tests.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer reading a maintenance report (wrong scope and break, a timeout called a
failure), the developer deciding whether to run `--full` now (no cost on the banner), a caller under
a .NET parent (Broken pipe on stderr), and anyone with `CDPATH` set who runs a script by hand.

## Q3 — Runner detection (F109)
**Q:** How does section 5 know the command is the project runner?
**A (auto):** `MUTATION_CMD` is exactly `bash scripts/run-mutation-gate.sh`; that string is set in
one place already and the trust path keys on it.

## Q4 — Break source (F109)
**Q:** Where does the runner's break come from?
**A (auto):** The last `settings:` line in its output, `break <int>`. The runner's header names that
line as its contract. Fallback: the 80 default, said as "the runner printed no break".

## Q5 — Scope wording (F109)
**Q:** What does the scope line say for a runner?
**A (auto):** "the project runner decides what it mutates (scripts/run-mutation-gate.sh)". The pass
cannot count configs a runner may not read, so it does not try.

## Q6 — Score note (F109)
**Q:** Does the "Stryker's score, timeouts count as kills" note stay for a runner?
**A (auto):** No. It is wrong for the template's runner, which counts a timeout as not killed. The
note says the score is the runner's and points at mutation-timeouts.md.

## Q7 — Estimate source (F110)
**Q:** Where does the expected duration come from?
**A (auto):** The ledger, `maintenance_ledger.py estimate`, median seconds over this place's runs.
It is already written by every measured job; nothing new is recorded.

## Q8 — Estimate when empty (F110)
**Q:** What does the banner say with no ledger runs?
**A (auto):** "Expected: unmeasured — no ledger run of <jobs> on this machine yet." Silence would
read as "cheap".

## Q9 — Which jobs (F110)
**Q:** Which jobs get an estimate line?
**A (auto):** The heavy ones that are due: mutation and suite. Secrets and similarity take seconds.

## Q10 — Banner command (R3)
**Q:** Is changing "Run now" to include `--suite` in scope?
**A (auto):** Yes, fixed in place: it is one word and smaller than recording it. `--full` alone
never runs the suite, so the line could not clear the job it was printed for.

## Q11 — Install summary (F110)
**Q:** Does the nightly installer print the estimate?
**A (auto):** Yes, one line, so the developer choosing `--at` knows how long the run takes. A
ledger-less install says unmeasured.

## Q12 — Timeout semantics (F111)
**Q:** How is a per-test timeout marked?
**A (auto):** `TIMEOUT <test> — unmeasured after 900s`, exit 124 when nothing else is red. 124 is
`timeout(1)`'s code, so a project that wraps its suite in `timeout` reads the same way.

## Q13 — Error state (F111)
**Q:** What does the report say for exit 124?
**A (auto):** "[SUITE] UNMEASURED — the suite timed out … neither passed nor failed. Not stamped."
The TIMEOUT lines are listed. It counts as a finding because the job is still due.

## Q14 — Mixed result (F111)
**Q:** FAIL and TIMEOUT both present?
**A (auto):** Exit 1, reported as failed, with the timeout count named so the red is not
overstated.

## Q15 — Rewrite method (F113)
**Q:** Bulk sed or per site?
**A (auto):** Per site, read before edit, file by file, with that file's self-tests run after.
The finding says so (msroute M2: a bulk pass broke things). The validator is the completeness check.

## Q16 — `head -c` replacement (F113)
**Q:** What replaces `printf … | head -c N`?
**A (auto):** `${VAR:0:N}`. Characters instead of bytes; these caps bound prompt size and a
character cut cannot split UTF-8. A command's output is captured first, then cut.

## Q17 — Random run name (F113)
**Q:** `tr -dc … < /dev/urandom | head -c 6` cannot read to the end. What then?
**A (auto):** `od -An -N16 -tx1 /dev/urandom | tr -dc 'a-f0-9' | cut -c1-6`: od reads exactly 16
bytes and stops on its own, so nothing downstream exits early.

## Q18 — Keeping leaks at zero (F113)
**Q:** How does zero stay zero?
**A (auto):** test-no-sigpipe-assertions.sh gets an arm that runs `--leaks` on the real template
tree and expects exit 0.

## Q19 — CDPATH fix form (F087)
**Q:** `unset CDPATH` at the top, or `CDPATH='' cd` per line?
**A (auto):** Per line. It is the idiom drive-sync.sh and guard-lib.sh already use. It is visible
at the site the audit flags, and a sourced library must not unset its caller's environment.

## Q20 — CDPATH gate (F087)
**Q:** Where is the regression check?
**A (auto):** One more entry in portability_audit.py CHECKS. It already scans every CORE script on
both platforms. A file that sources self-test-env.sh is exempt, since that file unsets CDPATH.

## Q21 — Reversibility
**Q:** Undo story?
**A (auto):** Every change is a text edit in a script, reverted by `git revert`. No state, no
migration. The ledger is only read.

## Q22 — Acceptance
**Q:** Measurable done?
**A (auto):** SC-A..SC-E pass in their self-tests, the touched scripts' self-tests are green, and
the declared suite is green.
