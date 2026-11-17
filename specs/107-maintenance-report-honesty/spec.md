# 107 — maintenance report honesty

Track: spec-only. No risk domain, no new entity, state machine or concurrency. The change touches
four production scripts (`project-maintenance.sh`, `register-similarity.sh`,
`register_similarity.py`, `test-worktree-root-detection.sh`) plus their tests, under the ≥ 6 file
hardening trigger. Findings: F180, F181, F191, F200, F201, F202, F204, F224, F225, verbatim in
`specs/FINDINGS.md`.

## Problem

`scripts/project-maintenance.sh` is the only report a project gets about its own health, and in
four places it says less than it measured or runs longer than anyone can wait for.

| Finding | What happens today | Where |
|---|---|---|
| F181, F224 | A red suite is reported with its last 12 lines. The template suite prints one line per script, so a `FAIL` early in the list is cut off and the report says `failed (exit 1)` and names no test (2026-10-04 and 2026-11-16). | `SUITE_TAIL`, section 7 |
| F202 | Every finding and note sits in a shell variable printed on the last line. `timeout 14400 bash project-maintenance.sh --full --suite` on agentcrm wrote a 0-byte log after four hours. | `add`, `note`, verdict |
| F204 | With no project runner, `--full` runs bare `dotnet stryker` with no bound. On agentcrm one run took the whole four hours and produced no score, so the CORE self-tests and the suite never ran. | section 5, `MUT_EXEC` |
| F191 | A ratchet exiting 77 is a note with no count and no limit, so a ratchet can skip itself forever without a finding. With no `timeout`/`gtimeout`, ratchets run unbounded, even under `--unattended`. | section 6e |
| F200 | The duplicate-row scan runs without `--dir`, so it reads `$HOME/repos/*/` and never this project when the project lives elsewhere (agentcrm in `~/Github`). It still stamps `similarity`. | section 3d |
| F201 | `--open-only` drops every ticked row before pairing, so it can never report an open row that duplicates finished work, the question the scan exists to answer. agentcrm: 12 open rows, 0 pairs; full corpus, 4 pairs. It also drops `[/]` rows. | `register_similarity.py load_rows` |
| F180, F225 | `install-guard-notice-mod.sh` and `test-guard-notice-mod.sh` are mode 100644. `test-worktree-root-detection.sh:7` runs `cd "$(dirname "$0")/.."` without `CDPATH=`. | git index, line 7 |

## Requirements

- **R1 — A red suite quotes every failure line (F181, F224).** When the suite is reported failed
  or aborted, the finding quotes every output line that starts with `FAIL`, `TIMEOUT`, `not ok`,
  or (after leading space) `Failed `, up to 40 lines, then `… and N more failure line(s)`. After
  that it quotes the last 12 lines under `last lines:`. With no failure line, the report keeps
  today's 12-line tail.
- **R2 — An interrupted pass still reports (F202).**
  - (a) Every `add` and `note` is also appended, as it happens, to `<git-dir>/maintenance-report.partial`.
    The pass truncates the file at its start and removes it when it reaches the verdict. A pass
    that is killed outright (SIGKILL) leaves the file behind as evidence.
  - (b) On TERM, INT or HUP the pass prints `project-maintenance: INTERRUPTED by SIG<name> — partial
    report, N finding(s) before the stop`, then every finding and note it has so far, then a line
    saying nothing was stamped. It exits 128 + the signal number. It writes no stamps, since stamping
    only happens after the verdict.
  - (c) Outside a git repository there is no partial file. The trap still runs.
- **R3 — The mutation step is bounded (F204).** Every mutation command runs under
  `timeout -k 30 $MAINTENANCE_MUTATION_TIMEOUT` (default 7200 s, a non-number falls back to the
  default) when `timeout` or `gtimeout` exists.
  - Exit 124 or 137 from the bound is `[MUTATION] UNMEASURED — \`<cmd>\` did not finish within Ns`.
    It is a finding, it is not stamped, and it names the variable.
  - With neither binary, bare `dotnet stryker` and `npx stryker run` are refused:
    `[MUTATION] NOT RUN — no timeout or gtimeout to bound …`. A project runner
    (`run-mutation-gate.sh`) still runs, since it bounds itself by contract, and a note says the
    pass could not bound it.
- **R4 — Ratchet skips are counted and capped (F191).**
  - (a) The exit-77 note says `N of M ratchet(s) skipped, precondition absent (exit 77)`, where M
    counts the ratchets that were started.
  - (b) Each ratchet's run of consecutive exit-77 passes is kept in `<git-dir>/claude-ratchet-absent`,
    one `<count> <file name>` per line. Any other exit, including a timeout, resets it. At
    `MAINTENANCE_RATCHET_ABSENT_CAP` passes in a row (default 5), the ratchet becomes a finding:
    `[RATCHET] scripts/X has skipped itself (exit 77) on N passes in a row — it has not run since`.
    Outside a git repository nothing is tracked and the note says so.
  - (c) `--unattended` with neither `timeout` nor `gtimeout` runs no ratchet. It reports one
    finding, `[RATCHET] NOT RUN — --unattended and no timeout or gtimeout …`, naming the count.
    Attended runs keep the existing "ran unbounded" note.
- **R5 — The duplicate scan reads this project, against its finished work (F200, F201).**
  - (a) Section 3d passes `--dir "$PWD"`. Cross-project scanning stays a manual run (no `--dir`).
  - (b) `--open-only` embeds every row and reports only pairs where at least one row is open
    (`[ ]`, `[/]`, `[!]`). Two ticked rows are never reported. The pairing filter is one pure
    function (`pair_wanted`), tested without Ollama.
  - (c) The stderr header says `N rows (M open)` under `--open-only`.
- **R6 — Mode and portability (F180, F225).** `test-worktree-root-detection.sh` uses
  `CDPATH= cd`. The two mod files' mode bits are the developer's to set: the mod guard (095a)
  refuses the agent. They go in the status summary as a `!` command, not in a commit.
- **R7 — Tests.** A `[107]` case per behaviour in `test-project-maintenance.sh` (R1–R5a) and
  `test-register-similarity.sh` (R5b, R5c), each failing against the pre-107 script.

## Non-goals

- Changing what counts as a ratchet failure, or what exit 77 means.
- Rewriting the report as a stream to stdout. Sections that add a finding late (the verdict counts)
  still print in the same order; R2 adds evidence, not a new format.
- Bounding the CORE self-tests or the suite: both already have bounds (spec 093).
- Cross-project duplicate scanning inside the pass.

## Scenarios

Harness-only spec: no user-facing scenario map row. The behaviours above are the cases, each
pinned by a `[107]` test.

## Clarifications

### Session 2026-11-17

- Q: Should the mutation bound apply to a project runner too? → A: Yes. The runner bounds its
  passes; this bound is the outer guard against a runner that does not. The default (7200 s) sits
  above every measured runner (fundit's longest, 41 min).
- Q: Does a timed-out ratchet reset the exit-77 streak? → A: Yes. It started, so its
  precondition was present.
- Q: Partial report location? → A: the git dir, beside the trust store. It is never committed and
  never synced.
- Q: Does `--open-only` in `--text` query mode change? → A: No. A query is compared against every
  row, as today.
