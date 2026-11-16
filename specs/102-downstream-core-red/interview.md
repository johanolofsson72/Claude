# Spec interview — 102-downstream-core-red

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Hardened (secrets domain, R5), so the overflow carries threat-surface questions for the
developer (Q19–Q20).

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the six reds and one freshness finding a re-synced fundit clone shows at 1ffab98.
Out: reds the sandbox no longer reproduces, F203, F204, the template-tree reds in F205.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer reading a project's maintenance pass. Six red CORE gates and one "rotate
this key now" finding that are the template's doing train them to skip the section.

## Q3 — Evidence standard
**Q:** How is "red downstream" measured?
**A (auto):** A local clone of fundit, re-synced from the template working tree into a scratch
sandbox, every `core-gates.sh` gate run with stdin closed and a 300 s bound. The same run after the
fix must show zero reds.

## Q4 — The .tsv files
**Q:** Is core-parity's ghost report a test bug or a sync bug?
**A (auto):** A sync bug. CORE_SCRIPTS names the files, the copy loop never copies them, so
`workload-placement.sh` and the quality gates run downstream without their tables.

## Q5 — Copy-loop shape
**Q:** Name the two files, or derive?
**A (auto):** Derive: every CORE_SCRIPTS name without a `.sh`/`.py` suffix is copied by name.
`speckit-version` then needs no special case.

## Q6 — Template-only files a test reads
**Q:** Ship sync-prompt.md downstream, or skip?
**A (auto):** Skip. /project-update fetches sync-prompt.md from GitHub; a local copy is a snapshot
nobody reads (2db2520 made the same call for the bootstrap test).

## Q7 — Skip granularity in local-llm-host
**Q:** Skip the suite or the checks?
**A (auto):** The checks that read sync-prompt.md. The rest tests `local-llm-host.sh`, which ships.

## Q8 — Skip predicate
**Q:** Which predicate decides "downstream"?
**A (auto):** The existing one: origin matches the template slug → template; no origin and a sync
stamp → downstream; another origin → downstream; neither answers → nothing is skipped.

## Q9 — Mobile docs on web projects
**Q:** Ship them or teach the citation validator about withheld docs?
**A (auto):** Ship them. One deleted case line against a second list; the mobile overlay dangles too.

## Q10 — Mobile overlay
**Q:** On a mobile project, does testing-mobile.md also land under its own name?
**A (auto):** Yes, in addition to the canonical-name overlay, so citations by either name resolve.

## Q11 — fixture-map-ids under split
**Q:** Where do the owned ids come from?
**A (auto):** `scenario_map_files` from scenario-map-layout.sh, the predicate every other consumer
sources. `--map` keeps meaning that one file.

## Q12 — Empty state for fixture-map-ids
**Q:** What does zero rows across all files report?
**A (auto):** NOT RUN, exit 3, as today. An unreadable map is not an empty one.

## Q13 — Error state for the sync
**Q:** What if a CORE data file is missing in the template?
**A (auto):** The copy loop skips it, as it skips a missing `.sh`; core-parity in the template is the
red that names it.

## Q14 — Freshness exemption mechanism
**Q:** Ship `.secret-shapes-allow` lines, or build them into the scanner?
**A (auto):** Built in. `.secret-shapes-allow` is project-owned; syncing it would overwrite a
project's own exemptions.

## Q15 — Exemption scope
**Q:** Which paths?
**A (auto):** Exactly `scripts/project-freshness.sh` and `scripts/test-project-freshness.sh`,
compared with `=`. No globs, no project extension of the built-in list.

## Q16 — Visibility
**Q:** Is an exempted hit printed?
**A (auto):** Yes, as `[ALLOWED]` with the built-in reason, counted like any allow.

## Q17 — Template's own allow file
**Q:** Keep the two now-redundant lines in the template's `.secret-shapes-allow`?
**A (auto):** Remove them. Two sources for one exemption is the drift this row is about.

## Q18 — Tests
**Q:** Where do the tests go?
**A (auto):** `[102]` cases in test-template-autosync suites (R1, R3), test-fixture-map-ids.sh (R4),
test-project-freshness.sh (R5), and downstream-mode cases for the R2 skips.

## Q19 — Threat: a real key at an exempted path
**Q:** Is it acceptable that a real key committed at `scripts/test-project-freshness.sh` in a
project prints `[ALLOWED]` instead of `[FINDING]`?
**A:** Yes. The path is CORE: guarded downstream, overwritten by the next sync, and the hit is still printed.

## Q20 — Threat: history blobs
**Q:** Should the exemption also cover historical blobs at those paths (older fixture versions)?
**A:** Yes. Path-based, like every .secret-shapes-allow line; old fixture versions sit in every project's history.
