# Spec interview — 109-mutation-tooling

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, not hardened (a template-only runner, one shipped check, no new trust
boundary), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the nine findings on the row. Out: agentcrm's own file (F216 is handled by the
shipped gate catching it), changes to the sample size or the break, other projects' mutation gates.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The maintenance pass and the developer reading it. A survivor the gate cannot see, or a
re-measure that dies on a marked line, makes the gate's number wrong or unusable.

## Q3 — Marker syntax
**Q:** Per site by column, by ordinal or by operator text?
**A (auto):** By operator text, with an optional `#n`. A column moves when the line is edited and an
operator rarely does. The text is also what the report prints, so a reader can copy it across.

## Q4 — Backward compatibility of markers
**Q:** What happens to the existing whole-line markers?
**A (auto):** They keep their meaning. Only the line F227 names changes.

## Q5 — Stale selector
**Q:** A selector that matches no site: warn or fail?
**A (auto):** Fail with exit 2 and name the line. A silent stale marker is an unmeasured state that
reads as clean (Trap 4).

## Q6 — `--lines` on marked lines
**Q:** Drop with a note, or measure anyway?
**A (auto):** Drop with a note on stderr. Measuring a site somebody recorded as equivalent re-opens a
decision without saying so.

## Q7 — `--lines` all marked
**Q:** What is the exit when every requested line is marked?
**A (auto):** 2, "nothing to measure". Zero mutants must not print a score.

## Q8 — Python parsing
**Q:** Regex or tokenize?
**A (auto):** tokenize. It is in the standard library and it knows strings, f-strings and comments,
which a regex would get wrong on a 2000-line guard.

## Q9 — Python operator classes
**Q:** Which operators?
**A (auto):** compare, boolean and True/False. They match the bash classes, and they are where a
guard's verdict flips.

## Q10 — Python tests
**Q:** Which suites kill Python mutants?
**A (auto):** The ones that drive each module: settings_guard → test-settings-edit-guard.sh;
sensitive_paths → test-sensitive-file-guard.sh; shell_glob → test-settings-edit-guard.sh and
test-sensitive-file-guard.sh; bash_write_targets → test-bash-write-guard.sh.

## Q11 — Runtime budget
**Q:** Does adding six modules make the nightly gate too slow?
**A (auto):** The before and after runs measure it, and the run log records it. Each test run is
capped at max(60, 3 × baseline), so a hang cannot stretch the run; only the mutant count can.

## Q12 — Error state
**Q:** What does the developer see for a bad marker?
**A (auto):** `run-mutation-gate: <module>:<n>: marker selector '<sel>' names no site`, exit 2.

## Q13 — Empty state
**Q:** A Python module with no sites?
**A (auto):** The same as bash: "no mutable site at all; fix the target table", exit 2.

## Q14 — F216 disposition
**Q:** Fix agentcrm's script from here?
**A (auto):** No. It is that project's own file and this session is in the template. The shipped
portability gate flags it at agentcrm's next maintenance pass, and the summary tells the developer.

## Q15 — Portability false positives
**Q:** Does the new check flag the relative `-newermt` in project-maintenance.sh?
**A (auto):** No. Only an `@` operand is flagged, and a test pins the relative form as clean.

## Q16 — A survivor that cannot be killed
**Q:** What if a survivor is a true equivalent?
**A (auto):** Mark it per site with the reason, after applying it by hand and running the suite
(Trap 5). The marker is the record.

## Q17 — Moved lines
**Q:** How are survivors found in files that changed since the finding?
**A (auto):** By the cited line's content plus the operator. In a module with no edits since the
finding (hook-notice.sh, project-freshness.sh), the line number is exact.

## Q18 — Timeouts
**Q:** settings-edit-guard-hook.sh had a timed-out `||`→`&&`. Does it count?
**A (auto):** Re-run it on its own first. A kill there counts, a survivor gets a test, and a hang is
recorded.

## Q19 — Sabotage coverage
**Q:** Does each new arm need a sabotage mutant?
**A (auto):** Yes, one per arm, in the runner test's MUTANTS list. An arm nobody has seen go red is a
report, not a test.

## Q20 — Shipping
**Q:** Does anything new ship to projects?
**A (auto):** Only the portability check and tests that touch shipped scripts. The runner and its
test stay in TEMPLATE_ONLY_SCRIPTS.
