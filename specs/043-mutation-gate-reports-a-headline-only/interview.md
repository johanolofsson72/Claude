# Spec interview — 043-mutation-gate-reports-a-headline-only

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no auth, PII, upload, new external surface, state machine or entity. The change reads report files and writes nothing new.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: section 5 of project-maintenance.sh reads this run's JSON reports and reports modules under the limit; its test. Out: project-local runners, a strict scorer, rows 047 and 053.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer on a hardened spec who reads PASS from `--full` while the module the spec changed is under break.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** The fundit 006 shape (88% headline, one module at 65%) produces a finding that names the module and its score.

## Q4 — The row's premise
**Q:** The row names `--reporter progress` in the runner. Fix that?
**A (auto):** No. Measured: neither runner passes a CLI reporter now, and 045 settled the runner as project-local. The live defect is the CORE reader.

## Q5 — Which reports count
**Q:** How is "this run's report" decided?
**A (auto):** A marker file touched just before the run; only reports newer than it are read. A stale report from yesterday must not stand in for today's run.

## Q6 — Report names
**Q:** Which filenames?
**A (auto):** `mutation-report.json` (Stryker.NET default) and `mutation.json` (StrykerJS json reporter). Both tools are already the two the section chooses between.

## Q7 — Where to search
**Q:** Which directories?
**A (auto):** The whole tree under the project root, pruning node_modules, .git, bin and obj. Not pruning .stryker-tmp, because fundit's runner writes its reports there.

## Q8 — Per-file score formula
**Q:** Strict or Stryker's?
**A (auto):** Stryker's (Killed + Timeout) / valid, labelled as such, matching the headline. A strict scorer is out of scope as in 041.

## Q9 — Merge across reports
**Q:** Several reports from one run?
**A (auto):** Merge per mutant (file, mutator, replacement, location). Detected in any report means detected.

## Q10 — Limit
**Q:** What limit applies per module?
**A (auto):** The same one as the headline: the config's thresholds.break, else 80. One limit, one source, already printed.

## Q11 — Error state: no report
**Q:** Score but no report?
**A (auto):** A finding naming the reporters fix and the CLI-replaces-the-list trap. Not silent.

## Q12 — Error state: unreadable report
**Q:** A report that is not valid JSON?
**A (auto):** Named in the finding as unreadable; the other reports are still read.

## Q13 — Empty state
**Q:** A file with no valid mutants?
**A (auto):** Not listed. CompileError and Ignored are excluded from Stryker's own denominator.

## Q14 — Ordering and volume
**Q:** How many modules are printed?
**A (auto):** All under the limit, lowest first. The row says "every module under the break"; truncation would hide the one that matters.

## Q15 — Stamp
**Q:** Does a module finding change the due-state stamp?
**A (auto):** No. A score came back, so the run measured (F044). The finding carries the gap.

## Q16 — Headline fails too
**Q:** Where does the list go when the headline also fails?
**A (auto):** Inside the GATE FAILED finding, so one gate failure stays one finding.

## Q17 — Reversibility
**Q:** Rollback?
**A (auto):** One section in one CORE script; revert the commit and the next sync restores the old reading.

## Q18 — Acceptance
**Q:** How is it proven?
**A (auto):** Fixture arms per FR in test-project-maintenance.sh with a stub Stryker writing a report, the existing mutation arms unchanged, and hand mutations of the new code killed.
