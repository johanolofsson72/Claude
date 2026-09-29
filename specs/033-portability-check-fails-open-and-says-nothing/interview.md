# Spec interview — 033-portability-check-fails-open-and-says-nothing

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no hardened trigger fires (no auth/PII/upload/new surface, no state machine, no new entity, 4 files).

## Q1 — Scope boundary
**Q:** Does the spec fix every `[ -f ]`-guarded section in `project-maintenance.sh`?
**A (auto):** No, only 6c (portability). The others have their own reasons: census scripts are declared optional, and 6b also needs a register. The rest go to a finding.

## Q2 — Primary actor
**Q:** Who is hurt?
**A (auto):** A developer on a synced project whose sync missed the portability scripts. Their maintenance pass reads `clean` while the check never ran, and a construct that breaks on the other developer's platform ships unseen.

## Q3 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** A pass on a project with both scripts behaves exactly as today. A pass on a project missing either one is red and names the file.

## Q4 — Finding or note
**Q:** Is a missing script a finding (red) or a note (reported, still clean)?
**A (auto):** A finding. Both are CORE, section 1 already makes a missing CORE check `[SETUP]`, and a note keeps the `clean` verdict the row complains about.

## Q5 — Label
**Q:** Which tag does the missing-script line use?
**A (auto):** `[SETUP]`, same as the missing `project-freshness.sh` line, with the same remedy: `/project-update`.

## Q6 — Naming
**Q:** When one script is missing, does the line name both or one?
**A (auto):** Only the missing one. Naming a file that is there sends the reader to the wrong place.

## Q7 — Could-not-run path
**Q:** What happens when the run exits 2 (validate-portability's "could not run") or 127?
**A (auto):** A `[PORTABILITY] ... could not run (exit N)` finding with the first three lines of output, the shape section 6b uses.

## Q8 — Exit 0
**Q:** Does a clean portability run print a reassurance line?
**A (auto):** No. The pass lists what went wrong, not what went right.

## Q9 — Exit 1
**Q:** Does the existing findings wording change?
**A (auto):** No. Only the paths that were silent get new output.

## Q10 — Error message content
**Q:** What does the `[SETUP]` line say exactly?
**A (auto):** `[SETUP] portability check did not run — <missing files> missing. Run /project-update to restore it.` It says the check did not run first, because that is the fact a reader needs.

## Q11 — Ledger
**Q:** Does the missing-script path go through `measured`?
**A (auto):** No. Nothing runs, so there is nothing to measure.

## Q12 — Other fixtures
**Q:** Which existing self-tests break because their fixtures lack the scripts?
**A (auto):** Any that assert a clean exit or an exact finding count: `test-project-maintenance.sh` (mkfix) and `test-skill-reachable.sh` (M1a counts 2, M2a expects 0). They get passing stubs. Tests that grep one tag are unaffected; checked by running them.

## Q13 — Stub shape
**Q:** What does a passing stub look like?
**A (auto):** `validate-portability.sh` that exits 0 and an empty `portability_audit.py`. The section only checks that the engine exists; the wrapper is what runs.

## Q14 — Concurrency / ordering
**Q:** Any ordering concerns?
**A (auto):** None. The section is sequential and reads two files.

## Q15 — Cross-platform
**Q:** Does the new code stay bash 3.2 / Git Bash safe?
**A (auto):** Yes. Plain `[ -f ]`, string concatenation and `sed -n`, no arrays.

## Q16 — Acceptance
**Q:** How is done measured?
**A (auto):** SC-033-01..06 in `test-project-maintenance.sh`, with 01-04 red on HEAD before the fix, and every self-test that runs `project-maintenance.sh` green after.

## Q17 — Reversibility
**Q:** Rollback?
**A (auto):** Revert the commit. No data, no migration.

## Q18 — Non-goals
**Q:** Does this spec restore the scripts in fundit?
**A (auto):** No. Cross-project findings are notify-only; fundit gets the fix through sync, and it already has the scripts now.
