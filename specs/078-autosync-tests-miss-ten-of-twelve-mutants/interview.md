# Spec interview — 078-autosync-tests-miss-ten-of-twelve-mutants

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger: tests for one CORE script, no new entity, no new surface, no auth, fewer than 6 files. No overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: one new test suite with an arm per surviving mutant in `scripts/template-autosync.sh`, a sabotage mode that proves each arm kills its mutant, and the CORE_SCRIPTS entry that ships it. Out: changing the sync's behaviour, a general bash mutation tool, the other two H1 modules (F048, F049).

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The six synced projects. A regression in the most-changed CORE script ships to all of them and no suite notices, which H1 measured as 10 of 12 behaviour changes.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** The same 12-mutant sample, re-run against every suite that exercises the sync, is killed in full except for mutants shown to be equivalent. Each kill of a former survivor comes from a named arm in the new suite.

## Q4 — Which mutants
**Q:** H1 named six survivors and did not record the other four. Which sample?
**A (auto):** The six named sites, mapped to today's line numbers, plus six new operator mutants from the same classes (`-n/-z`, `-eq/-ne`, `&&/||`, exit/return codes, `-f`). The sample is written to the spec so the next measurement repeats it rather than redraws it.

## Q5 — Equivalent mutants
**Q:** What if a survivor changes nothing observable?
**A (auto):** It gets no arm. The spec records why it is equivalent (for example a return code inside a `$(...)` whose status no caller reads). It counts as equivalent, never as a kill.

## Q6 — Kill criterion
**Q:** When is a mutant killed?
**A (auto):** When a suite that is green on the unmutated script goes red. Suites that are already red on main (core-gates b, hook-channels/F055, traceability case40a) count for nothing either way.

## Q7 — Where the arms live
**Q:** Extend the existing suites or add one?
**A (auto):** One new suite, `scripts/test-template-autosync-arms.sh`. The survivors span five unrelated features. Spreading arms over five suites would put the sabotage list in five places.

## Q8 — How an arm drives the sync
**Q:** Direct invocation or the helper?
**A (auto):** Through `drive_sync` / `drive_sync_readonly` from `scripts/drive-sync.sh`, as spec 011 requires and `test-validate-sync-sandbox-declarations.sh` enforces.

## Q9 — Sabotage mode
**Q:** How does the suite prove its arms bite?
**A (auto):** `--sabotage` copies the script, applies each arm's mutant by exact-text anchor (it must match exactly once, or the arm reports the anchor as stale), runs that arm against the copy and expects red. Precedent: specs 070 and 047 marked sabotage arms.

## Q10 — Anchor drift
**Q:** What happens when someone edits a mutated line later?
**A (auto):** `--sabotage` fails loudly naming the stale anchor. A silent skip would turn the proof into theatre.

## Q11 — Script under test
**Q:** Can the suite run against another copy?
**A (auto):** Yes, `ARMS_TEST_SCRIPT`, same pattern as `EOL_TEST_SCRIPT`. The sabotage mode uses it.

## Q12 — Runtime budget
**Q:** How slow may it be?
**A (auto):** Normal mode under 60 s on this machine. Each arm builds only the fixture it asserts about.

## Q13 — Platforms
**Q:** Which shells?
**A (auto):** bash 3.2 (macOS) and Linux bash, per the cross-platform base requirement. No GNU-only flags. Git Bash is not exercised locally; the suite uses nothing beyond what the sibling autosync suites use.

## Q14 — Shipping
**Q:** Does the suite ship to projects?
**A (auto):** Yes. It goes into CORE_SCRIPTS next to the other `test-template-autosync-*.sh` suites, so a project that syncs the script also gets its tests.

## Q15 — The four observable states
**Q:** Success / error / empty / loading?
**A (auto):** No UI. Success = every arm passes. Error = the failing arm is named with its expected and actual value. Empty = N/A. Loading = N/A.

## Q16 — Acceptance
**Q:** Measurable definition of done?
**A (auto):** (1) the new suite is green on HEAD; (2) `--sabotage` turns every arm red; (3) the 12-mutant sample re-run shows every non-equivalent mutant killed; (4) no previously green suite turns red.

## Q17 — Reversibility
**Q:** Undo story?
**A (auto):** Test-only change plus one CORE_SCRIPTS name. Revert the commit.

## Q18 — Pre-existing reds found on the way
**Q:** What about the three suites already red on main?
**A (auto):** Recorded as findings (`finding.sh --add`), not fixed here. The register is frozen and they are not this row.
