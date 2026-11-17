# H7 — integration-hardening checkpoint (template repo)

Seventh checkpoint. It covers what was ticked since H6: 100, 101, 102 and 104, plus 919bb38
(F235). `checkpoint-cadence.sh` reported `since=H6 count=5 due=1`. Everything ran in one session
on 2026-11-17.

## 1. Full-system regression

`project-maintenance.sh --full --suite` ran all 97 `scripts/test-*.sh` one at a time under bash
with the 900 s cap. Every test passed in 1236 s, and the suite was stamped. The whole pass took
2999 s because `--full` also ran the default mutation table (section 4). It exited 1 on hygiene
findings only:

- The register's context cost is 28 KB, and six history entries sit inline.
- The convergence stop: ratio 1.31.
- F225 is unchanged: two mod scripts lack the executable bit, and only the developer can fix that.
- Two near-duplicate row pairs in matchpilot. That's another project, so it's noted here and
  nothing more.

There was no timeout this time. At H6 the mutation run and the suite overlapped on the machine and
the suite hit its cap. This time the spot-check started after the suite finished.

## 2. Cross-cutting security sweep

`project-freshness.sh` was clean: no verified credentials and no committed key material. OSV was
skipped because osv-scanner is not installed. The `security-scanner` agent read the diff from
98ab21a to 919bb38. It was scoped to defensive gaps, it was told not to write bypass recipes, and
the items already recorded (F184–F193 and others) were excluded. It returned ten items. Three were
checked against the source here (1, 3 and 5), and the rest were read from the code by the agent.

Fixed in place, because the fix was smaller than a finding: the F235 twin check in
`test-hook-channels.sh` piped `.matcher | split("|")` through `jq ... 2>/dev/null`. A PostToolUse
group with no matcher, or a missing `jq`, emptied `MISSING`, and the test printed "every gate has
a twin". It now reads `(.matcher // "")` and fails when jq exits non-zero. The result is 51/0.

Recorded as F247–F255:

- F247 (verified): the 101 R3 by-name mode keys on `command_word()`. That function skips `VAR=`
  only, not wrappers such as timeout, nice, env, command or sudo, while `git_args` does unwrap
  them. The two parsers disagree.
- F248: a `sed -i` word that is not a recognised pure script is taken as a BSD backup suffix, so
  a GNU `r`, `R`, `w` or `W` script is never split. `gsed` is not treated as sed at all.
- F249 (verified): `sync-prompt.md` says the origin check runs "before insteadOf", but the fetch
  and the fast-forward after it honour `insteadOf`.
- F250 (suspected): sync-prompt accepts any directory with the right two markers as the template,
  and the not-a-clone and "old" branches warn and carry on.
- F251: the F235 twins cover Edit and Write but not MultiEdit. Whether MultiEdit is still a live
  tool needs checking first.
- F252: `test-sync-prompt-bootstrap.sh` keeps the unanchored origin-URL SKIP after 102's
  `self_test_subject`, which undoes F132's anchoring there.
- F253: `allium-check-hook.sh` counts errors by a `severity` key, so a schema rename passes
  silently. A non-numeric timeout turns off its bound.
- F254: `validate-fixture-map-ids.sh` resolves the project from the caller's cwd, and it reports
  "clean" over `scenario-map-rows.sh` exit 4 (malformed rows skipped).
- F255 (suspected): template-identity's root-commit check fails on a shallow clone, so the
  supply-chain pin tests can skip green.

## 3. Scenario-map reconciliation

Not applicable. The template has no language marker and no `specs/SCENARIOS.md`, as at H1–H6.

## 4. Mutation spot-check

The suite pass's `--full` ran the default table with today's seed (20261117), 12 mutants per
module. The headline was 88.0%. Three modules were under 80%:

| Module | Killed |
|---|---|
| `project-maintenance.sh` | 8/12 |
| `project-freshness.sh` | 9/12 |
| `template-autosync.sh` | 9/12 |

13 mutants survived in total, recorded as F256. They are the same class as F230: a fresh seed
draws new sites.

The default table leaves out two of the most-changed shell modules since H6. A custom
`MUTATION_TARGETS` table covered them, with seed 7 (H6 used 6). The Python guards that 101 changed
most have no mutation gate yet (F231, row 109).

| Module | Killed | Finding |
|---|---|---|
| `template-identity.sh` | 8/8 | none |
| `validate-fixture-map-ids.sh` | 9/12, +1 timeout | F257 |

The spot-check scored 17/20 (85.0%), above the 80% break. The timed-out mutant does not count as
a kill. The survivors at :230 and :234 sit on the exit-4 path F254 describes, so a test there
would close both.

## Carve budget

No row was carved. The register is at a convergence stop (ratio 1.31), and F247–F257 wait for the
next findings review. F256 and F257 fit row 109. F247 and F248 fit row 108's parser area, and
F249, F252 and F255 fit row 106's sync parity. Folding them is the developer's call at that review.
The one in-place fix was the jq fail-open in `test-hook-channels.sh`.
