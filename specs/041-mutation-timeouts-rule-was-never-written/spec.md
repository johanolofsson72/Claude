# 041 — mutation-timeouts rule was never written

Track: spec-only. No entity, no state machine, no new external surface. Not hardened: one new
rule, one new validator and its test, two list entries in the sync, two one-line pointers.

Evidence: hetznerradar (`~/repos/radar`) T0, finding F004, plus the gremlins family F003, F021,
F023, F024 and F071. Diagnosis in `specs/INDEX.pending.md`.

## The defect

Ten places in the template cite `.claude/rules/mutation-timeouts.md`, most of them for its
"trap 4". The file does not exist and no commit ever removed it. Two rationale docs, five scripts
and three tests lean on a clause nobody can read:

| Citation | What it takes trap 4 to mean |
|---|---|
| `.claude/docs/carve-budget-rationale.md:163` | an unparseable attribution and no attribution must not render identically |
| `.claude/docs/lane-handoff-rationale.md:61` | an enumeration that drops what it cannot parse reports clean and broken identically |
| `scripts/maintenance-due.sh:139` | an unmeasured thing and a measured-clean thing must never render identically |
| `scripts/project-maintenance.sh:920` | an unrun suite and a green one must not render identically |
| `scripts/lane_status.py:54` | the empty result that looks like good news |
| `scripts/bash_write_targets.py:47` | a conclusion kept while its premise stopped being checked |
| `scripts/test-maintenance-due.sh:7` | "never run" rendering the same as "run and clean" |
| `scripts/test-bash-write-guard.sh:677` | control first: an empty result and an uncalled probe look identical |
| `scripts/test-lane-orientation.sh:11` | an enumeration is believable only after it finds a case you know is there |
| `scripts/test-scenario-map-rows.sh:24` | a widened guard must be shown to still bite (the known positive) |

The citations agree. Trap 4 is: **an unmeasured state and a clean state must never render
identically, and a detector is believed only after it has found a known positive.**

A read-only sweep of every tracked file outside `specs/` finds no other dangling
`.claude/rules/*.md` or `.claude/docs/*.md` citation. The only other misses are test fixtures that
the tests write under a temporary root (`demo-rule.md`, `keep.md`).

## Decision

1. **Write `.claude/rules/mutation-timeouts.md`** with five numbered traps. The mutation traps are
   the concrete cases, and trap 4 is the general principle they share, numbered so every existing
   citation resolves to what it meant:
   1. A timed-out mutant is counted as detected (Stryker's `(Killed + Timeout) / valid`; gremlins at
      its default coefficient printing 100.00% over 127 timeouts, F003).
   2. The headline is not comparable across runs, and more timeouts print a higher number (F024,
      F071).
   3. The run nobody waits for: a flag that makes the run feasible changes what it measures (F021,
      F063).
   4. An unmeasured state and a clean state must never render identically; control first.
   5. A coverage artefact reads as a gap (F023).
   The rule is path-scoped to mutation tooling files so it costs no context in a session that never
   touches one. The always-loaded `spec-hardening.md` and the on-demand `testing.md` point at it.
2. **Ship it.** Add `mutation-timeouts.md` to `CORE_RULES` in `scripts/template-autosync.sh`.
   `copy_file` adds a new file to a project only if it is CORE, so without this the rule stays as
   missing in projects as it was before.
3. **Stop it recurring.** `scripts/validate-rule-citations.sh [root]` (CORE) reads every tracked file
   outside `specs/`. It reports:
   - a cited `.claude/rules/<name>.md` or `.claude/docs/<name>.md` that does not exist, unless the
     same file builds that path under a variable root (a test fixture: `$T/.claude/rules/x.md`);
   - a `trap N` citation of a rule or doc (same line or the line before the citation) whose file
     has no `Trap N` heading;
   - zero citations found at all, as **unmeasurable** (exit 3), never as clean.
   Exit 0 prints the count of citations checked; exit 1 lists `path:line: reason`; exit 2 is a usage
   or environment error.
4. **Test.** `scripts/test-validate-rule-citations.sh` (CORE): fixture arms for each verdict, plus
   the real repository resolving clean. The real-repo arm is red on HEAD, which is the known
   positive.

## Out of scope

- Fixing gremlins or Stryker. The rule tells a reader how to read their numbers.
- A strict scorer in `project-maintenance.sh`. Its mutation section already labels Stryker's number
  with its provenance.
- The allium-cli false warnings (F025, F038). Same family, different tool, row 050.
- Wiring the validator into `project-maintenance.sh`. Row 052 covers maintenance running checks.
- Rewording the ten citations. They are correct once the file exists.

## Functional requirements

- FR-01 `.claude/rules/mutation-timeouts.md` exists, has `paths:` frontmatter, and defines
  `## Trap 1` to `## Trap 5`, each with the symptom, the measured evidence and what to do.
- FR-02 Trap 4 states the principle every citation relies on, including the known-positive and
  control-first half.
- FR-03 `mutation-timeouts.md` is in `CORE_RULES`.
- FR-04 `spec-hardening.md` (mutation gate) and `testing.md` (mutation section) point at the rule.
- FR-05 `validate-rule-citations.sh` reports missing cited rules/docs with `path:line`, exit 1.
- FR-06 It exempts a path the same file builds under a `$VAR/` root.
- FR-07 It reports a `trap N` that the cited file does not define, including a two-line citation.
- FR-08 It reports zero citations as unmeasurable, exit 3.
- FR-09 It skips `specs/`.
- FR-10 The validator and its test are in `CORE_SCRIPTS`.
- FR-11 The template itself validates clean.

## Scenarios

- SC-A a clean fixture: exit 0, prints the number of citations checked
- SC-B a citation of a missing rule: exit 1, names `file:line` and the path
- SC-C a citation of a missing doc: exit 1
- SC-D a `$T/.claude/rules/x.md` fixture path with a bare mention elsewhere in the file: exempt
- SC-E `trap 2` next to a rule that defines Trap 2: clean
- SC-F `trap 9` next to a rule that defines Trap 1..5: exit 1
- SC-G `trap 4 in` on one line, the rule path on the next: resolved
- SC-H `trap 4 in missing.md`, bare basename, file absent: exit 1
- SC-I a dangling citation under `specs/`: ignored
- SC-J no citations at all: exit 3, says unmeasurable
- SC-K not a git work tree: exit 2
- SC-L the real template: exit 0 (red on HEAD)
- SC-M the rule defines Trap 1..5 and has `paths:` frontmatter
- SC-N `template-autosync.sh --list-rules` includes `mutation-timeouts.md`

## Clarifications

### Session 2026-09-29

- Q: Should the validator also check `.claude/agents/` and skill citations? → A: No. The defect is
  rule and doc citations; agents and skills have their own reachability check (`skill-reachable.sh`).
- Q: Should a `trap N` citation of a file that defines no traps at all fail? → A: Yes. A trap
  citation that cannot resolve is the same dangling pointer as a missing file.
- Q: Should the rule get a separate `-rationale.md` doc? → A: No. The evidence is short enough to sit
  under each trap, and the rule only loads on mutation tooling files.
