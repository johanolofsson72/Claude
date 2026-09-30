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

## 044 — traceability-gate-cannot-tell-zero-from-broken

**A second reporting defect in the same script, from agentcrm F316, 2026-09-22.** The gate printed

    part of the map was unreadable (see above)

with nothing above it naming what. The cause was one map row with six cells instead of five (a
doubled pipe); the parser dropped 31 rows silently, and the only trace was a row count that did not
add up. The reader is told a fraction of the map was lost and given no way to find it.

Same class as the row's own subject — a catastrophic-sounding report with a trivial cause and no
handle — so it wants fixing in the same pass: name the file and the line number of every row the
parser refused, and say how many were dropped. "See above" must not be printed unless something was.
