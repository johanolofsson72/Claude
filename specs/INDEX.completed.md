# Completed-spec retrospectives (archive)

Rows verbatim as they read at tick time. Never pipeline input.

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
