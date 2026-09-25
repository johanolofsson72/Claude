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


## 037 — sync-copies-nothing-under-zsh

_Opened 2026-09-07 from hetznerradar's bootstrap (T0). Template-owned per `.claude/rules/carve-budget.md` §4._

`scripts/sync-prompt.md` Step 5c mirrors the CORE scripts into a project with:

```bash
CORE_SCRIPTS_LIST=$(bash "$TEMPLATE/scripts/template-autosync.sh" --list-core-scripts)
for s in $CORE_SCRIPTS_LIST; do
```

An unquoted parameter expansion word-splits in bash and **does not** in zsh, which is the
developer's login shell. The 105 newline-separated names arrive as **one** value, `[ -f
"$TEMPLATE/scripts/$s" ]` is false for that one impossible filename, and the loop copies nothing.

What makes this the expensive kind: the failure path and the success path print the same sentence.
`ABSENT` collects the one bogus name and `[WARN]` names it, but the line the reader takes away is
`[OK] 0 core enforcement script(s) mirrored`. **A project bootstrapped this way gets no PreToolUse
guards at all, and a green report saying so.** That is the same shape the block's own comment
records for the hardcoded list it replaced — "a list that is merely INCOMPLETE looks exactly like a
list that is finished" — reappearing one layer down, in the iteration rather than the list.

Fix: `while IFS= read -r s; do … done <<< "$CORE_SCRIPTS_LIST"` (or a `printf %s | while read`
pipeline), which splits on newlines in both shells. Then make the count load-bearing: a copy pass
that mirrors **zero** of a non-empty CORE list is a failure, not an `[OK]`. The guard against the
next variant of this is the assertion, not the loop.

Scope: one block in `sync-prompt.md`, plus a check that no sibling `for x in $VAR` over a
command-substituted list survives elsewhere in the sync path.

## 038 — freshness-calls-a-scan-error-a-verified-secret

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

## 039 — core-guard-blocks-its-own-first-install

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

## 040 — harness-writes-what-no-project-ignores

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

## 041 — mutation-timeouts-rule-was-never-written

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

## 047 — stryker-spans-fail-silently-and-score-well (from ighweld-2026, 2026-09-16)

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

## 048 — sc-id-space-is-three-digits-and-full (from ighweld-2026, 2026-09-16)

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

## 049 — a-held-row-cannot-be-written-to (from ighweld-2026, 2026-09-16)

`spec_active.py` resolves the active spec and skips `- [!]` held rows — correct, and
`.claude/rules/spec-register.md` says so explicitly: a held row must never be offered as the active
row, or a banner quietly overrules the decision to hold it.

`scripts/spec-run-log-hook.sh` resolves through that same function. So the moment a row is held, the
run log for it can no longer be appended to (F139, F195).

Holding a row is precisely the moment the note matters — somebody stopped for a reason the register
cannot express as a dependency, and the next session needs to know what it was. The two needs are not
in conflict; they are two different questions asked of one resolver. "Which row should I work?" must
skip held rows. "Which row is this note about?" must not.

## 050 — allium-cli-warns-on-every-spec-it-has (from ighweld-2026, 2026-09-16)

`allium check` emits "deferred specification should include a location hint" for every `deferred` in
every spec in the project (F080). ighweld probed the syntax the lint seems to want — `in "p"`, `"p"`,
`{ lo… }` — and its own parser rejects each one (F001, F031), so there is no spelling that satisfies
it.

A warning that fires on every spec and cannot be satisfied is noise that trains people to skip the
whole report — which then hides the warnings that mean something. Either implement the syntax, or drop
the lint.

F089 is a second allium-cli defect found the same way: a rule that assigns a status through a
trigger-param binding (`when: SyncPush(item)` + `ensures: item.status = …`) is not accepted.

## 051 — maintenance-suite-blind-to-standalone-node-tests (from emaljen, 2026-09-18)

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

---

## 052 — maintenance-runs-what-it-finds

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

## 024 — sigpipe-backlog-in-production-scripts

**Evidence from msroute F008, reported 2026-09-25** (verbatim):

> F008 — harness — 2026-09-08 · from spec 010 — TemplateSyncDirectionTests.The_commit_named_is_the_one_holding_the_restored_content fails only under the full unit suite: template-autosync.sh:252 printf hits SIGPIPE and the SubprocessStderr guard expects silence. Passes in isolation. Same class as M2. Template-owned

Line 252 is msroute's copy at the time. In the template as of 2026-09-25 the matching pipelines are
`is_core()` at `scripts/template-autosync.sh:270-271` (`printf '%s\n' $CORE_SCRIPTS | grep -qx "$1"`):
`grep -q` exits on the first match, the still-writing `printf` takes SIGPIPE, and bash prints a
write error to stderr. `validate-no-sigpipe-assertions.sh --all` lists both lines as UNDECIDED.
This one is not a harmless diagnostic: a consumer that asserts an empty stderr fails, and only under
load, which is why it passes in isolation. A candidate for the first of the one-at-a-time fixes
(e.g. `case " $CORE_SCRIPTS " in *" $1 "*)` with no pipe at all).

## 053 — stryker-tmp-outlives-its-run (from msroute, 2026-09-25)

Reported by msroute F007, 2026-09-25 (verbatim):

> F007 — harness — 2026-09-08 · from spec 010 — Abandoned .stryker-tmp sandboxes are now excluded by four separate consumers (project-freshness, project-maintenance, vitest, eslint); the fix is to stop the directory existing — sweep on entry of the next run, or move tempDirName out of the tree. Template-owned

Related product-side row: msroute `007cm — stryker-tmp-untracked-and-trips-the-guard`, whose guard
half was closed 2026-09-03 by syncing 16 CORE scripts. Each new consumer of the tree has had to learn
the exclusion separately; a fifth will too. Fix at the source: sweep stale `.stryker-tmp` when a
mutation run starts, or point Stryker's `tempDirName` outside the working tree.

## 054 — finding-ids-collide-across-lanes

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

## 058 — write-guard-resolves-paths-against-the-wrong-root

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

## 060 — sc-ids-have-no-allocator

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

## 017 — canary-and-row-budget-do-not-compose

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

## 044 — traceability-gate-cannot-tell-zero-from-broken

**A second reporting defect in the same script, from agentcrm F316, 2026-09-22.** The gate printed

    part of the map was unreadable (see above)

with nothing above it naming what. The cause was one map row with six cells instead of five (a
doubled pipe); the parser dropped 31 rows silently, and the only trace was a row count that did not
add up. The reader is told a fraction of the map was lost and given no way to find it.

Same class as the row's own subject — a catastrophic-sounding report with a trivial cause and no
handle — so it wants fixing in the same pass: name the file and the line number of every row the
parser refused, and say how many were dropped. "See above" must not be printed unless something was.

## 059 — pipeline-state-guard-denies-during-a-merge

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
