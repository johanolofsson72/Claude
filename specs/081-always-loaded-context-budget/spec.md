# 081 — always-loaded context budget

Track: spec-only (docs move, one measuring script, one test; no new entity, no state). Approved from
proposal F076 on 2026-10-01.

## Problem

Every session in this template loads `CLAUDE.md` and every `.claude/rules/*.md` without a `paths:`
frontmatter key. Measured 2026-10-01 after 080: 68,229 bytes (~17k tokens) before the first prompt.
`CLAUDE.md` is 15.4 KB and `spec-register.md` 12.1 KB. Much of it is rationale and enforcement
internals that a session needs only when it works on that machinery, and `CLAUDE.md`'s critical
rules restate rule files that are loaded anyway. Nothing measures the total, so it only grows: 080
itself added ~1 KB to two rules.

## Requirements

- R1 **Measure.** `scripts/context-budget.sh` prints, largest first, each always-loaded file with its
  bytes, then the total and the cap. Always-loaded means: `CLAUDE.md` and `.claude/CLAUDE.md` at the
  project root, every `.claude/rules/*.md` (recursively) whose YAML frontmatter has no `paths:` key,
  and any file `CLAUDE.md` imports with a line starting `@`. `CLAUDE.local.md` is reported on its own
  line and not counted (personal, never shipped). Exit 0 within the cap, 1 over it, 2 when it cannot
  measure. `--max-bytes N` sets the cap (default 40960); `--root DIR` the project.
- R2 **Ratchet.** `scripts/context-budget.baseline` records the template's measured total.
  `scripts/test-context-budget.sh` tests the script on fixtures and, in the template repo only, fails
  when the total exceeds the cap or the baseline. A total more than 1 KB under the baseline prints
  the command that lowers it, so the ratchet only moves down.
- R3 **Report in projects.** `project-maintenance.sh` prints one context-budget line. Over the cap
  is a note, never a failed run: a project's own `CLAUDE.md` is its business.
- R4 **Trim to ≤ 40 KB.** Rationale, history and enforcement internals move from the always-loaded
  files into the matching on-demand doc (`.claude/docs/*-rationale.md`, new ones where none exists),
  verbatim, with a one-line pointer left behind. The contract, every BLOCKING marker, every command a
  session must run, and every heading a script or doc cites stay. Nothing is deleted outright.
- R5 New scripts and the baseline are CORE (`template-autosync.sh`).

## Non-goals

Path-scoping more rules (each needs its own trigger analysis). Trimming scoped rules. Rewriting
the rules' content. Changing any project's own `CLAUDE.md`.

## Acceptance

`context-budget.sh` reports ≤ 40,960 bytes on the template. `test-context-budget.sh` is green and
goes red on a fixture over the cap, on a `paths:` rule counted as always-loaded, and on an
`@`-import not followed. Every heading cited elsewhere (`grep` of `rules/<file>.md` § and `→`
references) still resolves. `test-pipeline-hooks.sh` and the guard suites stay green.

## Clarifications

### Session 2026-10-01 (auto-picked)

- Q: Are nested `.claude/rules/sub/*.md` files counted? → A: Yes, recursively, as Claude Code loads them.
- Q: Does an @-import inside a rule file count? → A: Only imports from CLAUDE.md files; the template has none in rules, and the report names any it sees in rules as a note.
- Q: What if frontmatter has `paths: []` (empty)? → A: Still scoped by our reading; an empty list is a deliberate opt-out of always-loading.
- Q: Which doc receives text moved from CLAUDE.md? → A: The rationale doc of the rule it restates; CLAUDE.md-only material goes to `.claude/docs/claude-md-rationale.md`.
