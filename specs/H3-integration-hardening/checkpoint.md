# H3 — integration-hardening checkpoint (template repo)

Third checkpoint. It covers what was ticked since H2 (4d8dd3b): 080, 081, 082, 083 and 084, plus
020 and 075, which closed in the same window. `checkpoint-cadence.sh` reported `since=H2 count=5
due=1`.

## 1. Full-system regression

All 86 `scripts/test-*.sh` ran one at a time under bash, with a 900 s cap per file.

- 86/86 green in 875 s, first run. Unlike H1 and H2, no seam red came out of the new rows.
- The slowest were `test-validate-scenario-traceability.sh` (166 s), `test-bash-write-guard.sh`
  (58 s) and `test-project-maintenance.sh` (47 s).
- `test-stryker-guard.sh` passed here, though F086 records it red on this machine at 031e24c. F086
  stays open: one green run doesn't show the pid-cwd read is fixed.
- The working tree was clean afterwards, so no suite wrote into the repo.

## 2. Cross-cutting security sweep

`project-freshness.sh` came back clean: no verified credentials, and no key material beyond the 3
allowed hits. osv-scanner is still not installed, and the template has no lockfiles, so nothing was
left unscanned.

The `security-scanner` agent ran in "assume it's exploitable" mode against the seams between the
rows. It had no shell, so every claim below marked reproduced was reproduced here by hand.

Fixed in place, red first:

- The Bash pre-layer missed most redirect spellings. The lookbehind that kept `2>&1` from reading
  as a write to a file called `1` also dropped `1>`, `&>`, `>&`, `>|` and `exec 3>`. Each one wrote
  `src/App.cs` with the pre-layer silent. The post-layer did catch it, after the write. The parser
  now reads every redirect spelling and skips only fd duplication (`2>&1`, `>&2`, `3>&-`). New
  fixture `fdforms`: 10 checks, 5 of them red before the fix.
- The opaque pass hit its cap in silence. The hook built its "the rest are UNCHECKED, not cleared"
  sentence into `$OVER` and never printed it. It now goes into the deny reason, and into a
  `guard_announce` when nothing in the checked part was refused. New fixture `opaquecap`, red
  before the fix.

Recorded as F090–F097:

- F090 (reproduced): an empty file at `src/app/.git` ends the root walk at `src/app`. The
  spec-interview and pipeline-state guards then allow `src/app/main.py`. The same walk is copied
  into three more guards.
- F091: Claude can grant suite trust itself, through `--trust --yes`, a `MAINTENANCE_TTY` file, or
  a direct write to `.git/claude-trusted-commands`.
- F092: suite trust hashes the `.suite-command` line, not the test files it loops over.
- F093: acceptance-case grandfathering reads the committer date, which `GIT_COMMITTER_DATE`
  forges.
- F094: `acceptance-cases.sh --confirm` accepts any quote, so nothing ties it to the developer.
- F095: cloud results are unauthenticated, and the project placement table can send the secret
  scan to the cloud.
- F096: gaps in the source-extension list, and trailing-dot and trailing-space names on NTFS.
- F097: the template-origin match is unanchored.

F090, F091, F093 and F094 share one cause: a gate trusts state that Claude can write. They are
proposed as one hardened row, F098 `guard-trust-anchors`. The proposal review flags
`src/app/main.py` as a missing citation. That path is the reproduction fixture, not a repo file.

Checked and holding: the loopback check in `quality_gates.py`, the `cloud-maintenance.sh` results
parser, the jq-missing and `..` paths in `guard-lib.sh`, and the `acceptance_cases.py` cache.

## 3. Scenario-map reconciliation

Not applicable. The template has no language marker and no `specs/SCENARIOS.md`, the same as at H1
and H2.

## 4. Mutation spot-check

Stryker has no bash target, so this is the H1 and H2 method: a sampled operator-mutation pass,
stratified by operator, 12 mutants per module, seed 3 (H2 used seed 2). Each module ran in its own
detached worktree under `$HOME`, with the full test set green at baseline first, and every test
under bash.

| Module | Commits since H2 | Killed | H2 | Finding |
|---|---|---|---|---|
| `template-autosync.sh` | 7 | 5/12 (42%) | 3/12 | F099 → row 085 |
| `project-maintenance.sh` | 5 | 6/12 (50%) | 7/12 | F100 → row 085 |
| `spec-interview-guard-hook.sh` | 2 (080, 083) | 8/12 (67%) | — | F101, F102 |

- The autosync survivors include the claimed-vs-parsed count check again (L2734), which H2 also
  found alive. Row 085 already owns these two modules, so F099 and F100 list the survivors for it.
- The guard was picked over `quality_gates.py` (3 commits) because it is the gate 080 and 083
  changed. `has_match` survives in both directions, so no fixture covers a project whose only
  marker is `*.csproj` or `*.sln` (F101).
- Two `exit 0 → 1` mutants in the guard survive. The CLI only parses a hook's JSON on exit 0, so
  that deny would be dropped. Nothing asserts a guard's exit code (F102).
- No timeouts this time.

## Carve budget

No row was carved. 13 findings were recorded (F090–F102), and one consolidated proposal (F098) is
up for the developer's decision at this stop.
