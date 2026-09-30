# 078 — autosync-tests-miss-ten-of-twelve-mutants

Track: spec-only. Tests for one CORE script (`scripts/template-autosync.sh`), one new suite, and
one CORE_SCRIPTS name. The sync's behaviour does not change. No entity, no state machine, no new
surface, fewer than 6 files. No hardening trigger.

Evidence: H1 mutation spot-check (`specs/H1-integration-hardening/checkpoint.md` §4), F050.

## The defect

H1 applied 12 sampled operator mutants to `template-autosync.sh` and ran every suite that drives
it. Two died. The finding named six survivors by line number and did not record the other four,
so that sample cannot be repeated.

## The sample, re-drawn and written down

The six named sites mapped to today's lines, plus six new mutants from the same classes. Measured
against all 20 suites that mention the sync (`grep -l template-autosync scripts/test-*.sh`). A kill
is a suite that is green on the unmutated script and red on the mutant. Three suites are already
red on main and count for nothing: test-core-gates b (F056), test-hook-channels (F055) and
test-validate-scenario-traceability case40a (F057).

| Id | Line | Mutant | Origin | Before 078 | After 078 |
|---|---|---|---|---|---|
| M01 | 445 | template `--unlisted`: `[ -f "$_f" ] \|\| continue` removed | H1:438 | survived | killed (arms) |
| M02 | 468 | `[ -f "scripts/$_n" ] && continue` → `\|\|` | new | killed (unlisted) | killed |
| M03 | 1042 | `eol_divergent_paths`: `\|\| return 0` → `return 1` | H1:1036 | survived | **equivalent** |
| M04 | 1043 | `[ -n "$_eol" ]` → `-z` | new | killed (eol) | killed |
| M05 | 1242 | `wrote_paths`: `$1 == "#" && $2 == "wrote"` → `\|\|` | H1:1235 | survived | **equivalent** |
| M06 | 1250 | `recorded_hash`: `-n` → `-z` | new | killed (stranded) | killed |
| M07 | 1442 | stranded `[ -n "$_paths" ]` → `-z` | new | killed (stranded) | killed |
| M08 | 1685 | `local_record`: `\|\| return 1` → `return 0` | H1:1678 | survived | killed (arms) |
| M09 | 1765 | accept-local refusal `-eq 1` → `-ne 1` | new | survived | killed (arms) |
| M10 | 1768 | accept-local CORE refusal `exit 1` → `exit 0` | H1:1761 | survived | killed (arms) |
| M11 | 1759 | accept-local unshipped refusal `exit 1` → `exit 0` | new | survived | killed (arms) |
| M12 | 2596 | final core re-merge `&& python3 -m json.tool` → `\|\|` | H1:2589 | survived | killed (arms) |

Before: 4/12. After: 10/12, measured with the same driver over the same 20 suites plus the new one.

### Why M03 and M05 get no arm

- **M03.** `eol_divergent_paths` is only ever called as `EOL_DIVERGED=$(eol_divergent_paths …)`,
  and the next line tests the captured text. Nothing reads its exit status and the script does
  not run under `set -e`. Changing a return code there cannot change behaviour.
- **M05.** With `||`, `wrote_paths` also prints field 4 of `# orphan` records and of the stamp's
  comment lines. Those paths join the `git diff` pathspec in `report_stranded`. `_keep` then drops
  every one of them, because it names a path only when `recorded_hash` (exact-match manifest line,
  then exact-match `# wrote` record) equals the file's current hash, and none of those paths has
  either record. The sync never writes a path into both an orphan record and the manifest. The
  report is identical.

H1 counted both as survivors. They are equivalent, and the honest score for the sample is 10 of 10
non-equivalent mutants killed.

## Requirements

- **FR-01** New suite `scripts/test-template-autosync-arms.sh`, with one arm per non-equivalent
  survivor (M01, M08, M09+M10, M11, M12). Each arm drives the real script end to end through
  `drive_sync` (spec 011) and builds only the fixture it asserts about.
- **FR-02** Each arm that asserts an absence has a positive control beside it, so it cannot pass
  just because the feature did not run (M01 checks that template mode named a real unlisted script,
  M08 that a real record for an identical file is `stale:1`, M11 that a shipped differing rule is
  accepted).
- **FR-03** `--sabotage` applies each arm's mutant to a copy of the script, using an exact-text
  anchor that has to match exactly once, and runs only that arm against the copy (`ARMS_ONLY`).
  The run passes only when every arm goes red. It prints the assertion that failed. A stale anchor
  or an arm that stays green is a failure and is named.
- **FR-04** `ARMS_TEST_SCRIPT` selects the script under test, following `EOL_TEST_SCRIPT`.
- **FR-05** The suite is listed in CORE_SCRIPTS beside the other `test-template-autosync-*.sh`
  suites, so it ships with the script it tests.
- **FR-06** bash 3.2-safe. No GNU-only flags.

## Acceptance

- AC1 `bash scripts/test-template-autosync-arms.sh` is green on HEAD.
- AC2 `--sabotage` reports all six mutants killed, each by the assertion written for it.
- AC3 Re-running the 12-mutant sample over all suites kills every non-equivalent mutant.
- AC4 No suite that is green on HEAD without this change turns red with it.

## Clarifications

### Session 2026-09-30

- Q: Repeat H1's exact twelve? → A: Impossible, four were never recorded. Use the six named plus six
  new ones from the same classes, and write the sample into this spec so the next pass repeats it.
- Q: Build a general bash mutation runner? → A: No. The sample and its driver live in the spec's
  scratch run. The permanent proof is `--sabotage`, which covers exactly the arms this spec adds.
- Q: Fix the three pre-existing reds found on the way? → A: No. They are recorded as F055 (already
  open), F056 and F057. The register is frozen and they are not this row.
