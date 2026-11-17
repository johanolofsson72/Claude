# 106 — downstream core red, part 2

Track: spec-only, hardened. Hardened by trigger 4 (an estimated ≥ 6 files) and because R4 widens
what the sync adds to every project. No entity, state machine or concurrency, so no `.allium` and
no `/tla`. Findings: F196 (1–3), F203, F205, F207, F211, F233, F234, verbatim in `specs/FINDINGS.md`.

## Problem

Measured 2026-11-17 at 49f9046. All 94 CORE gates were run with stdin closed and a 300 s bound in
the template tree and in two scratch sandboxes (local clones of agentcrm and billing re-synced from
the template working tree through `drive_sync --force --no-commit`).

- **Template tree:** 92/94 green. `test-core-owed-tick-guard` is red only under a parallel run
  (45/45 alone). `validate-fixture-map-ids` exits 3 (NOT RUN) because the template has no scenario
  map. Every other F205 red has already been fixed by specs 086–105.
- **agentcrm:** 11 red. **billing:** 6 red.

| Red | Where | Owner | Cause |
|---|---|---|---|
| test-template-identity 105-R5 | both | template | The test expects `upstream` from a hanging git. A synced tree correctly answers `downstream` (the sync stamp). |
| validate-rule-citations, test-validate-rule-citations | agentcrm | template | Scans the stale project-local `scripts/sync-prompt.md` (F234). |
| validate-rule-citations, test-validate-rule-citations | billing | template | `design-references.md` (rule) and `design-reference-library.md` (doc) never reached billing. Rules and docs are add-if-missing only by name, and nothing checks the names against the citations (F233). |
| test-context-budget | billing | template | Takes any tree without a root-level language marker for the template (F196 (3)). |
| core-gates.sh awk warning | Linux | template | `awk -v shape='…\.sh$'` asks gawk to process an escape, and gawk warns. project-maintenance reads `2>&1` and runs the warning as a test name (F203). |
| `sha=local-unknown` stamp | billing 2026-10-05 | template | An x86 git first on PATH could not run. The sync stamped a made-up SHA instead of stopping, and `harness-gitignore.sh --tracked` printed nothing (F196 (1), (2)). |
| validate-sync-sandbox-declarations (+2 tests) | agentcrm | project | `core-divergence-check.sh:66` runs `eval "$(sed … "$SYNC")"`. eval runs text read out of the sync, so the gate is right. The message printed `eval ""` and led F207 to misdiagnose it. |
| test-portability-audit, test-hook-channels, test-archive-spec-history case11, test-runtime-markers-ignored | agentcrm, billing | project | Project-owned scripts, settings, maps and a tracked marker the sync already reports. |
| test-sync-count-honesty | agentcrm | open | A published 2026-09-01 sync commit claims 2/0 with 0/0 in it. Not reproduced here. Recorded as a finding. |

Parity probe (F233): CORE rules, CORE scripts, RULE_DOCS and the skills cite six docs that are not
in RULE_DOCS. Across the 47 synced projects under `~/repos`, 6 lack one or more of them.

## Requirements

- **R1 — A git that cannot run stops the sync and the tracked report (F196 (1), (2)).**
  `resolve_local_template` asks git for the clone's HEAD before the dirty test. If git cannot
  answer, the sync writes nothing, prints why (which git binary, the clone path), and exits 0 like
  the dirty refusal (1 under `--accept-local`). `local-unknown` disappears.
  `harness-gitignore.sh --tracked` exits non-zero (4, as built) with a reason when `git --version` fails, instead of
  printing nothing.
- **R2 — core-gates.sh is quiet, and the pass reads its list from stdout (F203).** The shape goes
  to awk through `ENVIRON`, which awk does not escape-process. Section 5b of project-maintenance.sh
  reads core-gates.sh stdout as the list and keeps stderr for its error message.
- **R3 — validate-rule-citations skips the sync-prompt snapshot downstream (F234).** When
  `self_test_subject` answers `downstream`, `scripts/sync-prompt.md` is not scanned. Upstream it is.
- **R4 — Everything an always-shipped file cites reaches every project (F233).**
  - RULE_DOCS gains every template doc that a CORE rule, a CORE script, a RULE_DOC, a RULE_ADDS
    rule or a skill cites.
  - New `RULE_ADDS` (rules added when missing, then manifest-protected like a doc):
    `design-references.md`. It is path-scoped to frontend files, so it is inert elsewhere.
  - Stack rules (`dotnet`, `frontend`, `sqlite`, `wordpress`) are a per-project decision and stay
    out. Where an always-shipped file cites one by path, it is reworded to name the rule without
    the path.
  - A parity check in `test-template-autosync-ships.sh` (upstream only) fails on any such citation
    that is neither in CORE_RULES/RULE_ADDS (rules) nor in RULE_DOCS (docs).
- **R5 — test-context-budget asks self_test_subject (F196 (3)).** Downstream, the template ratchet
  is skipped whatever markers sit at the root.
- **R6 — test-template-identity 105-R5 expects the tree's own answer.** A hanging git leaves only
  the sync stamp to answer, so the expected `self_test_subject` is `downstream` when
  `.claude/.template-sync` exists and `upstream` otherwise.
- **R7 — The sandbox gate names the eval case (F207).** When rule (c) fires and the target sits
  inside a command substitution, the report says eval runs text read out of the sync and points at
  `drive_sync_readonly … --list-core-scripts | --list-core-rules`. The verdict does not change.
- **R8 — Tests and evidence.** Each behaviour gets a `[106]` case in the suite that owns it. The
  sandbox run is repeated after the fix, and every remaining red is project-owned or recorded.

## Threat model

New trust boundary: none. R4 widens what the sync adds to a project. R1 changes a failure path.

| STRIDE | Threat | Mitigation |
|---|---|---|
| Tampering | A doc or rule added by RULE_DOCS/RULE_ADDS overwrites a project's edit. | Add-if-missing only. After that it is manifest-protected: a local edit is reported and kept, never overwritten (spec 073 semantics, unchanged). |
| Tampering | RULE_ADDS turns a deliberate stack removal into a re-add. | Stack rules are excluded by name. `design-references.md` is path-scoped and cited by the always-shipped project-wizard skill. |
| Spoofing | A broken git produces a stamp that claims a SHA it never read. | R1: no stamp is written; the run refuses. |
| Repudiation | The refusal is silent. | It prints the git path and the clone. The `--tracked` exit 2 carries a reason. |
| Information disclosure | Re-adding `deployment.md` (live4 host and ssh detail) to projects that removed it by decision, some public (adversarial review #1). | Decision docs (`deployment.md`, `spot-architecture.md`, `spec-testing-checklist.md`) are never added; the parity test fails if one enters RULE_DOCS. The new messages print only local paths. |
| Denial of service | A project whose git cannot run is never synced. | That is the intent: a sync that cannot read its source has nothing true to write. SessionStart still exits 0. |
| Elevation of privilege | None. No new code runs from project or template data. | — |

### As built

- **R4 narrowed after the adversarial review.** `scripts/sync-prompt.md` has the developer remove
  `spec-testing-checklist.md` (no UI), `spot-architecture.md` (no live4) and `deployment.md` (a mobile
  app with no live4 backend). Adding them on every sync would undo that decision and push live4 host
  detail into projects that dropped it. They are stack-decision docs: never added, and listed in the
  parity test as expected citations (some sit in code paths that cannot be reworded). That is
  narrower than Q19's approval, so it is on the safe side of it. RULE_DOCS gained 10 docs, not 13.
- Stack-rule citations reworded to name the rule without the path: project-update, project-wizard,
  design-references.md, deployment.md, spot-architecture.md.
- **R1 widened after the review.** A failing `git status` is unreadable too (a corrupt or locked
  index, a safe.directory refusal). An unreadable candidate is passed over and the walk goes on; the
  run refuses only when no candidate resolves. A `.git` symlink counts as a clone.
- `--tracked` uses exit 4 for "could not list" (2 is the usage error), including a `.git` git will
  not read. The sync quotes its reason.
- The sandbox-gate hint names eval, -c and watch, since rule (c) covers all three.

## Non-goals

Project-owned reds: agentcrm's `core-divergence-check.sh` eval, its portability audit, its Write
twins, its map budget, and billing's tracked marker. These are reported to the developer and not
edited from here. Exit-3 semantics in the maintenance pass (row 107). The parallel-load flake in
test-core-owed-tick-guard and the historical agentcrm sync commit, both recorded as findings.

## Clarifications

### Session 2026-11-17 (auto-picked, recommended option; Q19–Q20 developer-answered)

- Q: Derive RULE_DOCS at sync time or keep the hand list behind a parity test? → A: Keep the list,
  test it. Deriving it would make what ships depend on how the prose is worded.
- Q: R1 refusal: fall back to the remote tarball? → A: No. The remote path needs git too, and a
  project whose git cannot run cannot commit what the sync writes.
- Q: R3: does the skip extend to other template-only files? → A: No, only `scripts/sync-prompt.md`,
  the one snapshot measured. A wider skip would hide project-owned citations.
- Q: R4: which citations count? → A: `.claude/(rules|docs)/<name>.md` in an always-shipped file,
  not preceded by `/` (a fixture under a variable root), naming a file the template has.
- Q: R4 widening and R1 exit code → A: developer-confirmed (interview Q19, Q20).
