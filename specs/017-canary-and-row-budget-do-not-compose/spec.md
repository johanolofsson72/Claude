# 017 — canary and row budget do not compose

Track: spec-only. No entity, no state machine, no new external surface. Not hardened: four files
plus one new read-only CORE helper, no auth/PII/upload, no concurrency.

Found as msroute 007ck, measured a second time in agentcrm (F201). Diagnosis:
`specs/INDEX.pending.md` § 017.

## Problem

Two rules govern the size of `specs/INDEX.md`. Every row stays inside 300 bytes, and the whole file
stays under the 25 KB context-cost canary. They do not compose. A register can obey the first and
still break the second, and when it does the canary tells the developer to run
`archive-completed-rows.sh`, which correctly has nothing to do.

Measured 2026-09-29:

| register | total | done rows | open rows | history | prose | rows over 300 B |
|---|---|---|---|---|---|---|
| msroute | 29 897 | 22 306 (75%) | 4 082 | 1 051 | 2 458 | 0 |
| agentcrm | 60 484 | 22 005 | 4 653 | 793 | 33 033 (55%) | 1 |

These are two defects with one symptom:

- **agentcrm**: the bytes are prose written inside `## Specs` (a two-lane explainer, dependency
  tables, rule commentary). No gate has an opinion about it, and the canary names the row archiver.
- **msroute**: the bytes are ticked rows. Every row is under budget and archived verbatim in
  `INDEX.completed.md`. No script in the template can shrink the file further. Removing ticked
  rows would break the 13 consumers that count them (id allocation, checkpoint cadence, carve
  ratio, maintenance cadence). The canary still fires every session with advice that cannot be
  taken.

A warning that cannot be acted on is noise, and noise teaches the reader to skip the banner.
agentcrm has carried this one unactioned since 2026-08-29.

## Requirements

- R1 A new CORE helper, `scripts/register-bytes.sh [--max-bytes N] FILE`, splits a register into
  four parts and prints one `key=value` line per part:
  - `rows`: every status row (`- [ ]`, `- [/]`, `- [!]`, `- [x]`) plus its indented continuation
    lines, with the number over the row budget (`over=`, default 300, same as the row archiver);
  - `history`: the `## Register history` section, with its entry count and the number over budget;
  - `prose`: everything else (title, preamble, notes, tables, blank lines);
  - `total`.
  Each part carries its share of the total as an integer percentage.
- R2 The helper also prints one `move=<part> <advice>` line for each part that **has an available
  move**, largest part first:
  - rows, when `over > 0`: `scripts/archive-completed-rows.sh`, with the count;
  - history, when there are more than 5 entries or any entry is over budget:
    `scripts/archive-spec-history.sh --keep 5`;
  - prose, when it is over 4096 bytes: move it to a sibling the pipeline does not read
    (`specs/INDEX.notes.md`; `INDEX.history.md` and `INDEX.pending.md` are the precedent) and leave
    a one-line pointer.
  No `move=` line means the register is **compliant**: nothing in the template shrinks it.
- R3 Exit 0 = answered. 1 = the file does not exist. 2 = usage error. A consumer that gets a
  non-zero exit falls back to the old wording. The canary must never go silent because the helper
  is missing or failed.
- R4 `spec-register-orientation-hook.sh`: when `INDEX.md` is over 25 KB, the canary names the
  breakdown and prints the `move=` advice in place of the fixed row-archiver paragraph.
  - With at least one move, the register joins the attention-mode canary, as today.
  - With no move, it does **not** trigger attention mode. It adds one informational line
    (`· INDEX.md NN KB — every part complies; nothing archives it further. Read it targeted.`),
    shown in both quiet and attention mode, and it never counts as actionable.
- R5 `project-maintenance.sh`: when `INDEX.md` is over 25 KB, the `[CONTEXT-COST]` finding names
  the part and the move. With no move it is a `note`, not an `add`: the verdict stays clean, because
  a red verdict no one can clear is the same noise.
- R6 The scenario-map canary is unchanged. It measures a different file and has its own remedy
  (row 008).
- R7 `.claude/rules/spec-register.md` "Keep the register lean" gets one bullet: prose lives outside
  the register, and the canary names which part the bytes are in.
- R8 The helper is added to `CORE_SCRIPTS` (both consumers are CORE, so it must travel with them)
  along with its self-test `scripts/test-register-bytes.sh`.

## Out of scope

- Folding ticked rows out of `INDEX.md`. That is the only move left for msroute's shape, and it
  changes what 13 consumers read. It is recorded as a finding with that evidence, not built here.
  The register is frozen, so it can only become a row through an approved proposal.
- Moving any project's prose. That is each project's own edit. The canary now tells them where.
- Changing the 25 KB threshold or the 300-byte budget.

## Acceptance

- A1 `bash scripts/test-register-bytes.sh` is green. It covers the partition arithmetic, each move
  rule on both sides of its threshold, continuation lines, a missing file, and bad arguments.
- A2 `bash scripts/test-scenario-map-canary.sh` is green, with new cases: a prose-heavy register
  gets the prose move and no row-archiver advice at both sites; a compliant row-heavy register
  produces no attention-mode canary, shows the info line, and maintenance stays clean.
- A3 On live registers: agentcrm names prose as the first move, msroute reports compliant, and the
  template's own register is under the threshold and silent.
- A4 `test-project-maintenance.sh`, `test-core-gates.sh`, `test-template-autosync-unlisted.sh` and
  `test-sync-prompt-core-parity.sh` are green. `bash -n` passes, and `validate-portability.sh` is
  clean on the new scripts.

## Clarifications

### Session 2026-09-29 (auto-picked, recommended options)

- Q: Is the prose threshold (4096 B) a share or an absolute? → A: Absolute. The template's own
  preamble is about 1.2 KB, and msroute's non-row, non-history bytes are 2.4 KB and legitimate
  (title, header, freeze line). 4 KB separates those from agentcrm's 33 KB with plenty of margin,
  and a share would fire on a small register whose preamble is most of it.
- Q: Should the compliant case disappear from the banner entirely? → A: No. One informational line
  stays, because the file really is large, and saying so once per session is cheaper than someone
  re-measuring it. It does not trigger attention mode.
- Q: Should the helper call `archive-completed-rows.sh` to decide whether rows are compliant? → A: No.
  It counts rows over the budget itself, using the same byte rule. One awk pass at SessionStart
  instead of a second script.
