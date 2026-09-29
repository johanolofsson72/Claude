# 012 — core-file comments hold real scenario ids

Track: spec-only [hardened]. No entity, no state machine, no new external surface. Nine CORE
production scripts (comments only), one CORE self-test, register bookkeeping. The size trigger
(≥ 6 files) fires, so the hardened additions run, scaled to a change that alters no executable line
outside the self-test.

Found as consultpilot H7bp (`consultpilot/specs/INDEX.pending.md`, "H7bp — a CORE file's comments
take real scenario ids back").

## Problem

A scenario id is a coverage claim wherever a gate reads it. consultpilot's accounting gate
(`validate-scenario-id-accounting.sh`) counts every id under `tests/` **and `scripts/`** as traced.
The template's own `validate-scenario-traceability.sh` reads whatever roots a project declares, and a
project that declares `scripts` (F005, ighweld) gets the same reading.

Nine CORE production scripts carry literal SC-ids in their comments, and the sync overwrites them
unconditionally in every project:

| File | What the comment does |
|---|---|
| `bash-write-detect-hook.sh`, `bash-write-guard-hook.sh`, `bash_write_targets.py`, `validate-no-sigpipe-assertions.sh`, `validate-register-ids.sh` | a `Covers:` line listing consultpilot's own row ids (48 ids) |
| `validate-scenario-traceability.sh`, `scenario-map-rows.sh` | ids from agentcrm, consultpilot and msroute as worked examples (SC-436, SC-155, SC-033b, SC-741, SC-1165, …) |
| `template-autosync.sh`, `spec-register-orientation-hook.sh` | a spec-kit success criterion (SC-06) and a consultpilot row (SC-1444) as provenance |

Two consequences, both silent:

1. **A deleted test looks covered.** On consultpilot the ids in a `Covers:` line are real rows. When
   the test that proves one of them is deleted, the CORE comment still names it, and the gate still
   reads the row as covered. It is backed by a comment, not by a test.
2. **Another project's ids land in every project.** On any other project, those same ids either
   collide with an unrelated row and cover it, or show up as dangling references nobody there can
   fix. The sync puts the file back on every run.

The comment is not the proof in any of these cases. The proof is the self-test that names the id,
and it still names it.

## Requirements

- R1 No CORE production script (a name in `CORE_SCRIPTS` whose basename does not start with `test-` or
  `test_`) contains a token the traceability gate reads as a scenario reference: neither
  `SC-<digits>[a-z]` nor `SC<digits>[a-z]_`.
- R2 Every `Covers:` line becomes a pointer to the self-test that names the ids. Audited id by id:
  all 47 ids but one are named by that self-test. The exception is consultpilot's sigpipe-sweep
  row, which nothing but the comment named. That is the defect itself, live, and it is recorded as
  F021 for consultpilot to give it a real test or a trace-gap marker.
- R3 A worked example keeps its meaning with a placeholder the gate cannot read (`SC-NNN`, `SC-NNNb`,
  `SCNNNN_`). Where the digit count is the point (the width rule), the placeholder says the width in
  words.
- R4 `scripts/test-validate-scenario-traceability.sh` gets a case that runs **the gate itself**, with
  `--roots` pointing at a copy of every CORE production script, against a one-row map. It fails and
  names file and id when any reference comes back: dangling, out-of-range or covered. The case
  reuses the gate's extractor, so it can never drift from what the gate reads.
- R5 The case has a sabotage arm. One id is planted in a comment of one copied file, and the case
  must go red and name that file.
- R6 CORE **test** files are out of scope for R1. Naming an id is how a test proves a scenario, and
  in the project the test was written for, that name is the coverage.

## Out of scope

- Admitting `scripts/` as a reference root (F005). It stays an open finding.
- `.claude/rules/scenarios.md` and the project-wizard skill. Their example maps are documentation
  under `.claude/`, which no reference root contains.
- consultpilot's own H7bp self-test change. It already landed there.

## Acceptance

- A1 `grep -nE '\bSC-[0-9]+[a-z]?\b|(^|[^A-Za-z0-9])SC[0-9]+[a-z]?_'` over the CORE production
  scripts prints nothing.
- A2 The new case passes on the tree, and the gate reports 0 references over the copied scripts.
- A3 The sabotage arm is red, naming the planted file.
- A4 `test-validate-scenario-traceability.sh` is green, and every suite that exercises a touched
  script is green.
- A6 The census is switched off only by an internal flag (`--skip-core-census`, passed by
  `sab_run`), never by an environment variable. A failed copy is a FAIL. The underscore form
  (`SCNNNN_`) has its own sabotage arm (case40e).
- A5 `bash -n` / `python3 -m py_compile` pass on every touched file. The diff outside the self-test
  touches comment lines only.

## Threat model

The trust boundary is the gate's evidence: a coverage figure that a developer takes as proof.

| STRIDE | Threat | Mitigation |
|---|---|---|
| Spoofing | a comment passes as a test and covers a row | R1 + R4: no production CORE file can name an id, and the gate itself checks it |
| Tampering | a later edit re-adds an id to a CORE comment | R4 runs in the self-test, which `run-gates.sh` and the sync's test pass execute |
| Repudiation | nobody can tell which file re-added it | R4 names file and id |
| Information disclosure | another project's row ids ship to every project | R1 removes them from production files |
| Denial of service | the new case slows a self-test that runs close to its timeout (H7bq) | one gate run over about 60 files; measured in the run log |
| Elevation of privilege | n/a: nothing executes differently | A5 |

## Clarifications

### Session 2026-09-29

- Q: Should test-file ids be scrubbed too? → A: No (R6). There the id is the proof.
- Q: Use a new validator script, or a case in the existing self-test? → A: A case in the existing
  self-test. A new CORE gate would need runner registration in every project, which is row 014's
  open defect, and it would copy the gate's regex.
- Q: Which placeholder? → A: `SC-NNN` and its shapes. They carry no digits, so neither alternative in
  the gate's pattern can match.
