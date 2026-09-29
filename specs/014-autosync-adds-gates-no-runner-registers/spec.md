# 014 — autosync adds gates, no runner registers them

Track: spec-only. No entity, no state machine, no new external surface beyond one read-only CORE tool.
Not hardened: three files, no auth/PII/upload, no concurrency.

Found as consultpilot H7av (`consultpilot/specs/INDEX.pending.md`, "H7av"), and argued the other
way by consultpilot H7be (the note above `GATES` in `consultpilot/scripts/run-gates.sh`).

## Problem

The sync delivers CORE scripts. Some of them are gates: `test-*.sh`, `validate-*.sh`. A project
that runs its gates through a registry (consultpilot's `run-gates.sh`: `GATES` + `EXCLUDED`, and a
drift check over `scripts/(test|validate|verify|check)-*.sh`) learns about a new CORE gate only when
its drift check trips. Until somebody registers the file by hand, the runner exits 2 (DRIFT), and
drift outranks every gate verdict it prints.

H7be measured the hand-registration latency at a median of 0 days (max 2) over eight arrivals and
concluded that no second mechanism was needed. Measured again on 2026-09-29, the premise no longer
holds. **14 CORE gate-shaped scripts are present in consultpilot and registered nowhere**
(`test-finding.sh`, `test-hook-channels.sh`, `test-lane-merge-drivers.sh`, `test-maintenance-due.sh`,
`test-maintenance-ledger.sh`, `test-next-register-id.sh`, `test-portability-audit.sh`,
`test-register-convergence.sh`, `test-register-similarity.sh`, `test-skill-reachable.sh`,
`test-speckit-sync.sh`, `test-sync-prompt-core-parity.sh`, `test-sync-prompt-zsh.sh`,
`validate-portability.sh`). Hand registration does not keep up with the rate the template ships.

H7be's objection still applies to one design. A sync that *refuses* an unregistered gate is a
second oracle in CORE, and it cannot see a project's registry. This spec builds something else:
the **CORE half of the registry**, shipped in the same file as the list of scripts it describes.
The template is the only party that knows whether its own `test-scenario-map-fixtures.sh` is a
sourced library or a gate. A project should ask for that answer, not work it out again.

F004 is the same defect seen from the other side. The template ships `test-coverage-hook.sh`, a
PostToolUse hook that matches the gate pattern. A runner that globs the pattern hangs on it, and
nothing in the template warns anyone. consultpilot carries a hand-written exclusion for it.

## Requirements

- R1 A new CORE tool, `scripts/core-gates.sh`, defines the **gate shape** in one place: a basename
  matching `^(test|validate|verify|check)-.*\.sh$`, the discovery pattern consultpilot's runner uses.
  The tool is not gate-shaped itself.
- R2 `core-gates.sh` holds the **non-gate table**, one `name|reason` per line. Each line names a
  gate-shaped script that is **not** a standalone gate (it needs arguments, it is a sourced library,
  it reads hook JSON on stdin, it recurses, it needs a tool a project does not have, or it is a
  report whose red is a backlog), with the reason in words.
- R3 **Gate by default.** A new CORE script in the gate shape is a gate as soon as it is added to
  `CORE_SCRIPTS`. Nobody has to add it to a second list. Only an exclusion takes a written decision.
- R4 `bash scripts/core-gates.sh` prints every gate, one basename per line, sorted: the output of
  `template-autosync.sh --list-core-scripts` filtered by the shape, minus the table.
  `--non-gates` prints the table, sorted. Exit 0 = answered. Exit 2 = cannot answer
  (`template-autosync.sh` missing, the query failed, the derived gate set is empty, or a table line
  is malformed: no `|`, empty reason, not gate-shaped, or a duplicate). A consumer never reads exit 2
  as an empty list. **No new query mode.** The query-mode list in
  `validate-sync-sandbox-declarations.sh` is capped at four by a developer decision (2026-09-29).
  `--list-core-scripts` is one of the four.
- R5 The table may also name gate-shaped `TEMPLATE_ONLY_SCRIPTS` (`test-coverage-hook.sh`,
  `verify-local-llm-hooks.sh` and the template-authoring tests). A project can hold a stale copy of
  one of them, and its runner has to know not to run it. This closes F004.
- R6 A new self-test, `scripts/test-core-gates.sh` (CORE, gate-shaped, therefore a gate by R3):
  - a. every table name is in `CORE_SCRIPTS` or `TEMPLATE_ONLY_SCRIPTS` (a stale or misspelled
    exclusion fails, and the message names it);
  - b. every gate-shaped template-only script is in the table (none is ever run downstream);
  - c. gates ∪ CORE table names = the CORE gate-shaped set, gates ∩ table = ∅;
  - d. every gate exists in `scripts/` (a CORE name with no bytes cannot be run);
  - e. `core-gates.sh` and `test-core-gates.sh` are in `CORE_SCRIPTS` (else neither reaches a
    project);
  - f. sabotage arms, each on a copy of `core-gates.sh` beside a stub `template-autosync.sh` in a
    mktemp dir: a malformed line (no `|`), an empty reason, a duplicate, a non-gate-shaped name, a
    failing query, and an empty CORE set must each exit 2 and name the cause. A new gate-shaped
    stub CORE name must appear among the gates without being written anywhere else, which proves R3.
- R7 The classification is **measured, not guessed**. Every CORE gate-shaped script runs once in the
  template with no arguments and stdin closed. Its exit code and runtime are recorded in the
  run-log, and every non-gate reason rests on that measurement or on reading the file.

## Out of scope

- Changing consultpilot's `run-gates.sh` to read the two modes. It is project-owned and has its own
  pipeline. Recorded as a finding with the adoption shape (R-adopt below).
- Shipping a generic gate runner to projects that have none. Recorded as a finding if measured.
- Refusing to deliver an unregistered gate in the sync (H7be's rejected design, and still rejected).

## R-adopt (the consumer contract, for the finding)

A runner unions `scripts/` + each `core-gates.sh` line into its gates, and each
`core-gates.sh --non-gates` line into its exclusions. It keeps its own hand-written entries for
project-owned scripts. If `core-gates.sh` is missing or exits non-zero, the runner
reports that as drift and does not treat it as an empty list.

## Acceptance

- A1 `bash scripts/test-core-gates.sh` is green, and every sabotage arm behaves as R6f says.
- A2 `core-gates.sh` + `--non-gates` cover exactly the CORE gate-shaped names, and each of
  consultpilot's 14 unregistered names appears in one of the two.
- A3 `test-template-autosync-unlisted.sh`, `test-sync-prompt-core-parity.sh` and
  `validate-sync-sandbox-declarations.sh` are green with the two new CORE names.
- A4 `bash -n` passes on every touched script, and `validate-portability.sh` is clean on the new ones.

## Clarifications

### Session 2026-09-29 (auto-picked, recommended options)

- Q: Should `validate-scenario-traceability.sh` be a gate or a non-gate? → A: Non-gate. Its
  `uncovered` direction is a per-feature backlog that stays red for a long time on a real map, and
  `project-maintenance.sh` already runs it with that asymmetry. Its self-test is a gate.
- Q: Does a non-gate reason have to say where the script *is* exercised? → A: Where one exists, yes
  (a library names its consumers). The self-test checks only that the reason is non-empty. Content
  is for review.
- Q: Should the self-test run the gates it lists? → A: No. It checks the partition. Running them is
  the runner's job, and the R8 census is the one-time measurement recorded in the run-log.
