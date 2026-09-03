# Pending-row diagnosis (archive)

The long form of rows not yet started. Never pipeline input.


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
