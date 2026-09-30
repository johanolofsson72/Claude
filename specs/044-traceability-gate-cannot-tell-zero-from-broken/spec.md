# 044 — traceability-gate-cannot-tell-zero-from-broken

Track: spec-only. No entity, no state machine, no new external surface. One CORE script and its
harness change. Not hardened.

Evidence: fundit (0 of 182, then 175 of 182 minutes later with nothing changed, 2146 TLC scratch
files under `tests/`) and agentcrm F316 (a partial read that said "see above" over nothing).
Diagnosis on the register row and in `specs/INDEX.pending.md`.

## The defects, as measured on 2026-09-30

Both live in `scripts/validate-scenario-traceability.sh`.

1. **Zero ids from a scan that ran.** The gate refuses (exit 4) when a root is missing, because zero
   references renders as "every claimed scenario is uncovered". When every root exists and the scan
   returns no id at all, the same report comes out as `coverage: 0 of N` with exit 1. The scan's own
   errors go to `/dev/null` (`xargs ... 2>/dev/null || true`), so nothing in the output hints at
   why. The fundit cause is unproven. It is NOT the binary-file flag: `-a` is deliberate and
   documented in the script. The row asks for a fix to the reporting, not to the guess.

2. **"See above" over nothing.** Under `--partial` the row extractor names every row it refuses as
   `file:line has N columns, expected 5` on stderr. The gate captures that stderr into `rows.err`
   and never prints it on the partial path. The last line then reads "part of the map was unreadable
   (see above)" and nothing above names the rows.

## Decision

- When the map claims at least one row (✓ or ◐) and the scan of every existing root yields no
  scenario id at all, the gate refuses with **exit 4** ("I could not look") instead of reporting
  coverage. The refusal names the roots, the number of files read under each, and the scan's own
  error output if it wrote any. It says what to try (rerun, check the roots) and what the state
  means if the suite genuinely cites no id.
- A map that claims nothing (all ☐ or retired) and a scan that finds nothing stays a normal run:
  nothing is claimed, so no claim goes unbacked, and the report is not catastrophic.
- The scan's stderr (xargs and grep) is captured into a file, not thrown away. It is printed only
  in the refusal, so the normal report is unchanged.
- Whatever the extractor wrote to stderr is printed whenever it wrote something, not only when it
  refused the map. The partial-read line states how many rows were refused and points at the lines
  above only when those lines exist. If the extractor said it skipped rows but named none, the gate
  says so rather than pointing at nothing.

## Out of scope

- Finding the fundit cause. Unproven, not reproducible here.
- Changing `scenario-map-rows.sh`. It already names file and line; the gate only has to print it.
- `project-maintenance.sh`. Exit 4 and 5 already reach its "could not run" finding with the
  output's tail.

## Functional requirements

- FR-01 A map with a claimed row, existing roots and no id in any file → exit 4, not 1.
- FR-02 That refusal names each root with the count of files read under it.
- FR-03 That refusal prints the scan's stderr when it wrote any.
- FR-04 A map claiming nothing with no id found → exit 0 (unchanged).
- FR-05 A partial read prints every row the extractor refused, as `file:line`, and the refused count.
- FR-06 "see above" is printed only when the extractor wrote something.
- FR-07 The new guard is a marked sabotage region, and the harness has an arm proving it is
  load-bearing.
- FR-08 Every existing harness case keeps its verdict.
- FR-09 The header's exit-code table states the widened meaning of 4.

## Clarifications

### Session 2026-09-30

- Q: Refuse on zero ids when the map claims nothing? → A: No. The row's damage is "every claimed
  scenario is uncovered"; with nothing claimed there is no catastrophic report, and refusing would
  turn an all-☐ roadmap project red.
- Q: Which exit code? → A: 4. It already means "I could not look", and every caller already treats
  it as "could not run" rather than as coverage.
- Q: Count raw tokens or kept ids? → A: Kept ids (`refs.u`). An out-of-range id is still an id the
  scan found, so it proves the scan read something.
