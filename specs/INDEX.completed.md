# Completed-spec retrospectives (archive)

Rows verbatim as they read at tick time. Never pipeline input.

## 058 — write-guard-resolves-paths-against-the-wrong-root

Ticked 2026-09-30.

- [x] 058 — write-guard-resolves-paths-against-the-wrong-root — spec-only — `bash-write-detect` ignores a command's own `cd`, and reads any token ending in a source extension (a git URL) as a file. Reproduced twice, 2026-09-25. Diagnosis: `specs/INDEX.pending.md`

**Done.** `bash_write_targets.py` resolves each relative target against the `cd` in force where it appears (`cwd_resolver`): a `cd` inside `( … )` ends with its parenthesis, and a `cd` to a runtime directory (`cd "$T"`, `cd -`) makes relative targets after it unresolvable. That is the declared bound `$DIR/x` already had, and the post-layer still watches the filesystem. Heredoc bodies are now blanked, not removed, so offsets hold. A token holding `://` is a URL and never a target (F237). `test-bash-write-guard.sh cwd`: 9 expectations, 5 red before. Full harness 126/126.

**Reproduced twice while working the T0 row it was filed from, 2026-09-25.** Both times the command
ran in `/home/daol/repos/Claude` or a scratchpad directory and the guard named a path in agentcrm:

- `cd /home/daol/repos/Claude && python3 - <<'PY' ... p="scripts/validate-scenario-traceability.sh"`
  → *"Target: /home/daol/Github/agentcrm/scripts/validate-scenario-traceability.sh"*.
- `cd "$T" && ... > scripts/finding.sh` where `$T` was a scratchpad fixture
  → *"Target: /home/daol/Github/agentcrm/scripts/finding.sh"*.

Neither command could touch agentcrm. The guard takes a relative path out of a command line and
joins it to the project root, ignoring the `cd` the same command line performs — so a relative write
to **any** other tree is judged as a write to this one. Absolute paths pass, which is why the defect
is survivable and why it has lasted.

The second arm (agentcrm F237) is the mirror image: a token that merely ENDS in a source extension —
a git URL, or free text like `whisper.cpp` — is read as a repo file and denied, including inside an
argument to `finding.sh`. One is a path that is not where it says; the other is not a path at all.

Both live in `scripts/bash-write-detect-hook.sh`. The honest fix is narrow: resolve against the
command's own working directory when one is established in the same line, and require a path-shaped
context (a redirect target, an argument to a writer) rather than an extension match anywhere.

## 059 — pipeline-state-guard-denies-during-a-merge

Ticked 2026-09-30.

- [x] 059 — pipeline-state-guard-denies-during-a-merge — spec-only — the tick moves "the active spec" on while the merge closing the previous row is still in flight, so the edit finishing it is judged against a spec with no artifacts. Diagnosis: `specs/INDEX.pending.md`

**Done.** While `MERGE_HEAD` exists, `pipeline-state-guard-hook.sh` passes a file that either side of the merge changed since the merge base (`git diff --name-only HEAD...MERGE_HEAD` and the reverse). A file neither side touched is judged as before, so an open `git merge --no-commit` does not get anything past the guard. If git cannot answer, the normal verdict applies. New CORE `test-pipeline-state-merge.sh`: 4 assertions on a real merge, 2 red before.

**From agentcrm F094, spec V1, 2026-09-08.** The guard fired on a one-line namespace fix to a
migration the *other* lane had just landed, while the merge closing the previous row was in flight.

The guard is not wrong about the rule; the hazard is ordering. Ticking a row moves "the active spec"
to the next one, and a merge that closes the previous row is finished *after* the tick — so any
source edit the merge still needs is judged against a spec that has not started and has no
artifacts. The work is legitimate and the guard has no way to see that.

`branch-per-spec-guard` already reads `MERGE_HEAD`, and `template-autosync.sh:721` does too, so the
precedent for "this repository is mid-merge" exists in two places. Decide whether
`pipeline-state-guard-hook.sh` should join them, or whether the tick should move later. Either
answer is fine; the current state — a guard that blocks the last step of a merge — is not.

## 061 — spec-criteria-numbering-reads-as-a-dangling-scenario

Ticked 2026-09-30.

- [x] 061 — spec-criteria-numbering-reads-as-a-dangling-scenario — spec-only — criteria numbered `SC-044-01` are read by the traceability gate as a reference to `SC-044`. `scenarios.md` warns against it; nothing enforces it. Diagnosis: `specs/INDEX.pending.md`

**Done.** The gate's hyphen alternative takes an optional `-<digit>…` tail, so a criterion `SC-NNN-NN` is one match and the id filter's `-x` drops it. It neither dangles nor covers its namesake. case47a/b were both red before; 47b shows the old gate silently covered the row. agentcrm has no `SC-NNNN-NNNN` range notation, so no real reference is lost.

**From agentcrm F208, 2026-09-18.** agentcrm spec 044 numbers its own success criteria
`SC-044-01 … SC-044-04`. The traceability extractor matches `\bSC-[0-9]+[a-z]?\b`, and `-` is not a
word character, so `SC-044-01` yields a reference to **SC-044** — an id the map does not have, which
surfaces as dangling.

`.claude/rules/scenarios.md` already warns against a second numeric SC- sequence and tells authors to
use letters; nothing enforces it, and row 007 solved the neighbouring case (spec-kit's own `SC-001`
criteria) by digit WIDTH, which cannot help here because the width matches.

Two candidate fixes, and they are not equivalent: refuse the shape in the gate (a reference
immediately followed by `-<digits>` is not a scenario id), or refuse it at the source (a checklist
gate on spec files). The first is cheap and local; the second stops the collision being minted.

## 062 — the-map-has-no-way-to-say-superseded

Ticked 2026-09-30.

- [x] 062 — the-map-has-no-way-to-say-superseded — spec-only — a row a later spec replaced is none of the four states the gates know. agentcrm wrote `⊘ superseded`, then retired both rows because no gate reads it. Diagnosis: `specs/INDEX.pending.md`

**Done — already decided.** `scenarios.md` has said since 2026-08-29 (`f20e097`) that a replaced row is written retired, with a `Superseded by spec N` pointer and status `—`. `test-scenario-map-index.py` enforces it. The row's premise that the template never decided was wrong, and agentcrm's H5 retreat was the documented answer. One sentence added that names `⊘` as not a fourth status.

**From agentcrm F270 / F279 / F330 / F334, 2026-09-21.** `scenarios.md` defines three statuses —
`☐ mapped`, `◐ tested`, `✓ validated` — plus retired (`~~SC-nnn~~`, status `—`). A row that a later
spec **replaced** is none of those: it was validated, the behaviour is gone, and the replacement has
its own id.

agentcrm documented a fourth, `⊘ superseded`, in its own map header, and then could not use it:
`test-scenario-map-index.py` reads the tally alternation `✓ *|✓ int|✓|◐|☐` and nothing else, so an
index stating `⊘` cannot match the file. Both rows that had carried `⊘` were retired at H5 instead,
each keeping the history in its text — `_(retired at H5; had carried ⊘.)_`.

That retreat may well be the right answer, and that is the point: **the template has never decided.**
Either the gates learn a fourth status, or `scenarios.md` says plainly that retired-with-a-pointer is
how a superseded row is written, so the next project does not spend a spec rediscovering it. Row 036
already taught the alternation `✓ int` once, so the mechanism is known.

## 063 — e2e-startup-has-no-declared-port

Ticked 2026-09-30.

- [x] 063 — e2e-startup-has-no-declared-port — spec-only — `webServer` appears nowhere in the template, so each project invents its own startup: agentcrm holds the web port in four places and has no `webServer` key. Diagnosis: `specs/INDEX.pending.md`

**Done.** `.claude/docs/testing.md` has a new section, "The app under test starts from one declared port". One `WEB_PORT` module is read by vite, the tests and any backend setting. `webServer` runs with `--host --port --strictPort` and `reuseExistingServer`, and a .NET API gets a second array entry with its own health `url`. This is documentation only, since the template ships no Playwright config of its own.

**From agentcrm F205, 2026-09-18.** `webServer` appears nowhere in the template — not in
`.claude/docs/testing.md`, not in any rule — so every project invents its own browser-suite startup.

agentcrm holds the web port in **four** independent places: `vite.config.ts`,
`appsettings.Development.json` (`Tenancy:PublicLinkPort`), `playwright.config.ts` and
`tests/e2e/support/urls.ts`. Its `playwright.config.ts` has no `webServer` key at all, so the server
is started by hand and three values are kept in sync by memory. A fourth value, `--host`, is needed
because without it vite listens on `::1` only and `crm-*.agentcrm.localhost` gets ECONNREFUSED over
IPv4. That combination cost four runs in one evening.

`strictPort` makes the drift loud but does not remove the duplication. What the template can offer is
the shape: one declaration that feeds all consumers, plus a `webServer` block with
`reuseExistingServer` so the suite starts what it needs and does not fight a running dev server.

## 064 — a-sabotage-arm-is-not-surgical

Ticked 2026-09-30.

- [x] 064 — a-sabotage-arm-is-not-surgical — spec-only — `test-validate-scenario-traceability.sh` arm `l` breaks `case1-clean` too, so it proves nothing and the suite is 1-red on every run. Predates 2026-09-25. Diagnosis: `specs/INDEX.pending.md`

**Done — no longer reproducible.** With this commit, the full traceability suite runs 53/0/0 with sabotage enabled, and arm `l` is surgical (case1-clean survived all 15 arms). The commit touches neither roots discovery nor its fixture. On `7bab5a5` the suite was red for another reason: case40a caught 054/060's own comments naming real SC ids in two CORE scripts, and it skips the whole sabotage step once anything is red. That is fixed here too. The commit between `5d32990` and `7bab5a5` that made `l` surgical was not bisected.

**Found while running the suite during agentcrm's T0 pass, 2026-09-25**, and confirmed to predate the
session's own changes by re-running against `HEAD` (39 passed · 1 failed · 2 inconclusive, both
before and after).

`scripts/test-validate-scenario-traceability.sh` checks its own teeth by sabotaging a copy of the
gate one marked region at a time, then asserting that the right cases go red **and** that
`case1-clean` survives. Arm `l` replaces the roots-discovery region with the constant `ROOTS="tests"`
— and `case1-clean` breaks too, so the arm proves nothing about the defence it targets and the suite
reports a failure on every run.

The script's own comment at that arm ("tests DO live in tests/ this sabotage is invisible") says what
was expected; the fixture evidently does not satisfy it. Either the fixture grows a root outside
`tests/` so the sabotage becomes surgical, or the arm is retired with a line saying why. **A suite
that is permanently 1-red is a suite whose next real red goes unread**, which is the failure this
whole file exists to prevent.

## 054 — finding-ids-collide-across-lanes

Ticked 2026-09-30.

- [x] 054 — finding-ids-collide-across-lanes — spec-only — `finding.sh` numbers by COUNTING the local ledger, so two lanes mint the same F-id and a resolved row lets the next reuse a number. agentcrm: F141–F143 named six findings. Diagnosis: `specs/INDEX.pending.md`

**Done.** `finding.sh --add` takes the highest F-id, never a count, from `scripts/max-id-in-refs.sh`: the working tree (uncommitted and untracked included), every `FINDINGS*.md`, and every local and remote-tracking branch in one `git grep`. A pushed spec branch in the other lane is counted before its merge; a deleted line no longer frees its number while any ref holds it. Residual, stated in the helper: an unpushed branch or a stale fetch. `test-max-id-in-refs.sh` 12 cases, two-lane repro included; `test-finding.sh` 73/73.

**Two defects in one line.** `scripts/finding.sh` allocates by counting:

```
N=$(grep -cE '^- \[[ x]\]' "$LEDGER"); N=$((N + 1))
```

That is a count of ROWS in the LOCAL file, so:

1. **Two lanes collide.** Each branch counts its own ledger and both mint the same next id. Proven on
   agentcrm 2026-09-17: `origin/main` carried F141 (a person's name missing, spec 034), F142
   (DemoPhotoTests red on clean main) and F143 (language links too small), while the branch
   `spec/044-named-refusals` carried a different F141 (FeedRunner:191 stale guard), F142 and F143.
   Three numbers, six findings. `merge=union` on `FINDINGS.md` keeps both sides without a conflict
   marker, so the collision is **silent** — `validate-register-ids.sh` protects the register and
   nothing protects the ledger. The three branch ids were moved to F202–F204 by hand at the merge.
2. **A deleted row reuses a number**, even in one lane, because the count falls when a line goes.

The fix is the one the register already uses: read the highest id, not the count, and read it in
this branch AND in `origin/main` — `next-register-id.sh` does exactly that for rows and is the
model. Both halves need it; fixing only the first leaves the reuse.

## 060 — sc-ids-have-no-allocator

Ticked 2026-09-30.

- [x] 060 — sc-ids-have-no-allocator — full track — rows have `next-register-id.sh`; scenario ids have nothing, so every parallel merge collides. agentcrm: 47 collisions, 26 from two lanes taking one range. Diagnosis: `specs/INDEX.pending.md`

**Done.** `scripts/next-scenario-id.sh [--count N] [--prefix X]` appends past the highest map-row id (struck rows included, prose and flowchart mentions ignored) across the working tree, `SCENARIOS*.md`, `scenarios/*.md` and every local and remote-tracking ref, via the same `max-id-in-refs.sh` as 054. Width follows the map and grows past SC-999 to SC-1000 — the allocation half of 048; 048's gate half stays open. `scenarios.md` says never pick an SC-id by eye. `test-next-scenario-id.sh` 13 cases, including the agentcrm SC-1625..1650 two-lane shape. agentcrm answers SC-2485.

**Root cause, not a tidy-up.** Register rows have `scripts/next-register-id.sh`, which appends past
the highest id in the register AND in every `INDEX*.md` archive beside it. Scenario ids have no
equivalent, so every lane picks by eye and every parallel merge collides.

agentcrm measured **47 colliding ids on 2026-09-21**. Twenty-six were specs 052 and 055 in one
window: both lanes took SC-1625..SC-1650 independently and met in the merge. The same defect
produced S1 (104 ids), S2 (13) and F196 (`fragor.md` numbered by hand). Twenty-one older collisions
span both lanes' specs — 017/017b (4), 008b/022 (3), 055/063 (3).

**A cleanup without an allocator recreates the defect at the next parallel spec**, which is the
reason this is a row rather than a chore. Row 048 (the three-digit id space is full) is the adjacent
problem and wants deciding in the same pass: an allocator that mints `SC-1000+` settles both.

## 044 — traceability-gate-cannot-tell-zero-from-broken

Ticked 2026-09-30.

- [x] 044 — traceability-gate-cannot-tell-zero-from-broken — spec-only — `validate-scenario-traceability.sh` already exits 4 when a root is MISSING, because zero references renders as 'every claimed scenario is uncovered' — a catastrophic report with a trivial cause. The same is true when a root EXISTS and the scan returns nothing, and there the script reports `coverage: 0 of N` instead. Seen once in fundit (0 of 182, then 175 of 182 unchanged minutes later, with 2146 TLC scratch files under `tests/`); cause unproven, and NOT binary-ness — the `-a` is deliberate and documented. Fix the reporting, not the guess: no ids found anywhere is a broken scan, so refuse.

**Done.** `scripts/validate-scenario-traceability.sh`: when the map claims a ✓/◐ row and no file under any existing root names an id, the gate exits 4 instead of printing `coverage: 0 of N`, naming each root with its file count and the scan's own stderr (no longer sent to /dev/null). A map claiming nothing stays a normal run. The extractor's stderr (file:line of every refused row) is now printed, and the partial-read line gives the refused count and points "above" only when something is there (agentcrm F316, from `INDEX.pending.md`). New region `zero-refs-guard`; a missing root now has two defences, proven by sabotage arms f/n/o. Harness 47 -> 50 cases, 15 surgical arms. The fundit cause stays unproven.

## 043 — mutation-gate-reports-a-headline-only

Ticked 2026-09-30.

- [x] 043 — mutation-gate-reports-a-headline-only — spec-only — `run-mutation-gate.sh` passes `--reporter progress`, and a CLI reporter REPLACES the config's list, so no json report is written and per-module scores cannot be read. `spec-hardening.md` gates on the changed critical MODULE. Found in fundit 006: headline 88.21% PASS while PushEndpointPolicy (SSRF decision) killed 65.79%. Fix: add `--reporter json` + print every module under the break. (CORE half settled by 045: project-local by design — do NOT land it here.)

**Done.** `scripts/project-maintenance.sh` §5 reads every `mutation-report.json` / `mutation.json` newer than a marker touched before the run, merges them per mutant (detected in any report = detected), and lists each file with valid mutants under the limit, lowest first. A passing headline over such a module is a finding; a failing one carries the list. A scored run with no report says the module gate is unmeasured and names `"json"` in `reporters`. The row's runner premise was stale on measurement: neither fundit nor rocky passes a CLI reporter and every config lists json. C54-C62, 133 -> 154; 8/8 hand mutants killed.

## 035 — a11y-suite-runs-at-one-viewport-only

Ticked 2026-09-29.

- [x] 035 — a11y-suite-runs-at-one-viewport-only — spec-only — maintenance §6d reports a Playwright config with no narrow viewport as [VIEWPORT]; testing.md puts the width in the shared config. Verbatim in `INDEX.completed.md`.

**Done.** `scripts/project-maintenance.sh` §6d judges each `playwright*.config.*` alone: no width below 480px, no phone device and no `narrow-viewport: not-applicable` comment make a `[VIEWPORT]` finding. A .NET-only suite falls back to test files. `testing.md` has a Viewports subsection (shared config project, NUnit fixture per width, overflow assertion). C46-C53 + C51b, 133/133. First pass flags fundit, agentcrm, ighweld-2026 and hireflow.

**Original row:**

- [ ] 035 — a11y-suite-runs-at-one-viewport-only — spec-only — the shared a11y/visual template asserts at the default 1280px, so a horizontal-overflow defect shipped in fundit spec 001 and survived until spec 004 measured 375px by hand. A viewport dimension belongs in the shared suite, not per spec. Reported by fundit F024.

## 034 — freshness-reports-seven-bogus-lockfile-skips

Ticked 2026-09-29 without new code. Commit 774a909 (2026-09-09), four days after the row was filed, had already landed the fix.

- [x] 034 — freshness-reports-seven-bogus-lockfile-skips — spec-only — already fixed by 774a909: a workspaces member is reported as covered by its root's audit. fundit now shows 0 SKIPs over 15 members. Verbatim in `INDEX.completed.md`.

**Verified 2026-09-29.** `scripts/project-freshness.sh:655-686` walks up from a lockfile-less manifest to the nearest `package.json` that declares `"workspaces"` and has a lockfile, and reports the member as `[OK] npm workspaces member — covered by the audit of <root>`. On fundit, `--deps --no-install` prints 15 such lines under `src/web` and zero `[SKIP] No lockfile`. `test-project-freshness.sh` passes 146/146. C10 pins the member case, and its sabotage arm keeps a real lockfile-less package reported as a SKIP.

**Original row:**

- [ ] 034 — freshness-reports-seven-bogus-lockfile-skips — spec-only — project-freshness.sh prints `[SKIP] No lockfile` per npm workspace package; in a workspace only the root has one and it covers them, so seven noise lines sit where a real skip would hide. Reported by fundit F003.

## 030 — unlisted-fires-forever-on-an-optional-callee

Ticked 2026-09-29 without new code. Spec 045 (a4fe4ca, 2026-09-11) had already landed the fix, as F042.

- [x] 030 — unlisted-fires-forever-on-an-optional-callee — spec-only — superseded by 045: CORE files declare optional project scripts (`# template-autosync: optional-project-script`). Verbatim in `INDEX.completed.md`.

**Verified 2026-09-29.** `scripts/project-maintenance.sh:729-731` declares all three paths optional. `--unlisted` returns 1 (no findings) on rocky and on all 46 synced repos under ~/repos. `test-template-autosync-unlisted.sh` 31/31; AC-10/AC-11 pin the pair-scoped declaration.

**Original diagnosis:**

**Measured on rocky, 2026-09-05, during checkpoint H13.**
`scripts/project-maintenance.sh` is CORE and calls three project scripts —
`scripts/e2e-gate-census.py`, `scripts/e2e-wait-audit.sh`, `scripts/install-git-hooks.sh` — each
behind a `[ -f ]` test. Its own comment says so in as many words: "if it has neither they are a
silent no-op and cost one `test -f` each. They live here rather than in the project that uses them
because this file is CORE: a caller added downstream is deleted by the next sync."

So the caller is in CORE **on purpose**, and the callee is deliberately optional. `--unlisted` reads
the call as a dependency and reports all three, permanently, which holds `core-owed-tick-guard`
red on every tick this project will ever make. The block's own comment sets the standard it is
failing: "A detector whose output is permanently non-empty is not a detector."

**Corroborated, and distinguished.** `bc84617` fixed the same class in agentcrm, where
`lane-handoff.md` merely *named* `scripts/merge-locale-json.py` in prose — there the fix is to
delete the mention. Here the three are **called**, so deleting the reference deletes the feature.
Nor is shipping them the answer: `e2e-gate-census.py` and `e2e-wait-audit.sh` parse rocky's own E2E
ledger, and making them CORE would push them onto msroute, agentcrm, ighweld and the rest.

Scope: teach the detector to tell a **use** from a **dependency** — a reference guarded by a
presence test is the former. `install-git-hooks.sh` is separately worth considering for CORE on its
own merits; the other two are not.

## 028 — traceability-roots-declaration

Ticked 2026-09-04. Row as it read at tick time, plus the diagnosis.

- [x] 028 — traceability-roots-declaration — spec-only — the gate discovered top-level test dirs only, so a project with suites under `src/` was under-reported. Projects may now declare roots in `specs/traceability-roots`. Verbatim in `INDEX.completed.md`.

**Where it came from.** ighweld-2026 register row 173 (`e2e-suite-integrity`), which batched twelve
rows about checks that report success without checking. Two of them (132, 149) were this defect seen
from inside one project; this is the fleet-wide half.

**The defect.** `validate-scenario-traceability.sh` discovers its reference roots from a candidate
list of top-level directories — `tests test e2e __tests__ cypress playwright` — and deliberately
excludes `src/`, on the correct ground that a source comment naming an id is not a test. A project
whose test trees are neither top-level nor reachable by widening that list therefore could not be
served at all. ighweld keeps ~3,500 xUnit tests under `src/welding/Welding.Api.Tests/` and ~1,345
vitest suites under `src/welding/client/src/**/__tests__/`.

**Measured on ighweld, 2026-09-04, both directions:**

| | discovered roots | real roots |
|---|--:|--:|
| coverage | 443 of 814 | 518 of 814 |
| dangling | 4 | 11 |

The second row is the finding worth keeping. ighweld's own row 149 stated in writing that the blind
spot was one-way — *"an id named by an unscanned test simply is not seen at all, so nothing is being
falsely reported as covered; the error is one-way"* — and that is wrong. Seven dangling ids
(`SC-011`…`SC-019`) were concealed by the narrow roots, i.e. seven broken references that the gate
could not report because it could not see the tests that made them. A gate under-reporting its
coverage trains readers to discount the number; a gate hiding broken references is worse, and it was
doing both.

**The fix.** An optional per-project declaration at `specs/traceability-roots` — one root per line,
`#` comments and blanks ignored. Precedence, most specific first:

1. `--roots` — the caller's promise, for one invocation.
2. the declaration — the project's promise, for every invocation.
3. discovery — the fleet default, unchanged.

Two properties carried over from the existing design rather than invented:

- **A declared root that does not exist refuses** (exit 4), through the untouched `root-guard`. That
  guard already drew the distinction: discovery *skips* an absent candidate because a candidate is a
  guess, while `--roots` refuses because it is a promise. A declaration is a promise, so it refuses.
- **An empty declaration refuses rather than falling through to discovery.** A file of nothing but
  comments must not become a route to the "0 of 0, all clear" report this script is named after.
  That is the sabotage direction that mattered most, and it has its own case.

The report line now says where the roots came from — `(--roots)`, `(declared in
specs/traceability-roots)`, `(discovered)` — because a reader looking at a low coverage figure needs
to know whether they are seeing a project's declaration or the default having guessed.

**Additive by construction.** A project without the file behaves exactly as before; `case39` asserts
that rather than assuming it. Same property that let the two-lane logic ship enabled.

**Tests.** Five cases (35–39) and a sabotage arm (`m`, `roots-declaration`) that neutralises the
region and confirms cases 35 and 38 go red. 40 passed, 0 failed. The sabotage arm matters here for
the reason the `roots-discovery` one does: on any project whose tests live in `tests/`, this whole
feature is invisible, so nothing else in the suite would notice if it stopped working.

## 001 — carve-budget

- [x] 001 — carve-budget — full track — the register has to converge: a finding is fixed in place, carved (max 2/spec, depth 2), or declined in writing. Detalj: specs/INDEX.completed.md

## 002 — dotted-sub-spec-ids

- [x] 002 — dotted-sub-spec-ids — spec-only — `spec_active.py`'s numeric grammar did not know `501.1`/`450.7`, so 22 of rocky's 123 rows were unclassifiable and both PreToolUse guards failed closed on them. Detalj: specs/INDEX.completed.md

## 003 — archiver-refuses-real-registers

- [x] 003 — archiver-refuses-real-registers — spec-only — `archive-completed-rows.sh` demanded a `## Specs` heading rocky never had, and its id shapes claimed to match `spec_active.py` while rejecting any letter-led id. Inert on two projects. Detalj: specs/INDEX.completed.md

## 004 — nightly-has-no-body

- [x] 004 — nightly-has-no-body — spec-only — three documents said the mutation gate runs nightly and nothing scheduled it, so it ran never. `install-nightly-maintenance.sh` is the crontab entry.

## 005 — lane-merge-cost-is-in-the-lists

- [x] 005 — lane-merge-cost-is-in-the-lists — spec-only — two lanes append to four markdown files and git calls every append a conflict; `union` on the append-only lists, `validate-register-ids.sh` as the backstop.

## 007 — traceability-gate-is-three-defects-in-one-script

- [x] 007 — traceability-gate-is-three-defects-in-one-script — full track — the two SC- namespaces split by digit WIDTH, not magnitude (a floor is useless on a map starting at SC-001); duplicates get exit 6. msroute 13 dangling → 0. Detalj: specs/INDEX.completed.md

## 009 — held-rows-have-no-archive

- [x] 009 — held-rows-have-no-archive — spec-only — the archiver told you to write a pending entry by hand and nobody did, so rocky ran 47 over-budget open rows. `--write-pending` makes the advice executable; rocky 131→39 KB. Detalj: specs/INDEX.completed.md

## 015 — sigpipe-validator-scans-only-self-tests

- [x] 015 — sigpipe-validator-scans-only-self-tests — spec-only — `--all` scans every script, `--strict` fails on them; the default population and its meta-test are unchanged. The gate was already RED here on 7 of its own self-tests, now fixed. Detalj: specs/INDEX.completed.md

## 018 — core-owed-tick-gate-goes-silent

- [x] 018 — core-owed-tick-gate-goes-silent — full track — the gate was never broken: the TEST used GNU `sed -i` on a BSD sed, so the tick never happened and the detector correctly said nothing. Portable `inplace()` helper; 89/89. Detalj: specs/INDEX.completed.md

## 019 — are-we-writing-this-row-twice

- [x] 019 — are-we-writing-this-row-twice — full track — nothing measured the question that opened the review: are we rebuilding what we already have. Local embedding pass over every register; found ighweld-2026 119/138, one job planned twice. Detalj: specs/INDEX.completed.md

## 025 — speckit-check-fired-on-the-template

- [x] 025 — speckit-check-fired-on-the-template — spec-only — the pass told this config repo to install spec-kit once it grew a register; now gated on a language marker, the predicate every other guard uses. Third not-applicable case today.

## 045 — unlisted-predicate-denies-a-tick-it-cannot-clear

- [x] 045 — unlisted-predicate-denies-a-tick-it-cannot-clear — full track — four defects in the CORE-ownership machinery, each already recorded in a project run-log and never landed here.

Found while trying to tick rocky's spec 495. `core-owed-tick-guard-hook.sh` denies a register tick
on any `--unlisted` finding, and rocky had three that no action could clear. The instruction the
deny prints — land it in the template and sync it back — was not available, because the right answer
was that the template must NOT ship these files. A gate whose only exit is the override protects
nothing; that is row H7bk arriving a second time by a second route.

**F042 — the predicate had no exit for a deliberately optional reference.** Its rule is "a CORE file
names it, so either the template ships it or the next sync deletes the reference". Sound for an
unguarded call, false for a guarded one: `project-maintenance.sh` section 6 runs
`scripts/e2e-gate-census.py` only `if [ -f ]`, and its own TEMPLATE NOTE explains that the caller
lives in CORE precisely so the sync cannot delete it while the script stays project-local. Nothing
vanishes and nothing is owed. `install-git-hooks.sh` was worse: it is never called at all, appearing
only inside a diagnostic string. Fixed with a declaration the referring CORE file carries —
`# template-autosync: optional-project-script <path>` — scoped to the **pair**, so file A declaring
it optional says nothing about file B calling it bare. It cannot be granted downstream: writing one
into a project moves that CORE file off its manifest hash and `[owed]` names it by the next session
start. A misspelled path matches no pair and the finding simply still fires — the safe direction.

**F041 — `run-mutation-gate.sh` was on `CORE_SCRIPTS` while two prose blocks said it is deliberately
not shipped.** The `TEMPLATE_ONLY_SCRIPTS` comment carries a whole paragraph about it under
"Project-local bounded runners"; `project-maintenance.sh` says "deliberately NOT a CORE script (see
the not-shipped list in template-autosync.sh)". The name went onto the last line of the wrong list
and sat there from 2026-09-04. Consequence: `--is-core` answered CORE, so `core-machinery-guard-hook.sh`
refused every edit to that path in every project, while the template had no bytes to copy and the
one place it could legitimately be authored was the one place it does not belong. Row 043 read the
symptom the other way round and concluded the file should be landed here; that clause is corrected
on the row rather than quietly contradicted.

**The inverse check that would have caught it now exists.** Template mode walked files and asked
whether the list names them; it never walked the list and asked whether a file is behind the name.
AC-13 pins it, and the negative control reproduces the exact week-long state.

**F044 — `mutation` was stamped on any `--full` run.** Including a run this same section had just
called unclassifiable, and including a project with no Stryker config and no runner where
`$MUTATION_CMD` is empty and nothing executes at all. The due-state then went quiet about a gate
nobody had measured. Its sibling twelve lines above already had this right and said why: a red suite
has not satisfied the obligation. Now stamped only when a score came back — a gate failing on the
NUMBER does stamp, because that is a measurement with a finding attached.

**F045 — the score contract between a CORE reader and a project-local runner was never written
down.** The classifier greps the phrase `mutation score`; rocky's runner printed `Score: 94.1%`,
every field correct and the phrase absent, so a completed gate was discarded as unreadable. Declared
in the branch that chooses the runner, and the unclassifiable message now quotes the contract rather
than sending the reader looking. Deliberately not fixed by widening the grep, which would start
reading numbers out of any tool that happens to be in the output.

**Gates.** `test-template-autosync-unlisted.sh` 21 → 31 (AC-10/AC-11 opt-out and its pair scoping,
AC-12 sabotage, AC-13 inverse); `test-project-maintenance.sh` 57 → 63 (C28/C29/C30 stamping).
Both new families negative-controlled: removing the opt-out lookup reddens AC-12 and restores the
declaring file as a referrer; removing the `MUT_MEASURED` guard reddens C29 and C30 while C28 stays
green, so the arms discriminate rather than both reading one thing. eol 36, owed 34, stranded 45,
core-parity 8, count-honesty 21, finding 13, maintenance-due 11 — all unchanged.

## 036 — index-tally-cannot-express-a-decorated-status

- [x] 036 — index-tally-cannot-express-a-decorated-status — spec-only — the split index's tally regex knew `✓ *` but not `✓ int`, so a map documenting its own integration-layer status could not be indexed at all: every index it could be given claimed `✓` where the file held `✓ int`. Found by ighweld-2026 spec 180.

## 006 — nothing-checks-the-design-gate-exists

- [x] 006 — nothing-checks-the-design-gate-exists — spec-only — the bare name RESOLVES to the plugin cache, so the naming half is refuted. What stands: nothing verifies the plugin is installed, so a BLOCKING gate fails silent without it. Diagnosis below; spec `specs/006-nothing-checks-the-design-gate-exists/`.

_Diagnosis, moved from INDEX.pending.md on tick:_

- [ ] 006 — nothing-checks-the-design-gate-exists — spec-only — corrected on measurement 2026-09-03.

_Row as it stood, and as it was wrong:_

- [ ] 006 — frontend-design-is-a-plugin-not-a-skill — spec-only — four CORE files call `frontend-design` as BLOCKING by bare name; it ships in the plugin cache, not `.claude/skills/`. Without that plugin the gate cannot fire and says nothing. Found by @david as agentcrm S20.

The row made two claims and only one survives.

**Refuted — the bare name resolves.** Measured from film-i-vast-demo, 2026-09-03, by
invoking `Skill(skill: "frontend-design")` and reading where it loaded from:

    Base directory for this skill:
    ~/.claude/plugins/cache/claude-plugins-official/frontend-design/0120fb83da5d/skills/frontend-design

The harness resolves an unqualified skill name against installed plugins, so the
nine files naming the bare form — `CLAUDE.md`'s BLOCKING line, `.claude/rules/frontend.md`,
`.claude/rules/design-references.md`, `.claude/docs/workflows.md`, `project-wizard`,
`scripts/ui-design-hook.sh`, `scripts/stop-validation-hook.sh`, `scripts/sync-prompt.md`
and the `settings.json` PostToolUse hook — are all correct as written. Renaming them to
`frontend-design:frontend-design` would be churn, and would break the day the skill moves
back out of a plugin.

The claim was never measured. It was inferred from the skill's absence in
`.claude/skills/`, which is true and irrelevant: `.claude/skills/` is not the only
namespace the Skill tool reads.

**Stands — nothing verifies the plugin is present.** The failure the row was reaching for
is real, one level in. Every caller above is prose telling a model to invoke a skill; none
of them checks it can be invoked. On a machine where the plugin is not installed —
a fresh clone, a second lane, a teammate who never ran `/project-wizard` Step 6 — the
`Skill` call fails, and the BLOCKING design gate degrades to nothing. No hook fires, no
gate reports, and the UI ships undesigned with a clean run log. That is the same shape as
row 004 (three documents said nightly, nothing scheduled it) and row 018 (the gate was
fine, its test never reached it).

Fix is a presence check, not a rename: one predicate that answers "is the design gate
reachable", called where the gate is already claimed to be enforced —
`scripts/ui-design-hook.sh` (PreToolUse, where the model is being told to invoke it) and
`scripts/project-maintenance.sh` (so a missing plugin is reported once a night rather than
discovered by a UI spec). `project-wizard` Step 6 installs it; the check is what notices
when Step 6 did not run or the cache was cleared.

Scope note: the same argument applies to every external skill the ruleset calls BLOCKING
by name. Enumerate them before writing the predicate — a check that covers only
`frontend-design` is the same gap with a smaller radius.

**The predicted machine exists, measured 2026-09-25** (agentcrm F281, then F296, confirmed again on
its second lane during the T0 pass). `frontend-design` is absent from `.claude/skills/`, absent from
`~/.claude/plugins/**`, and absent from the session's own skill list — `Skill` answers *Unknown
skill*. On this machine `CLAUDE.md`'s BLOCKING line and the eight other callers name something that
cannot be invoked, so the design gate has been silently inert for every UI spec this lane has run.
agentcrm spec 058 substituted `design-system/MASTER.md` plus the existing `Invoices.tsx` /
`Contracts.tsx` patterns and shipped, with nothing in the run log to say the gate never fired.

Worth recording rather than re-arguing: the refuted half above ("the bare name resolves") was
measured on a machine where the plugin happened to be installed, and read as a property of the
harness. It is a property of **that machine**. Resolution is per-machine, which is precisely why a
presence check is the only thing that can answer it — the standing half, now with the failing case
in hand instead of hypothesised.

## 022 — sync-version-marker-abandoned

- [x] 022 — sync-version-marker-abandoned — spec-only — only `sync-prompt.md` and `project-wizard` write `.claude/.sync-version`; autosync maintains `.claude/.template-sync`. Step 0 reads the stale one and reports "sync needed" on a current project. Diagnos: `specs/INDEX.pending.md`.

## 037 — sync-copies-nothing-under-zsh

- [x] 037 — sync-copies-nothing-under-zsh — spec-only — Step 5c iterates `for s in $CORE_SCRIPTS_LIST`; zsh does not word-split, so 105 names became one filename, 0 scripts were copied, and it reported `[OK] 0 core enforcement script(s) mirrored`. Diagnos: `specs/INDEX.pending.md`

## 046 — hooks-shout-at-the-developer-and-whisper-to-the-model

- [x] 046 — hooks-shout-at-the-developer-and-whisper-to-the-model — full track — every advisory hook emits `systemMessage` ("Warning shown to user in UI" per the CLI's own reference), so reminders addressed to the model land as red warnings in the transcript; and 42 hooks — including all four wired UserPromptSubmit pipeline reminders — emit top-level `additionalContext`, which Claude Code silently ignores. Both channels are backwards.

## 055 — findings-review-never-clears-its-due-state

- [x] 055 — findings-review-never-clears-its-due-state — spec-only — `--stamp findings` existed and nothing ever called it, so the banner said "never run in this project" through four reviews that decided 33 findings. Deciding a finding now stamps it. From agentcrm F078.

## 056 — the-pkill-rule-kills-the-shell-that-runs-it

- [x] 056 — the-pkill-rule-kills-the-shell-that-runs-it — spec-only — `dotnet.md` mandated `pkill -f "<abs>/src/X"`, which matches the running shell's own command line: probe died with exit 144 and the build never ran. Bracketed literal, verified both ways. From agentcrm F101.

## 057 — traceability-cannot-read-its-own-naming-convention

- [x] 057 — traceability-cannot-read-its-own-naming-convention — spec-only — the extractor matched only `SC-NNN`, while `scenarios.md:113` prescribes `Checkout_SC014_...` and a C# method name cannot carry a hyphen. agentcrm coverage 1716 → 1767 of 1824. From agentcrm F331.

## 073 — pipeline-refresh-2026-09

- [x] 073 — pipeline-refresh-2026-09 — spec-only — one sync engine for wizard/update/sync-template, spec-kit pinned, zsh + GNU fixes, supply-chain cooldowns, context diet, hook latency; then roll out to 15 projects. Folds 037, 022. User-requested 2026-09-28.

## 074 — measure-where-maintenance-should-run

- [x] 074 — measure-where-maintenance-should-run — spec-only — no maintenance run records its duration, peak memory or host, so local-vs-cloud placement would be a guess. Ledger per run + a placement report. Developer request 2026-09-29.

## 076 — malformed-id-deny-blames-a-healthy-register

- [x] 076 — malformed-id-deny-blames-a-healthy-register — spec-only — both PreToolUse guards deny a malformed active id (`7-x`) with the "resolver missing / register unparsable" text. Own exit 97 + text naming token and grammar. Found as consultpilot H7ai / Q2.

## 008 — scenarios-map-canary-unheeded

- [x] 008 — scenarios-map-canary-unheeded — spec-only — the canary gave a map INDEX.md remedies and recorded nothing: 17 map files over 25 KB, 4 named here. project-maintenance now records each in the project's FINDINGS.md with a remedy for its role.

Measured 2026-09-03 across all seven projects:

    consultpilot   682 KB  single-file   27x the canary
    agentcrm       252 KB  single-file   10x
    rocky          242 KB  SPLIT          9x
    film-i-vast    137 KB  single-file    5x
    fundit          30 KB  single-file    1x
    msroute          5 KB  SPLIT          under
    ighweld        (no map)

The row named only rocky and agentcrm until today, which is how film-i-vast's
137 KB came back as a fresh finding from a /project-update run that was right to
report it: nothing in that project's register pointed here, and this row did not
name it either. A row that lists two of five instances is a row that lets the
other three read as untracked.

Note rocky is ALREADY split and still 242 KB, so splitting is not sufficient on
its own — the index itself grows. msroute is the shape to copy: split, 5 KB.

Per-project work with its own spec, not a sweep: moving a map must not reword,
re-status or drop a row, and `scripts/scenario-map-rows.sh` +
`scripts/test-scenario-map-split.sh` are the pair that proves it mechanically.

Remeasured 2026-09-29, every project under ~/repos with a map, files over 25 KB:

    puck 439 · noisycricket-joucbox 145 · iskvalp 121 · teach 99 · emaljen 71 ·
    originalilluminati 70 · noisycricket-rmk 60 · rocky 54 (split index) · rundan 51 ·
    processhub 43 · consultpilot 43 (one feature file) · noisycricket-fundit 42 · juradrop 39 ·
    konsultradar 35 · noisycricket.se 33 · ighweld-2026 32 (one feature file) · lufia6 27

agentcrm, fundit and film-i-vast-demo are now under. The row named four and missed thirteen.
It was the second time a list kept here went stale, so the fix stopped keeping one. Spec 008 gives
a map file the remedy for its role and has project-maintenance.sh record each file in the owning
project's specs/FINDINGS.md, where the 5-spec review decides it. See specs/008-scenarios-map-canary-unheeded/.

## 077 — row-proposals-carry-their-need

- [x] 077 — row-proposals-carry-their-need — spec-only [hardened] — the freeze chosen 2026-09-29 needs teeth: a freeze line the hooks read, and row proposals recorded with evidence of need, checked (duplicate, stale citation) and put to the developer to approve or decline. Developer request 2026-09-29.

## 010 — autosync-test-writes-to-the-repo-it-tests

- [x] 010 — autosync-test-writes-to-the-repo-it-tests — full track [hardened] — `test-template-autosync-*.sh` writes into the working repo instead of a fixture, so a failing run can leave the tree dirty. Found by @johan as consultpilot H7bm.

## 011 — twenty-hand-written-sync-invocations

- [x] 011 — twenty-hand-written-sync-invocations — full track [hardened] — 19 hand-spelled sync calls in 6 drivers now go through one helper, `drive_sync`; the gate is a shell lexer with one rule, 4 argued exclusions, 27/27 sabotage arms. From consultpilot H7bo.

## 012 — core-file-comments-hold-real-scenario-ids

- [x] 012 — core-file-comments-hold-real-scenario-ids — spec-only [hardened] — 9 CORE scripts cited real SC-ids in comments; any gate reading scripts/ counted them, so a deleted test left its row covered. Now SC-NNN shapes; case40 runs the gate over every CORE script. From consultpilot H7bp.

Row as opened: - [ ] 012 — core-file-comments-hold-real-scenario-ids — spec-only — a CORE file's comments cite real SC-ids as examples, so the traceability gate counts them as references and a deleted row looks covered. Found as consultpilot H7bp.

Spec: `specs/012-core-file-comments-hold-real-scenario-ids/`. The live instance was consultpilot's validated sigpipe-sweep row. Only a `Covers:` line in `validate-no-sigpipe-assertions.sh` traced it (F021).

## 014 — autosync-adds-gates-no-runner-registers

- [x] 014 — autosync-adds-gates-no-runner-registers — spec-only — `scripts/core-gates.sh` is the CORE half of a gate registry: a new gate-shaped CORE script is a gate unasked, 6 argued non-gates (F004 closed). consultpilot had 14 unregistered; adoption is F022. From consultpilot H7av.

Row as opened: - [ ] 014 — autosync-adds-gates-no-runner-registers — spec-only — a sync that ships new `test-*.sh` scripts leaves every project's `run-gates.sh` reporting DRIFT until someone adds them to GATES by hand. Found as consultpilot H7av.

Spec: `specs/014-autosync-adds-gates-no-runner-registers/`. H7be's median-0-days registration latency no longer held: 14 CORE gates sat unregistered in consultpilot on 2026-09-29. No new query mode (the cap of four is a developer decision). A default project runs no CORE gate at all (F023).

## 017 — canary-and-row-budget-do-not-compose

- [x] 017 — canary-and-row-budget-do-not-compose — spec-only — the canary assumed the bytes were rows. `register-bytes.sh` splits INDEX.md into rows/history/prose and names only moves that exist: agentcrm gets "move prose", compliant msroute one info line. Fold is F024.

Row as opened: - [ ] 017 — canary-and-row-budget-do-not-compose — spec-only — every row can sit inside the 300-byte budget and the register still exceed the 25 KB canary: on msroute 90 archived-verbatim completed rows are 74% of the file. A compliant register with no next move. Found as msroute 007ck.

Spec: `specs/017-canary-and-row-budget-do-not-compose/`. Measured 2026-09-29: msroute 29 897 B, done rows 75%, 0 over budget → compliant, info line only. agentcrm 60 484 B, prose 55% → prose move first. Prose written inside the history section counts as prose, because the history archiver refuses it. The diagnosis carried in `INDEX.pending.md` until this tick:

**Second measurement, agentcrm, 2026-09-25.** The row was filed from msroute, where 90
archived-verbatim completed rows were 74% of the file. agentcrm is the same defect with the bytes
somewhere else entirely:

| part of `specs/INDEX.md` | bytes | share |
|---|---|---|
| the 111 spec rows | 26 212 | 44.0% |
| `## Register history` | 2 062 | 3.5% |
| **everything else inside `## Specs`** | **31 358** | **52.6%** |
| total | 59 632 | 2.4× the 25 KB canary |

Mean row 236 bytes; **one** row over the 300-byte budget. Both archivers report clean. So the
project is told every session that the file is too large, is pointed at
`archive-completed-rows.sh`, and that script correctly has nothing to do.

The "everything else" is prose written *inside* the Specs section: a two-lane explainer, dependency
tables, a file-conflict table, rule commentary. It is useful and it is not rows, and no gate in the
template has an opinion about it.

Two halves, and they are separable:

1. **The canary should measure where the bytes are** rather than assuming rows, and name the part
   that is large. `spec-register-orientation-hook.sh` already reads the file; the arithmetic above is
   four lines.
2. **The advice should follow the measurement.** Prose belongs in a sibling the pipeline does not
   read — `INDEX.history.md` and `INDEX.pending.md` are the precedent. Recommending the row archiver
   to a register whose rows already comply is advice that cannot be taken, which is how a banner
   becomes noise: agentcrm has carried this one, unactionable, every session since 2026-08-29.

`spec-register-orientation-hook.sh` is CORE (`template-autosync.sh:173`), so the fix lands here.
From agentcrm F201.

## 021 — core-set-excludes-docs-and-skills

- [x] 021 — core-set-excludes-docs-and-skills — spec-only — `--owed` is CORE-only on purpose: `[manual]` already names local doc/skill edits (4 in 45 projects, 0 purely owed). Both headers now say so; AC-13 pins the boundary.

Row as opened: - [ ] 021 — core-set-excludes-docs-and-skills — spec-only — `core_divergence` walks only CORE_SCRIPTS+CORE_RULES, so project-authored work under `.claude/docs/` or `.claude/skills/` is absent from `--owed` and a tick passes. Third gap after 018. Diagnos: `specs/INDEX.pending.md`.

Spec: `specs/021-core-set-excludes-docs-and-skills/`. Measured 2026-09-29: `[manual]` (007af, 2026-08-20) already reported both msroute files at every syncing run; the finder queried `--owed`/`--unlisted` only. Fleet: teach/radar/fundit `deployment.md`, msroute `workflows.md` — all project-specific, so gating the tick was rejected. The diagnosis carried in `INDEX.pending.md` until this tick:

`core_divergence()` builds its candidate set from `CORE_SCRIPTS` (prefixed `scripts/`) and
`CORE_RULES` (prefixed `.claude/rules/`). Nothing else is asked about. So a project-authored
change to a template-owned file under `.claude/docs/` or `.claude/skills/` is not
under-reported — it is absent from the question, the same structural shape the `[unlisted]`
block already names for scripts the template has never shipped.

Measured on msroute, which reported `--owed` empty and `--unlisted` empty while carrying two:

- `.claude/docs/conventions.md` — an OOM-catch convention with `OomCatchConventionTests`
  behind it (msroute 007bm).
- `.claude/skills/allium/SKILL.md` — `exposes: a, b` comma lists are rejected by allium-cli,
  measured 2026-09-02.

Both hash-differ from `.claude/.template-sync`, so by the rule's own definition of owed they
are owed. `core-owed-tick-guard-hook.sh` consults `--owed`, is told nothing, and allows the
tick — which is precisely the 007bl failure the gate was built to stop, reached by a route
018 did not close. 018 found the tick gate's TEST was broken (GNU `sed` on BSD); this is the
detector's SCOPE, and the two are independent.

Note before choosing a fix: these two directories are not overwritten unconditionally the way
CORE is. The manifest-hash rule preserves a locally edited doc or skill rather than
reverting it. So the loss here is not destroyed work, it is work that never propagates: it
stays in the one project that wrote it and the other five never see it. That is a weaker
failure than 007bl's and it argues for reporting rather than for widening CORE, which would
change overwrite semantics for two whole directories as a side effect.

## 023 — secret-scan-misses-signing-material

- [x] 023 — secret-scan-misses-signing-material — full track [hardened] — two repos commit an ASP.NET Data Protection key and `project-freshness.sh` reports "no verified secrets" on both. trufflehog matches verifiable credentials; a signing key is none. Needs a file-shape arm.

## 024 — sigpipe-backlog-in-production-scripts

- [x] 024 — sigpipe-backlog-in-production-scripts — spec-only — `validate-no-sigpipe-assertions.sh --all` reports 54 pipelines outside the self-tests. Mostly diagnostics where 141 costs nothing. One at a time: a bulk pass turned msroute's suite red (M2). Evidence: `specs/INDEX.pending.md`

**Evidence from msroute F008, reported 2026-09-25** (verbatim):

> F008 — harness — 2026-09-08 · from spec 010 — TemplateSyncDirectionTests.The_commit_named_is_the_one_holding_the_restored_content fails only under the full unit suite: template-autosync.sh:252 printf hits SIGPIPE and the SubprocessStderr guard expects silence. Passes in isolation. Same class as M2. Template-owned

Line 252 is msroute's copy at the time. In the template as of 2026-09-25 the matching pipelines are
`is_core()` at `scripts/template-autosync.sh:270-271` (`printf '%s\n' $CORE_SCRIPTS | grep -qx "$1"`):
`grep -q` exits on the first match, the still-writing `printf` takes SIGPIPE, and bash prints a
write error to stderr. `validate-no-sigpipe-assertions.sh --all` lists both lines as UNDECIDED.
This one is not a harmless diagnostic: a consumer that asserts an empty stderr fails, and only under
load, which is why it passes in isolation. A candidate for the first of the one-at-a-time fixes
(e.g. `case " $CORE_SCRIPTS " in *" $1 "*)` with no pipe at all).

## 027 — zero-attributions-reports-clean

- [x] 027 — zero-attributions-reports-clean — spec-only — `carve_audit.py` prints "clean" and exits 0 when `len(parent)` is 0, so a register that never attributed a carve reads like a flat one. §4b says that count *is* the finding. Diagnos: `specs/INDEX.pending.md`

## 029 — pretooluse-deny-is-inert-under-bypass-permissions

Ticked 2026-09-29. Row as it read at tick time, plus the diagnosis.

- [x] 029 — pretooluse-deny-is-inert-under-bypass-permissions — spec-only [hardened] — not the permission mode: rocky probed pre-046 guards with no hookEventName. Guard tests now read a verdict the way the CLI does (hook_verdict); probe-live-deny.sh asks the CLI itself.

**Measured on rocky, 2026-09-05, during checkpoint H13.** Two independent probes:

1. A register tick made while `--unlisted` was non-empty. Fed its exact payload on stdin,
   `core-owed-tick-guard-hook.sh` returns `permissionDecision: deny` with the full refusal text.
   The identical live `Edit` went through. Four rows were ticked that way.
2. A one-word edit to `scripts/spec_active.py`. Fed its payload, `core-machinery-guard-hook.sh`
   returns `deny` ("not this project's file to edit"). The identical live `Edit` went through, and
   was reverted immediately.

The hooks are correct, wired to the right matcher (`Edit|Write|MultiEdit`), and answer correctly
when asked. Their answer is not applied in the permission mode these sessions run in.

**The asymmetry is the useful part.** `bash-write-detect-hook.sh` — the PostToolUse, filesystem-diff
layer added at row H7b for shell-made writes — *does* fire, and blocked the same tick when it was
made through the shell. So enforcement is not gone; it is gone on the **Edit path**, which is
precisely the path four rule files and `CLAUDE.md` describe as the hard block ("hard-blocks source
edits", "cannot be silently skipped", "there is no bypass for mobile"). The shell path, which H7b
was written to close because writes there "met no gate", is now the only one with teeth.

Five guards rest on the inert path: `spec-register-guard`, `pipeline-state-guard`,
`spec-interview-guard`, `core-machinery-guard`, `core-owed-tick-guard`.

Scope: decide whether the guarantee is repaired (a channel that holds regardless of permission
mode) or the claim is corrected (the rules stop calling these deterministic and name the
PostToolUse layer as the real backstop). The current state is the worst one, because four rule
files promise a gate that is not there.

**What it turned out to be (2026-09-29).** Not the permission mode. A live A/B under
`bypassPermissions` (CLI 2.1.284): a deny without `hookEventName` let the Edit through, and the same
deny with it blocked. rocky measured on 2026-09-05; spec 046 found and fixed the missing field on
2026-09-12. The guarantee holds, and the rules that call these guards hard blocks are right.

What was still wrong is how rocky's probe got fooled. Every guard test read `.permissionDecision`
and ignored the discriminator, so guards stripped of the field passed the old tests 399/399. They
now decode through `scripts/hook-verdict.sh` and miss 81. `test-hook-channels.sh` §11–§15 checks
every emit site, pins how the tests read verdicts, and pins the probe's verdict logic against a fake
CLI. `scripts/probe-live-deny.sh` runs the A/B against the installed CLI. Rerun it after an upgrade.

## 031 — dotnet-test-prints-passed-over-an-aborted-run

Ticked 2026-09-29. Row as it read at tick time, plus the diagnosis.

- [x] 031 — dotnet-test-prints-passed-over-an-aborted-run — spec-only — a crashed test host reported `Passed!` with 45% of the suite unrun; no wrapper reads the abort line. Diagnos: `specs/INDEX.pending.md`

_Opened 2026-09-05 by rocky's 5-spec findings review (finding F006, from checkpoint H13). Template-owned per `.claude/rules/carve-budget.md` §4: this is a defect in how the harness READS a run, not in any product._

Measured on rocky 2026-09-05. The integration host crashed and the output block read, in this order:

```
The active test run was aborted. Reason: Test host process crashed
Passed!  - Failed: 0, Passed: 1673, Skipped: 7, Total: 1680
Test Run Aborted.
```

Exit code was 1. The suite is **3050 tests** — proven by a completing `--blame` re-run (3040 passed, 3 failed, 7 skipped) — so **45% of it never ran and the summary word was `Passed!`**.

**The reporting defect is independent of the crash.** The crash did not reproduce on a quieter machine and its cause is unidentified; that does not matter here. What matters is that a reader — human or script — is told in English that the run passed, over a run that covered barely half the suite.

This is the **third** way this command misreports, and the most persuasive. `project_495` already records `dotnet test` exiting **0** on failures; F006 adds a run that aborts, reports a truthful-looking per-assembly summary for the part that did run, and labels it `Passed!`.

**What any wrapper that judges a run must do:** treat `Test Run Aborted.` as fatal, and trust **neither** `$?` **nor** the summary word. `scripts/e2e-wait-audit.sh` already parses the summary line for this family of reason and is the natural place to start; **nothing currently reads the abort line**.

Scope: a shared run-verdict helper the CORE scripts call, plus the two existing call sites. Bite-proof it in both directions — a genuinely green run must stay green, and a captured aborted-run transcript must go red.

**Outcome.** Three template call sites judged a run, and all three believed the rocky transcript: `repeat-failure-guard-hook.sh` reset a live failure counter on `Passed! *-`, `project-maintenance.sh --suite` stamped an exit-0 abort green, and `template-sync-verify.sh` discharged the obligation as verified. `scripts/run-verdict.sh` (CORE, sourced) now owns the abort pattern, and all three read it before any success signal. Red arms were proven on HEAD in `test-run-verdict.sh`, `test-pipeline-hooks.sh`, `test-project-maintenance.sh` C37–C39 and the new `test-template-sync-verify.sh`. rocky's own `e2e-wait-audit.sh` is F030.

## 032 — spec-dir-absent-leaves-both-guards-inert

Ticked 2026-09-29. Row as it read at tick time, plus what was measured.

- [x] 032 — spec-dir-absent-leaves-both-guards-inert — spec-only — a row worked without a spec directory resolves to found:false in spec_active.py, so pipeline-state-guard and spec-interview-guard both pass everything; fundit's 016a shipped that way. Reported by fundit F001.

_Opened 2026-09-05 from fundit finding F001 (spec 016a, a static holding page shipped with no spec directory)._

**The row's mechanism is wrong.** `found: false` never let anything through. Both guards turn a missing directory into a deny: every phase missing, 0 of 15 answers. That holds at HEAD and in fundit's own copies at `d637ed2`, the version on disk when 016a was committed.

**Two other holes let 016a through.** The one guarded file, `site/fetch-fonts.mjs`, met a deny with no `hookEventName`, which the CLI drops; 046 closed that on 2026-09-12. Everything else was `.html`, `.css`, config, a Dockerfile or `scripts/**`, and no guard ever asked about those. The product itself, `site/index.html`, sat outside `SOURCE_EXTS` while `.cshtml`, `.razor`, `.vue` and `.astro` were inside it.

**Outcome.** `html|htm|css|scss|sass|less` joined `SOURCE_EXTS` in all three path guards. Config, Dockerfile and `scripts/**` stay exempt on purpose. `scripts/test-spec-dir-absent.sh` (CORE) pins the directory-less deny through `hook_verdict`, which no test did before. It also checks that the three lists are identical and that a spec with finished artifacts can still edit markup. 16 arms red on HEAD, 34/34 after. A SessionStart signal for a directory-less active row is F031, not built.

## 033 — portability-check-fails-open-and-says-nothing

Ticked 2026-09-29. Row as it read at tick time, plus what was measured.

- [x] 033 — portability-check-fails-open-and-says-nothing — spec-only — project-maintenance.sh guards the portability audit behind `[ -f ]`, so a clone without scripts/portability_audit.py skips it silently. A check that fails open must say so. Reported by fundit F002.

_Opened 2026-09-05 from fundit finding F002 (commit 57b6ea1 synced the call site without either portability script)._

**Measured.** A fixture with no portability scripts read `project-maintenance: clean`, exit 0. Section 6c had three silent paths: both scripts missing, one missing (the guard wanted both, so the wrapper's own exit 2 never ran), and a run that exited anything other than 0 or 1.

**Outcome.** A missing script is now a `[SETUP]` finding that names only the file that is missing, the same treatment section 1 gives `project-freshness.sh`. Any exit other than 0 or 1 is a `[PORTABILITY] ... could not run (exit N)` finding with the run's first lines. `test-project-maintenance.sh` C40–C45: C40–C43 red on HEAD, 110/110 after. The fixtures in `mkfix` and `test-skill-reachable.sh` now carry a passing pair. Sections 2c and 6b still skip without a word when their script is missing: F032, not fixed here.

## 038 — freshness-calls-a-scan-error-a-verified-secret

Ticked 2026-09-29. Row as it read at tick time, plus the diagnosis and what was measured.

- [x] 038 — freshness-calls-a-scan-error-a-verified-secret — spec-only — trufflehog exits non-zero on error as well as on findings, and the `if` reads both as `[FINDING] verified secret(s) — rotate NOW`. A repo with no commits reported a breach. Diagnos: `specs/INDEX.pending.md`

_Opened 2026-09-07 from hetznerradar's bootstrap (T0). Template-owned per §4._

`scripts/project-freshness.sh` runs `trufflehog … --fail` inside a bare `if`, so **every** non-zero
exit becomes the same conclusion:

```
[FINDING] trufflehog found verified secret(s) above. Rotate them NOW —
```

`--fail` promises a distinct exit code for *results found*. It says nothing about the codes
trufflehog uses for *unable to scan*, and the `if` cannot tell them apart. Observed on
hetznerradar before its first commit: trufflehog exited non-zero with `failed to read index file:
.git/index: no such file` — a repo with no history, nothing scanned — and the script reported a
verified secret. Confirmed false by re-running after the first commit: `verified_secrets: 0`.

This is `CLAUDE.md`'s Principle IX in the harness itself: an error and a finding are two states, and
collapsing them costs in both directions. A false breach burns a rotation that was never needed; the
same conflation would let a genuine scan failure ride out as "we looked, it's clean" if the codes
ever landed the other way round.

Fix: capture the exit code, branch on it. Findings → `[FINDING]`. A documented error code, or any
code the script does not recognise → a **third** status (`SECRETS_STATUS="scan failed — …"`) that is
neither clean nor a finding, carries trufflehog's own stderr, and does not set `FINDINGS=1`. Both
call sites (`trufflehog git` and `trufflehog filesystem`) have the defect.

**Measured.** trufflehog 3.95.5: `--fail` exits 183 on results; a repo with no commits exits 1 (`failed to read index file`). Without `--fail-on-scan-errors`, an error mid-scan exits 0.

**Outcome.** Both call sites now pass `--fail-on-scan-errors` and branch on the exit code: 0 clean, 183 `[FINDING]`, anything else `[WARN] trufflehog could not scan (exit N)` with trufflehog's own error message, `Secrets: scan failed`, and `NOT SCANNED: trufflehog` in RESULT. No finding, no rotate. A repo with no commits gets a hint. `test-project-freshness.sh` K29 (12 arms red on HEAD, 167/167 after) includes a real-trufflehog run on an empty repo. F033: the maintenance pass still reads NOT SCANNED as clean. F034: the PuTTY fixture in the self-test trips the template's own key scan (pre-existing).


## 039 — core-guard-blocks-its-own-first-install

Ticked 2026-09-29. Row as it read at tick time, plus the diagnosis and what was measured.

- [x] 039 — core-guard-blocks-its-own-first-install — spec-only — the guard denies on the path alone, so the sync that places a CORE script for the first time is refused by the guard that exists to protect it. Byte-identical copy, override burned. Diagnos: `specs/INDEX.pending.md`

_Opened 2026-09-07 from hetznerradar's bootstrap (T0). Template-owned per §4._

`scripts/core-machinery-guard-hook.sh` decides on the **path**: a write to a CORE file is denied
unless the override is set. During a first `/project-update` on a fresh project, every CORE script
is being placed for the first time — and the guard refused `scripts/tlc-cleanup.sh` on exactly that
basis. All seven tech-stack hook scripts in that pass were byte-identical to the template's copies.

The guard's purpose is to stop a project **diverging** from the template. A write whose bytes equal
the template's copy diverges from nothing; it is the sync doing its job. Denying it means a
first-time install cannot complete without `ALLOW_CORE_MACHINERY_EDIT=1`, and an override reached
for as routine bootstrap ceremony is an override that stops meaning anything — which is the real
cost here, since that variable is also the escape hatch for the deliberate local repair the guard's
own deny message describes.

Fix: before denying, compare the content being written against `$TEMPLATE/scripts/<name>`. Byte-
identical → allow, silently. Different, or the template copy unreadable → deny as today. That keeps
the guard's teeth on every write that actually changes a CORE file while making the install path
pass on its own merits rather than on a burned override.

Bound worth stating: the comparison needs the template clone resolvable. When it is not, the guard
must deny (fail closed) — it protects a file the template owns, and with no template to compare
against there is nothing to prove the write benign.

**Measured.** A Write of the template's `scripts/tlc-cleanup.sh` into a fixture project with its own `template-autosync.sh` was denied on HEAD; it now passes with no output, and the same bytes plus one `#` are still denied. The comparison costs 63 ms on the largest CORE file (229 KB).

**Outcome.** After `--is-core` says CORE, the guard computes the bytes the call would leave on disk (Write content, or Edit/MultiEdit applied to the current file with split/join) and allows silently when they equal `<template>/<rel>` in the local clone. No clone, no template file, no bytes in the payload, an Edit on a missing file, or any jq failure denies as before. The deny text says a byte-identical write would have passed. `test-core-machinery-guard.sh` SC-039-01..12: 6 red on HEAD, 36/36 after. F035: the Bash route (`cp` from the template) carries no bytes and is still denied.


## 040 — harness-writes-what-no-project-ignores

Ticked 2026-09-29. Row as it read at tick time, plus the diagnosis and what was measured.

- [x] 040 — harness-writes-what-no-project-ignores — spec-only — `.gitignore` is deliberately outside the synced set, so each project must independently know the harness writes 8 machine-local paths. hetznerradar knew none: 109 `.claude/state/` files tracked. Diagnos: `specs/INDEX.pending.md`

_Opened 2026-09-07 from hetznerradar's T0 (finding F005). Template-owned per §4._

`template-autosync.sh:2996` states the design decision plainly: **`.gitignore` is not in the synced
set.** That is defensible on its own — a project's ignore file is its own, and overwriting it would
trample build output, language conventions and local habits.

What was never built is the other half. The harness *writes files it knows are machine-local*, and
this template's own `.gitignore` names eight of them:

```
.claude/state/                   # attempt counters, TTL-pruned
.claude/.maintenance-state       # when each recurring job last ran ON THIS MACHINE
.claude/.template-sync-check     # autosync rate-limit marker
.claude/.bash-write-marker       # re-stamped on every Bash write
.claude/.bash-write-blocked
.claude/settings.local.json      # the per-machine lane config the two-lane rule requires
.claude/projects/
__pycache__/                     # the guards import spec_active.py, so python3 writes one
```

Every one of those entries exists here because this repo hit the problem and fixed it **for itself**.
The knowledge stayed. A project bootstrapped from the template starts with a `.gitignore` written for
its language and learns none of it.

Measured on hetznerradar 2026-09-07: **109 `.claude/state/attempts/` files committed**, one per hook
invocation, and a `.bash-write-marker` deletion sitting in `git status` at session start — a
timestamp file re-stamped every Bash write, in version control. Its `.gitignore` carries none of the
eight. The two-lane cost is worse than the noise: `settings.local.json` is where `SPEC_OWNER` and
`CLAUDE_TEMPLATE_AUTOSYNC` live, and a project that commits it has both lanes fighting over one
machine's identity.

The comment at 2996 is right that the file cannot be *replaced*. It does not follow that it cannot
be *appended to*. Fix: the sync owns a delimited block — `# --- claude-code harness (managed) ---`
… `# --- end ---` — that it inserts once and rewrites in place thereafter, leaving every line
outside the markers untouched. That is the same shape `sync-core-hooks.py` already uses for
`settings.json`: strip the managed set, reinstall the current one, leave the project's own alone.

The list must come from one place. Deriving it from the paths the harness actually writes beats a
second hand-maintained list — that is the drift `sync-prompt.md`'s own Step 5c comment records
("a list that is merely INCOMPLETE looks exactly like a list that is finished").

Second half, because the ignore alone does not help a project that already committed them: the pass
should **report** tracked files matching the managed set, with the `git rm --cached` line to run.
Ignoring a tracked file changes nothing, and a report that says "added 8 lines" over 109 still-tracked
files is the green-light-nobody-earned shape again.

**Measured.** Read-only sweep over `~/repos` with the new helper: 45 synced projects, every one missing the block, and 39 of them tracking machine-local files today. Most common: `.claude/skills/ui-ux-pro-max/scripts/__pycache__` (~35, from an old sync commit) and `.specify/feature.json` (16). ticket tracks 114 files, which collapse to 5 paths.

**Outcome.** `scripts/harness-gitignore.sh` (CORE) holds the one list, with a reason per path. `--apply` owns the lines between two marker lines in `.gitignore`: it appends the block once at the end and rewrites it in place afterwards, leaving bytes outside the markers untouched. It handles CRLF and refuses with exit 3 on broken markers. `template-autosync.sh` runs it after the copy loop (`--check` under `--check`/`--dry-run`/deferral) and records `.gitignore` so it is committed. At every exit it reports `[tracked]`: machine-local paths the index already holds, collapsed per directory, with the `git rm -r --cached` line to run. It never untracks. `test-runtime-markers-ignored.sh` D reads the helper instead of SKILL.md 3a. The template's `.gitignore` carries the block, with the same ignored set as before. `test-harness-gitignore.sh`: 87 arms, green under bash 3.2 and 5, and 12 of 12 hand mutations killed.


## 041 — mutation-timeouts-rule-was-never-written

Ticked 2026-09-29. Row as it read at tick time, plus the diagnosis and what was measured.

- [x] 041 — mutation-timeouts-rule-was-never-written — spec-only — ten files cite `.claude/rules/mutation-timeouts.md` and its "trap 4" as an authority — two rules, six scripts. It exists in no project and never has. Carries the gremlins family. Diagnos: `specs/INDEX.pending.md`

**Done.** `.claude/rules/mutation-timeouts.md` exists (CORE, path-scoped to mutation tooling) with five traps. Traps 1-3 and 5 are the gremlins/Stryker family (F003, F024/F071, F021/F063, F023). Trap 4, recovered from the ten citations, says an unmeasured state and a clean state must never render identically, and a detector is believed only after a known positive. `scripts/validate-rule-citations.sh` (CORE) reported exactly the ten dangling citations on HEAD and nothing else out of 534. Afterwards it resolves 536. Test: 31 arms, 9 of 10 hand mutants killed, the survivor equivalent. Pointers were added to `spec-hardening.md` and `testing.md`. The spec also fixed spec 040's pipe into `grep -q` at `template-autosync.sh:1548`, which `validate-no-sigpipe-assertions.sh --strict` had flagged.

_Opened 2026-09-07 from hetznerradar's T0 (finding F004, plus the gremlins family F003/F021/F023/F024)._

Ten files in this template cite `.claude/rules/mutation-timeouts.md` — and it does not exist. Not
here, not in any project, and `git log` finds no commit that ever removed it. It was cited into
existence and never written.

The citations are not decorative. Six of them invoke a numbered clause, **"trap 4"**, as settled
authority for a real and recurring argument — that *an unmeasured state and a clean state must not
render identically*:

| File | What it leans on trap 4 for |
|---|---|
| `.claude/rules/carve-budget.md:155` | an unparseable carve attribution must not read like no attribution |
| `.claude/rules/lane-handoff.md:53` | a question with no `**Blocks:**` line is reported, not skipped |
| `scripts/maintenance-due.sh:139` | "never run" must not render as "run and clean" |
| `scripts/lane_status.py:54` | silence that looks like good news |
| `scripts/bash_write_targets.py:45` | a conclusion drawn from a check that did not run |
| `scripts/test-bash-write-guard.sh:674` | silence below means nothing |
| `scripts/test-scenario-map-rows.sh:24` | a widened guard must be shown to still bite |

That is a principle the codebase reasons *with*, load-bearing in two rules and five scripts, whose
statement nobody can read. A reader who follows the pointer finds nothing and either invents what
trap 4 says or ignores the citation; both are worse than the rule being absent and uncited.

The second half of the row is the content the rule should hold, which hetznerradar has now measured
four times over and which currently lives only in that project's `CLAUDE.md`:

- **F003** — gremlins at its default `--timeout-coefficient` reported 127 mutants TIMED OUT and
  printed **`Test efficacy: 100.00%`**. At `--timeout-coefficient=20` the same run is 89.09% with 18
  survivors. This is trap 4 exactly: unknown rendered as killed, and the direction of the error is
  toward a green light.
- **F024** — worse, and the reason the coefficient alone is not the fix: because a timed-out mutant
  counts as neither lived nor killed, **a run with MORE timeouts prints a HIGHER efficacy.**
  Measured on one package, same code, two runs: `Lived 6 / Timed out 98 → 100.00%` and
  `Lived 0 / Timed out 51 → 99.42%`. The headline number is not comparable across runs. Read the
  LIVED list; never the percentage.
- **F021** — the run that matters most is the one nobody will wait for: 11 hours at face value,
  1m46s under `GOFLAGS=-short`, because one stress test is 234 of the package's 242 seconds and
  gremlins cannot pass test flags through. The caveat travels with the number — under `-short` that
  test does not run, so mutants only it would kill survive.
- **F023** — gremlins reports a `case` arm in a tagless switch as NOT COVERED even when tests
  demonstrably kill the mutant, because Go emits no coverage block for the case *expression*, only
  its body. Proven twice. A reader who trusts it writes a test that already exists.

All four are the same shape and it is the shape trap 4 names. Writing the rule closes F004 and gives
F003/F021/F023/F024 the home they were consolidated toward, instead of one project's `CLAUDE.md`
holding knowledge that every project with a mutation gate needs.

Scope: write the rule, numbering the traps so the six existing citations resolve to what they meant.
Recover the intended numbering from the citation sites rather than inventing it — each one says what
it thought trap 4 was, and they agree.

## 042 — needs-clause-swallows-a-null-dependency

Ticked 2026-09-29. Row as it read at tick time, plus the diagnosis and what was measured.

- [x] 042 — needs-clause-swallows-a-null-dependency — spec-only — `lane_status.py:196` treats a row's `needs` as ids, so a register written in another language (`needs inget`, `needs nothing`) reports a dependency that is never ticked. Six of nine runnable rows were invisible in agentcrm's "what can I start" list, two of them carved security rows. Diagnos: `specs/INDEX.pending.md`

**Done.** A `needs` entry with no digit (`inget`, `nothing`, `none`) is prose and no longer blocks; an id-shaped entry that names no row still blocks and is named on a `needs names no row, held until fixed` line. That departs from the diagnosis below, which proposed freeing every unresolved entry: agentcrm's register and `next-rows.sh` document that an unknown id must block so a typo never frees a row, and the digit test keeps that without a word list. On agentcrm at `3a7221ad` the runnable list goes from 3 to 9, and the six restored rows are exactly S17, 027, 028, 029, 031 and 032. The fix pushed that list past the full report's cap of 8 (the brief caps at 6), and neither cap said so; both now name the overflow. `test-lane-orientation.sh` cases 7 and 8, 31 arms, 18/18 non-equivalent hand mutants killed. Found along the way: F036, `validate-rule-citations.sh` red on HEAD since 041.

`runnable()` in `scripts/lane_status.py:196` keeps a row only when every entry in its `needs`
list is a ticked id:

```python
and all(d in ticked for d in r["needs"])
```

The parser puts whatever follows `needs` into that list. A register that writes "this row
depends on nothing" in words — agentcrm uses the Swedish `needs inget`, an English register
would write `needs nothing` or `needs none` — yields `needs: ['inget']`, and no row is ever
ticked under that id. The row is therefore reported as blocked forever, by a dependency that
says it has none.

Measured on agentcrm 2026-09-08, immediately after S16 was ticked: nine rows were unticked,
unowned and had every real dependency satisfied. The tool listed **three**. The six it hid
were S17, 027, 028, 029 and — the reason this is worth a row rather than a note — **031 and
032**, the two rows H3 carved from its own security sweep.

The failure is silent in the direction that matters. It never invents work; it withholds it,
and a short list of real rows looks exactly like a correct short list. The developer asked
"are we blocked on outside answers?" and the tool's own output was the reason to think so.

Not a display cap: `render()` slices `free[:8]`, so eight would have fitted.

**The fix is not a word list.** Adding `inget|nothing|none` to a skip set fixes Swedish and
English and breaks on the next register. The sound reading is that an entry in `needs` which
matches no row id in the register is not a dependency — it is prose. Treat it as such, and
report it once as unparseable rather than as blocking, so a genuine typo in a real id
(`needs 04` for `needs 004`) still surfaces instead of silently becoming "no dependency".
That distinction is the whole content of this row: an unresolvable reference and no reference
must not render identically (`.claude/rules/mutation-timeouts.md`, trap 4).

`validate-register-ids.sh` does not catch it — it validates row ids, not the ids rows cite.

## H1 — integration-hardening

- [x] H1 — integration-hardening — checkpoint — full-system regression + security sweep after the five rows closed 2026-09-03; the template ships to six projects, so its seams are theirs.

## 047 — stryker-spans-fail-silently-and-score-well

Ticked 2026-09-30.

- [x] 047 — stryker-spans-fail-silently-and-score-well — spec-only — an invalid mutate glob matches no file and reports a clean score; spans are CHARACTER offsets, not lines; a concurrent `dotnet build` zeroes the run silently. From ighweld-2026. Diagnosis: `specs/INDEX.pending.md`

**Done.** `scripts/stryker_guard.py` owns the rules. Every maintenance pass checks each committed `stryker-config*.json` `mutate` pattern, plus the literal `-m` values in the project runner. A malformed span (F184), a glob that matches no `.cs` file, and a valid CHARACTER span (F197/F185) are each a finding. `--full` will not start beside a live Stryker run or dotnet build (F069). `scripts/stryker-guard-hook.sh` (PreToolUse, Bash) denies the same shapes when Claude issues the command, with `STRYKER_SPANS_ARE_CHARACTERS=1` / `STRYKER_GUARD=off` as the overrides. It fails open on anything it cannot read. Hardened: threat model in the spec. The security-scanner adversarial review found 10 issues, 9 fixed with arms. /security-review found nothing. Hand mutants: 43/43 killed. The run also fixed `hook-verdict.sh` (its bash 3.2 pattern substitution hung on a 40 KB reason). Findings F051–F053.


Three findings, one theme: Stryker.NET's per-file targeting fails in ways that read as success.

- **F184 — an invalid line span matches nothing and scores well.** `'**/X.cs{845-1080}'` uses a hyphen
  where Stryker wants `..`. It is not an error; the glob simply matches no file, so the run mutates
  nothing in that file and reports a clean result. A gate that measures nothing and passes is worse
  than no gate.
- **F197 — spans are CHARACTER offsets, not line numbers.** `SyncService.cs{98..120}` selects
  characters 98–120 of the file. ighweld spec 161's first run was scoped to a couple of dozen
  characters and nobody could tell from the output.
- **F185 — spans are unusable as a per-spec gate anyway.** With `'**/WpqrService.cs{840..1140}'` the
  file still generates its whole mutant set; the span does not reduce the run.
- **F069 — a concurrent `dotnet build` or `dotnet test` silently destroys the measurement.** The
  sibling build overwrites the mutated assembly, and the run scores ~0% with no warning. ighweld
  carries this as a project memory (`stryker_runs_alone`) because it cost a full run. It belongs in
  the mutation docs and, better, in a guard.

Distinct from 043 (which is about the reporter list) and 041 (the timeouts rule). The common fix
shape: refuse a mutate glob that matches no file, and say so.

## 079 — traceability-loses-the-second-id-in-a-chain

- [x] 079 — traceability-loses-the-second-id-in-a-chain — spec-only — `grep -o` is non-overlapping, so `SCNNN_SCNNN_Name` in a C# method read as one id and the second row was reported uncovered. 8 of agentcrm's 58 "uncovered" rows were this, each with a passing test. Pattern takes `(...)+`, `tr` splits; case46 asserts both forms. Found as agentcrm H6 / F391.

## 048 — sc-id-space-is-three-digits-and-full

Ticked 2026-09-30.

- [x] 048 — sc-id-space-is-three-digits-and-full — spec-only — `scenarios.md` mandates `SC-NNN`; ighweld has used 961 of 999 and already mints `SC-1000+`. Row 007 split the two SC- namespaces by digit WIDTH. Diagnosis: `specs/INDEX.pending.md`

**Done.** `scenarios.md`: an SC id is zero-padded to at least three digits and grows past `SC-999`; low gaps are not reused and old ids are not re-padded. The locate grep reads `SC-[0-9]{3,}`. The namespace paragraph names both out-of-range rules (narrowest width, floor). `validate-fixture-map-ids.sh` counts ids of any width ≥ 3 (five places had a 4-digit cap). `test-validate-scenario-traceability.sh` case48a/b pin the width rule on a mixed-width map, the first test it ever had; sabotage (p) widest-width and (q) width-removed each turn a case red. `test-fixture-map-ids.sh` C16/C16b: a five-digit owned id is seen by R1 and R3.

`.claude/rules/scenarios.md` specifies `SC-NNN`, "three digits, padded". ighweld-2026 has used 961 of
the 999 (F065; F057 measured 950 a week earlier), and the free ids are all in low gaps, which are the
worst ones to reuse because an old test may still name them.

It has already overflowed in practice: spec 112 minted `SC-1000..1006` for the public API block
(F078), so the project is running four-digit ids against a rule that says three.

**The interaction that makes this more than a widening.** Row 007 split the two `SC-` namespaces — the
scenario map's permanent handles and spec-kit's per-spec Success Criteria — **by digit width**,
deliberately, because a magnitude floor is useless on a map that starts at SC-001. Four-digit map ids
walk straight into that discriminator. Decide the two together or the traceability gate starts
mis-bucketing.

## 049 — a-held-row-cannot-be-written-to

Ticked 2026-09-30.

- [x] 049 — a-held-row-cannot-be-written-to — spec-only — `spec-run-log-hook.sh` resolves through `spec_active.py`, which skips `- [!]` rows, so holding a row stops you logging why you held it. Diagnosis: `specs/INDEX.pending.md`

**Done.** `--spec` takes a register id as well as a directory (`--spec 049`, `--spec H1`). The lookup goes through the new `spec_active.py --id`, which shares `resolve()`'s `<id>-*` glob and ignores the row's status, so held and ticked rows are writable. An existing directory still wins, and a value with a slash stays a path. The implicit path still picks the row to work. When it cannot record, stderr names `--spec <id>` and lists the held rows. `spec-register.md` says this in one sentence. `test-pipeline-hooks.sh` has 15 new arms, 10 of them red on HEAD. Two sabotage runs (slash guard removed, status filter added) each turned arms red.

`spec_active.py` resolves the active spec and skips `- [!]` held rows — correct, and
`.claude/rules/spec-register.md` says so explicitly: a held row must never be offered as the active
row, or a banner quietly overrules the decision to hold it.

`scripts/spec-run-log-hook.sh` resolves through that same function. So the moment a row is held, the
run log for it can no longer be appended to (F139, F195).

Holding a row is precisely the moment the note matters — somebody stopped for a reason the register
cannot express as a dependency, and the next session needs to know what it was. The two needs are not
in conflict; they are two different questions asked of one resolver. "Which row should I work?" must
skip held rows. "Which row is this note about?" must not.

## 050 — allium-cli-warns-on-every-spec-it-has

Ticked 2026-09-30.

- [ ] 050 — allium-cli-warns-on-every-spec-it-has — spec-only — the deferred location-hint lint wants a syntax its own parser rejects, so `allium check` warns on every spec and the warning means nothing. Diagnosis: `specs/INDEX.pending.md`

`allium check` emits "deferred specification should include a location hint" for every `deferred` in
every spec in the project (F080). ighweld probed the syntax the lint seems to want — `in "p"`, `"p"`,
`{ lo… }` — and its own parser rejects each one (F001, F031), so there is no spelling that satisfies
it.

A warning that fires on every spec and cannot be satisfied is noise that trains people to skip the
whole report — which then hides the warnings that mean something. Either implement the syntax, or drop
the lint.

F089 is a second allium-cli defect found the same way: a rule that assigns a status through a
trigger-param binding (`when: SyncPush(item)` + `ensures: item.status = …`) is not accepted.

## 051 — maintenance-suite-blind-to-standalone-node-tests

Ticked 2026-09-30.

- [ ] 051 — maintenance-suite-blind-to-standalone-node-tests — spec-only — `project-maintenance.sh --suite` detects only `npm test`/.NET, so a repo of bare `node tests/*.mjs` never stamps `suite`; mutation is unwired too. Diagnosis: `specs/INDEX.pending.md`

emaljen runs its whole suite as standalone Playwright scripts (`node tests/*.mjs`, about 20 files,
plus `tests/vrt/`), with no `package.json`. `project-maintenance.sh --suite` looks only for
`npm test` or a .NET test project, so it prints "nothing to run" and never stamps `suite`. The
due flag therefore can't clear through `--full`, and emaljen stamps it by hand after a real green
run (emaljen F027). Mutation has the same gap: no `run-mutation-gate.sh` stack for PHP/WordPress.

Fix direction: read `.claude/.template-sync-verify` (or a sibling `.claude/.suite-command`) as the
suite command when no stack is detected, rather than adding one more hard-coded stack.

Second case (iskvalp, 2026-09-25) — worse, because it stamps instead of refusing: the jest suite
lives in `client/package.json` and the repo root has only `iskvalp.sln`, so `--suite` runs
`dotnet test` alone (1194 tests) and on green stamps `suite` — "unit + integration + E2E + visual
regression" — without the 4138 jest tests, Maestro E2E or VRT. The package.json probe only looks at
the root. The same override file fixes both; a detected stack should not outrank a declared one.

## 052 — maintenance-runs-what-it-finds

Ticked 2026-09-30.

From ighweld-2026's findings batch review, 2026-09-18.

**Half 1, the ratchets (ighweld F062).** Nothing invokes any `scripts/check-*.sh` ratchet: not
`check-e2e-guards.sh`, `check-silent-catches.sh` or `check-css-classes.sh`. `project-maintenance.sh`
runs none of them. A ratchet that only runs when someone remembers it will eventually stop running.
One `check-all.sh`, wired into the maintenance pass, covers every ratchet a project adds.

**Half 2, the build target.** `--suite` runs `dotnet test` and `--full` runs `dotnet stryker` from the
repo root. ighweld-2026 had a leftover `IGHWeld.Web.sln` at the root that pointed at deleted Blazor
projects. On 2026-09-18 both steps failed with MSB3202 "project file not found", and the pass
reported `[SUITE] failed` and `[MUTATION] failed to complete`. The real solution
(`src/welding/Welding.sln`) was 7478/0 green in the same session. Stryker also has no whole-project
config there, only `stryker-config.NNN.json` files, one per spec. Proposed fix: let the project
declare its solution and test project (as `specs/traceability-roots` does for test roots) and fail
loudly when no declaration exists and more than one candidate is present, rather than taking
whatever the root holds.

## 053 — stryker-tmp-outlives-its-run

Ticked 2026-09-30.

Reported by msroute F007, 2026-09-25 (verbatim):

> F007 — harness — 2026-09-08 · from spec 010 — Abandoned .stryker-tmp sandboxes are now excluded by four separate consumers (project-freshness, project-maintenance, vitest, eslint); the fix is to stop the directory existing — sweep on entry of the next run, or move tempDirName out of the tree. Template-owned

Related product-side row: msroute `007cm — stryker-tmp-untracked-and-trips-the-guard`, whose guard
half was closed 2026-09-03 by syncing 16 CORE scripts. Each new consumer of the tree has had to learn
the exclusion separately; a fifth will too. Fix at the source: sweep stale `.stryker-tmp` when a
mutation run starts, or point Stryker's `tempDirName` outside the working tree.

## 065 — nightly-cron-line-runs-blind

From fundit F084 and F086 (2026-09-08/09). The crontab line `install-nightly-maintenance.sh`
writes runs under cron's PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), where none of dotnet, node, npm,
npx, docker or timeout exist; fundit's mutation pass failed every night from 2026-09-04 with
`dotnet: command not found`. Separately, a line whose command fails to parse writes nothing, since
the redirect is part of the unparsed command, so "never fired", "failed to parse" and "ran and wrote
nothing" look identical. It took four probes to separate them. Fix: write an explicit PATH captured
at install time, and wrap the command so the redirect survives a parse failure. The script is
opt-in now (`github-actions.md`), which lowers the priority, not the defect.

Fixed 2026-09-30: the PATH is captured to `~/.claude/nightly/<project>.path` (inline it broke BSD cron's
999-character command limit), the line opens its log first with start/end lines, paths are quoted,
`%`/newline and over-long lines are refused, `sh -n` runs before crontab is touched, `--list` flags
stale lines. `scripts/test-install-nightly-maintenance.sh`.

## 066 — allocator-cannot-make-a-carved-suffix

From fundit F095 (2026-09-09). Carved rows are ids like `002a`, `005b`, `015a`: the parent's number
plus a letter. `next-register-id.sh --alpha` is for letter-led series (`S21`, `H3`), so
`--alpha 005` returns `0051`. The rule says never pick an id by eye, and for the one shape carving
produces, eye is the only allocator there is. Fundit's H3 picked `015a`/`015b` that way on
2026-09-27. Fix: a `--suffix NNN` form that returns the next free letter across the register and
every `INDEX*.md` archive.

Fixed 2026-09-30: `next-register-id.sh --suffix <parent>` returns the parent plus the letter after the
highest one used, over the register and every `INDEX*.md` archive, case-folded, single-letter children
only; unknown parent, mixed modes and past-`z` exit 2. `scripts/test-next-register-id.sh`.

## 067 — traceability-walk-races-test-results

From fundit F116 (2026-09-10). Three consecutive runs on identical input gave 141, 0 and 0 of 148
covered while a Playwright suite was writing and deleting `test-results/`. The reference walk is a
`find` over the tree, and a directory vanishing mid-walk ends it early, with the error swallowed.
Related to 044 (zero vs broken are indistinguishable), but a separate cause: this walk should
prune `test-results/` and other build output, and treat a walk error as unreadable, not as zero.

Fixed 2026-09-30: `test-results/` was already pruned (6bf2e52); the live gap was the partial case. A
walk whose `find` or `grep` reported any error now refuses (exit 4, error lines + files read per root)
instead of printing a partial `coverage:`. `blob-report/`, `allure-results/`, `.nyc_output/` pruned.
`scripts/test-validate-scenario-traceability.sh` case49/case50 + two sabotage arms.

## 068 — checkpoint-cadence-counts-checkpoints

From fundit F211 (2026-09-24). `spec-register-orientation-hook.sh` counts every ticked row toward
the every-5 checkpoint cadence, checkpoint rows (H1, H2) and carved rows (016a) included, and fired
"checkpoint due" at 20 done when only four feature specs had been ticked since H2. The register's
own precedent counts feature specs since the last checkpoint. Fix: count ticked rows that are not
H rows and carry no `carved by`, since the last ticked H row.

## 069 — tlc-cleanup-kills-the-run-it-guards

- [x] 069 — tlc-cleanup-kills-the-run-it-guards — spec-only — tlc-cleanup.sh `pkill -f tla2tools|tlc2.TLC` from PreToolUse/Stop hooks kills the TLC run and its own hook shell (exit 144). Sibling of 056. From ekofak 005. Diagnosis: `specs/INDEX.pending.md`

From ekofak spec 005 (2026-09-28). `scripts/tlc-cleanup.sh` does `pkill -f "tla2tools"` and
`pkill -f "tlc2.TLC"`, and `.claude/settings.json` runs it from a PreToolUse Bash hook whenever the
command mentions `tlc|tla2tools|tlc2.TLC`, and from Stop/SubagentStop. Three failures, all observed:
the PreToolUse run matches the hook's own `bash -c` (its grep pattern contains the string) and the
Bash tool's shell, so every `/tla` command as the skill writes it dies with exit 144 before TLC
starts; a TLC run in the background is killed the moment any subagent stops; and `pkill -f` in the
same command kills the shell running it (the 056 trap). `/tla` is unrunnable as documented.
Workaround used: a renamed jar (`java -jar modelcheck.jar`) through a wrapper script. Fix: track
the TLC PID the skill starts (a pidfile) and kill only that, or use the bracketed-literal pattern
056 adopted (`pkill -f "[t]la2tools"`) and drop the PreToolUse trigger, which runs before TLC exists.
Second sighting: hireflow spec 017 (2026-09-30) — SubagentStop/Stop and the PostToolUse Bash hook killed 4 TLC runs of a `/tla` subagent mid-run (exits 137/143/144) whenever any other agent stopped; the same renamed-jar workaround was needed.
Fixed 2026-09-30: the cleanup matches only `java` processes (argv[0]) and by default kills only runs older than the 320 s bound; `--all` for manual use. The hook is PostToolUse(Bash), not PreToolUse; the wiring is unchanged.

## 070 — freshness-audits-npm-only

- [x] 070 — freshness-audits-npm-only — spec-only — project-freshness.sh runs `npm audit` and nothing else, so a Maven/Gradle backend's dependency CVEs are never checked. From ekofak H1. Diagnosis: `specs/INDEX.pending.md`

From ekofak checkpoint H1 (2026-09-28). `scripts/project-freshness.sh` has two checks, trufflehog and
`npm audit`, and discovers only `package.json` manifests. ekofak's backend is Java 21 / Spring Boot 3 on
Maven (`backend/pom.xml`: Spring, PDFBox, Flyway, jqwik), and its H1 security sweep reported
"Deps: advisories — frontend/" as if that were the whole dependency surface; the backend was never looked at.
The same holds for any Gradle, NuGet, Cargo, Go or pip project the template runs in. Fix: discover the
other manifests and run the ecosystem's own audit where one exists locally (`mvn
org.owasp:dependency-check-maven:check` needs an NVD API key and is slow, so consider OSV-Scanner, which
reads pom.xml / lockfiles offline-first), and print an explicit `[SKIP] <manifest> — no auditor` line for
any ecosystem it cannot check, so an unchecked backend never reads as clean.
Fixed 2026-09-30: the template already had osv-scanner and dotnet passes (ekofak's copy predated them). Added pass 6, dependency coverage: every Maven/Gradle/Cargo/Go/Python/Ruby/PHP/Elixir/Dart manifest is `[OK] … osv-scanner (<file>)` or `[SKIP] … no auditor: <why>`, and an unchecked one is NOT SCANNED in RESULT. `Deps:` renamed `npm:`.

## 071 — testing-doc-prescribes-js-screenshot-api

- [x] 071 — testing-doc-prescribes-js-screenshot-api — spec-only — testing.md tells .NET projects to use Expect(Page).ToHaveScreenshotAsync, which exists only in Playwright's JS runner. From teach F007. Diagnosis: `specs/INDEX.pending.md`

From teach F007 (spec 003, confirmed at teach H1–H3). `.claude/docs/testing.md` prescribes
`Expect(Page).ToHaveScreenshotAsync` for visual regression on .NET. That assertion belongs to
Playwright's JS/TS test runner (`@playwright/test`); `Microsoft.Playwright` has no screenshot
comparison at all. teach built its own `VisualBaseline` (in-browser canvas diff against a committed
PNG) to satisfy the rule. Fix: say what .NET projects actually have — `Page.ScreenshotAsync` plus a
pixel diff (a canvas diff in the page, or ImageSharp/Codeuctivity.ImageSharpCompare) with committed
baselines — and keep the JS API only for Node projects.
Fixed 2026-09-30: the Node block is TS `toHaveScreenshot`; the .NET block is `ScreenshotAsync` + Codeuctivity.SkiaSharpCompare, per-OS baselines in the source tree, missing baseline fails, `VRT_UPDATE=1` writes. Verified by running the snippet. Guard: `scripts/test-doc-dotnet-playwright-apis.sh` (template-only).

## 072 — security-rule-says-secrets-in-env-and-1password

- [x] 072 — security-rule-says-secrets-in-env-and-1password — spec-only — rules/security.md says production secrets go in environment variables; Swarm secret files are the safer shape (docker inspect shows env). From teach F061. Diagnosis: `specs/INDEX.pending.md`

From teach F061 (spec 014 deploy-hardening, 2026-09-28). `.claude/rules/security.md` ends with "Never
store secrets in code — use appsettings.json (local) or environment variables (production)". teach
spec 014 moved every production secret to Swarm secrets mounted as files (`/run/secrets`, 0400),
because environment variables are readable through `docker service inspect` / `docker inspect` by
anyone with Docker API access, and refused a secret-class key with a live value from any non-file
source. The rule as written steers the next project into the weaker shape. Fix: production secrets
come from an orchestrator secret store mounted as files (Swarm/Kubernetes secrets) or a vault;
environment variables only where the platform offers nothing else, and never baked into an image.
Fixed 2026-09-30: docs/security.md § Secrets. 1Password holds every real value (`op run --env-file=.env.op` locally). Production pipes `op read … | docker secret create <name> -` and mounts it under `/run/secrets`, and the app reads it with `AddKeyPerFile`. Env vars are a fallback only, never `ENV`/`ARG`. Rule, deploy-checklist, deployment.md and wizard Q39 agree and point there. Guard: `scripts/test-doc-secrets-guidance.sh` (template-only).

## 078 — autosync-tests-miss-ten-of-twelve-mutants

- [x] 078 — autosync-tests-miss-ten-of-twelve-mutants — spec-only — H1 sampled 12 operator mutants in template-autosync.sh; the 16 suites that run it killed 2. Add a surgical arm per survivor (list in specs/H1-integration-hardening/checkpoint.md). — carved by H1 — approved F050

## H2 — integration-hardening

- [x] H2 — integration-hardening — checkpoint — full-system regression + security sweep + mutation spot-check over the ~30 rows ticked since H1 (043–079).

## 075 — place-heavy-jobs-local-or-cloud

- [x] 075 — place-heavy-jobs-local-or-cloud — light track [hardened] — needs 074 + five ordinary specs ticked under its ledger. Per job (Stryker, suite, freshness, similarity, findings/carve review): local or Claude cloud, decided from the numbers. Developer request 2026-09-29.

## 080 — developer-authored-acceptance-cases

- [x] 080 — developer-authored-acceptance-cases — full track [hardened] — the developer confirms 3-5 Given/When/Then cases before code on full/hardened specs; guard blocks until then; each AC-n gets a test written first — approved F075

## 081 — always-loaded-context-budget

- [x] 081 — always-loaded-context-budget — spec-only — CLAUDE.md + unscoped rules are ~69 KB every session; context-budget.sh caps it at 40 KB with a ratchet test; rationale moves to on-demand docs — approved F076

## 020 — quality-gate-hooks-unwired-for-latency-we-no-longer-pay

- [x] 020 — quality-gate-hooks-unwired-for-latency-we-no-longer-pay — full track — 15 local-LLM hooks (test-realism, test-assertion, test-gap, secret-scan…) are unwired because they cost in-session latency. The nightly pass makes that free. Re-measure them at 02:30.

## 082 — harness-supply-chain-and-unattended-exec

- [x] 082 — harness-supply-chain-and-unattended-exec — full track [hardened] — autosync pulls main unpinned, the nightly runs repo-controlled strings, lane-catchup strips ~/.ssh denies, prune can destroy agent work. F037 F043 F045 F062–F067.

## 083 — guard-bypass-and-fail-open

- [x] 083 — guard-bypass-and-fail-open — full track [hardened] — PreToolUse guards fail open without jq, miss unnormalised paths, exempt any */scripts/*, miss a split tick; the deny list is bypassable. F029 F035 F038–F042 F044.

## 084 — autosync-sandbox-and-harness-env

- [x] 084 — autosync-sandbox-and-harness-env — full track — the root walk loops on a relative dir, sandboxed runs still push, self-tests inherit CLAUDE_PROJECT_DIR and CDPATH. F013 F015–F020.

## H3 — integration-hardening

- [x] H3 — integration-hardening — checkpoint — full regression + security sweep + mutation spot-check over 080–084.

## 088 — guard-trust-anchors

- [x] 088 — guard-trust-anchors — full track [hardened] — the gates trust state Claude can write: a planted .git ends the root walk, self-granted nightly trust, forged acceptance grandfathering and self-confirm. F090 F091 F093 F094 — approved F098
