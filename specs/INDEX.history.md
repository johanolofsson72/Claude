# INDEX — archived history

Old history entries moved out of INDEX.md to keep per-spec context cheap.
This file is NOT read during the pipeline. Newest archived batch first.

- 2026-09-30 — 048 ticked: SC ids grow past 999 without re-padding; the width discriminator measures the narrowest id and now has a test.

- 2026-09-30 — 047 ticked: mutate patterns that match nothing or count characters are findings; Stryker beside a build is refused.

- 2026-09-30 — 079 added and ticked in one pass: the traceability gate could not read a chained underscore id; agentcrm H6 measured 8 lost citations.

- 2026-09-30 — 044 ticked: zero ids from a scan that ran is refused, not reported as 0 of N; "see above" now has something above it.

- 2026-09-30 — 043 ticked: the live defect was the CORE reader, not the runner; a passing headline over a weak module is now a finding.

- 2026-09-30 — H1 ticked: 57/57 after two fixes; 078 added from approved proposal F050 (autosync kills 2/12 mutants).

- 2026-09-29 — 034 ticked without new code: 774a909 (2026-09-09) had already fixed it. fundit's deps pass shows 0 bogus SKIPs.
- 2026-09-29 — 030 ticked without new code: 045 had already landed the fix. --unlisted is clean on rocky and all 46 repos.

- 2026-09-29 — 029 re-diagnosed: the permission mode was never the cause (live A/B); re-tracked spec-only [hardened]. F029 recorded.

- 2026-09-29 — 020 held: Ollama is disabled machine-wide since 2026-09-06, so the hooks it re-measures are no-ops; resumes on a machine that runs a local model.

- 2026-09-29 — 075 held: ledger spans 0 of 5 specs and has no Stryker/suite run anywhere; resumes when `maintenance_ledger.py report --all` clears 5.

- 2026-09-29 — 026 deleted: same scope as 011 (port drive_sync + its gate, convert the CORE drivers), which landed it. Developer decision at 011's interview.

- 2026-09-29 — convergence stop answered: FREEZE until open rows < 40. 077 added at the developer's request so proposals carry evidence of need.

- 2026-09-29 — 076 filed from consultpilot Q2 (H7ai): the 97 branch consultpilot carried was reverted by two syncs because it never lived upstream.

- 2026-09-29 — 074, 075 added at the developer's request (not carves): measure maintenance, then place jobs local vs cloud after five specs.

- 2026-09-28 — 073 added at the developer's request: pipeline refresh + rollout (consolidated; folds 037, 022).

- 2026-09-28 — 071, 072 filed from teach H3 findings review (F007, F061).
- 2026-09-25 — 054-064 filed from agentcrm's T0 pass (two findings reviews, 2026-09-19 and H5 2026-09-23); 055-057 fixed in the same pass, 064 found while running the suite.
- 2026-09-25 — 053 filed from msroute F007; msroute F008 (autosync printf SIGPIPE) added as evidence to 024 (carve-budget §4).
- 2026-09-18 — 052 filed from ighweld-2026's second findings review; the rest of its tooling findings were already rows 047, 049 and 050.
- 2026-09-18 — 051 filed from emaljen's H3 findings review (F027, carve-budget §4).
- 2026-09-16 — 047-050 filed from ighweld-2026's first findings review (carve-budget §4); F003/F059/F085 closed there instead, already fixed by 028.

- 2026-09-12 — 046 carved: hook output channels are inverted — advisories shout at the developer, model context is silently dropped.
- 2026-09-11 — 045 landed from rocky F041/F042/F044/F045: the unlisted predicate denied a tick no action could clear, and 043's CORE half is corrected on the row.
- 2026-09-07 — 040-041 filed from the same T0 pass: the ignore set never reaches a project, and a rule ten files cite was never written.
- 2026-09-07 — 037-039 filed from hetznerradar's T0: the three defects its bootstrap hit (carve-budget §4).
- 2026-09-07 — 036 fixed in place from ighweld-2026 180: the tally alternation learns `✓ int`, longest-first.
- 2026-09-05 — 032-035 filed from fundit's findings review (carve-budget §4: a harness defect belongs here, not on a product register)

- 2026-09-04 — 028 ur ighweld 173: traceability-gaten läste bara toppnivå-testkataloger; projekt får nu deklarera sina roots.
- 2026-09-04 — 027 ur agentcrm: `--carves` kallade ett register clean vars djup-3-kedja just spårats för hand. Regeln säger att noll attributioner *är* fyndet; skriptet exitar 0 och `project-maintenance.sh` ser grönt.

- 2026-09-03 — 006 corrected on measurement: the bare skill name resolves to the plugin cache, so the rename half is refuted; what stands is that nothing checks the plugin is installed.
- 2026-09-03 — 021 + 022 filed from an msroute `/project-update`; the two orphaned CORE-adjacent improvements landed here in the same pass.
- 2026-09-03 — register created; harness defects move here off the product registers, per the carve budget.
