# Pending-row diagnosis (archive)

The long form of rows not yet started. Never pipeline input.


## 029 — pretooluse-deny-is-inert-under-bypass-permissions

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

## 030 — unlisted-fires-forever-on-an-optional-callee

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

## 007

_2026-09-03: folded into row 007 — one script, three defects. Row as it stood:_

- [ ] 007 — traceability-gate-conflates-two-failures — spec-only — `validate-scenario-traceability.sh` reports collisions and the coverage backlog through one `exit 1`, so a real collision is invisible behind a permanently-red backlog. Found by @david as agentcrm S3.

## 013

_2026-09-03: folded into row 007 — one script, three defects. Row as it stood:_

- [ ] 013 — traceability-self-test-straddles-its-timeout — spec-only — `validate-scenario-traceability.sh`'s own self-test runs 77s against its timeout, so it passes or fails by machine speed. Found as consultpilot H7bq.

## 016

_2026-09-03: folded into row 007 — one script, three defects. Row as it stood:_

- [ ] 016 — traceability-gate-floor-and-letter-ids — spec-only — the out-of-range floor is the map's lowest id, useless on a map starting at SC-001 (11 ids misfiled), and the gate cannot see letter ids, so nine `SC-A11` audits trace to nothing. Found as msroute 007cp + 007cw.

## 021

- [ ] 021 — core-set-excludes-docs-and-skills — spec-only — found on msroute during `/project-update`, 2026-09-03.

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

## 022

- [ ] 022 — sync-version-marker-abandoned — spec-only — found on msroute during `/project-update`, 2026-09-03.

Two markers record "which template revision is this project at", and only one is maintained:

- `.claude/.sync-version` — written ONLY by `scripts/sync-prompt.md` (Step 0) and
  `.claude/skills/project-wizard/SKILL.md`. Both are prose executed by a model.
- `.claude/.template-sync` — written by `scripts/template-autosync.sh`, the automated path
  that actually runs at every session start.

On msroute the first sat at `4407255` (2026-08-22) while the second read `sha=ac2dad5c9d9b`
synced the same morning, and three intervening `chore(sync)` commits had moved the project
without touching it. Step 0's whole purpose is to skip Steps 1-8 when the project is current;
reading the abandoned marker inverts it, so a current project takes the full-sync path every
time and the token saving the step exists for is never collected.

Independent content verification at the time: 221 of 223 manifest files byte-identical to the
template, the 2 exceptions being row 021's finding. The project was current; only the marker
disagreed.

Fix is a choice, not a patch: either have `template-autosync.sh` write both, or have Step 0
read `.claude/.template-sync` and retire `.sync-version`. Prefer the second — one writer, one
reader, and the prose stops owning a fact the automation already knows. Check
`project-wizard` in the same pass; it writes the marker on a path where no autosync has run
yet, so retiring the file means giving the wizard the other one.

## 008 — scenarios-map-canary-unheeded

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

## 006 — nothing-checks-the-design-gate-exists

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

## 026 — port-drive-sync-and-its-gate-upstream

The 2026-08-30 incident — a harness syncing the real repository against a three-file sandbox template,
54 `chore(sync)` commits pushed to origin/main, 505 lines deleted — was diagnosed and fixed by
consultpilot as row H7bo. It built two things this repository does not have:

- a `drive_sync` helper every harness routes its `template-autosync.sh` calls through, and
- `validate-sync-sandbox-declarations.sh`, the gate that refuses any other call shape.

The one dangerous call site here is already fixed (`test-template-autosync-stranded.sh:63`, commit
9b0b5ad). What is missing is the mechanism that stops the next one being written, and the reason it
matters is that this template is where every project's copy comes from.

**Why it cannot be fixed downstream.** consultpilot's gate reports 17 direct invocations across six
harnesses — `test-template-autosync-stranded`, `-owed`, `-eol`, `-unlisted`, `test-sync-count-honesty`,
`test-core-owed-tick-guard`. Every one is CORE. A fix written into any of them is eaten by the next
`chore(sync)`, which is the H7t lesson; the gate is therefore permanently red in that project for a
defect it is not allowed to repair. Third time today a check has been found judging files the project
does not own — the other two were `test-sync-prompt-core-parity.sh` and the stale `sync-prompt.md`
copies.

**Scope:** port `drive_sync` and the gate; convert the call sites in the CORE harnesses; ship both as
CORE so the gate arrives with the shape it enforces. Audit first — two of the four call sites here
already pass `CLAUDE_PROJECT_DIR` and need only rerouting, not a behaviour change.

## 027 — zero-attributions-reports-clean

Found on agentcrm 2026-09-04, immediately after a convergence stop that the same tool
could not see.

`scripts/carve_audit.py:63-66`:

```python
if not over and not deep:
    extra = f" ({len(unresolved)} unresolved attribution(s) above.)" if unresolved else ""
    print(f"carve shape: clean — {len(parent)} attributed row(s), none over {budget} carves, none past depth 2.")
sys.exit(1 if bad else 0)
```

`parent` is built from `carved by` / `found by` / `opened by` / `from`. On a register that
uses none of them `parent` is empty, so `over` and `deep` are necessarily empty too, and the
verdict is the word **clean** with exit 0.

`.claude/rules/carve-budget.md` §4b already states the intended reading:

> A register with no attributions at all reports `0 attributed row(s)`, which is itself the
> finding: agentcrm's S-series carries none, which is why its depth-3 chain had to be traced
> by hand.

The count is printed faithfully. What is wrong is the label and the exit code around it. §4b
also says `project-maintenance.sh` "runs it and reports it as a finding" — on exit 0 with the
word clean, it reports nothing.

**agentcrm is the proof, on the day the tool shipped.** Its register carried
`S6 → S9 → S11 → S18`, depth 3, and `S11` carved six rows against a budget of two. Both are
exactly what §§2–3 forbid, both were traced by hand out of the Register history, and
`--carves` answered `carve shape: clean — 0 attributed row(s)` over that same file.

This is `.claude/rules/mutation-timeouts.md` trap 4 in the tool written to stop trap 4: an
enumeration that finds nothing rendering identically to a count of zero. The rule's own
authors saw it — the sentence in §4b is that observation — and the script did not follow.

**Fix shape** (not started): `len(parent) == 0` on a register with more than a handful of rows
is its own verdict — `carve shape: unmeasurable — 0 attributed row(s) of N; depth and budget
cannot be computed from this register`, with a non-zero exit so the maintenance pass surfaces
it. Keep `clean` for the case it was meant for: attributions present, none over budget, none
past depth 2. The threshold below which "no attributions" is honest (a young register really
has no carves yet) needs measuring across the machine's registers, not guessing.


## 031 — dotnet-test-prints-passed-over-an-aborted-run

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

