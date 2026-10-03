# 097 — prompt-audit cleanup

Track: spec-only (text in prompts, rules and one skill; no behaviour, no new state). Source: F149.
The H5 audit report and patch lived in that session's scratchpad and did not survive it, so the audit
was redone on 2026-10-03 against the current files, scoped to the five areas the row names.

## Findings (the audit)

| # | Area | Where | What is wrong |
|---|---|---|---|
| A1 | self-contradiction | `CLAUDE.md` Execution mode vs Context management | "Max 3 attempts per problem" (what `repeat-failure-guard-hook.sh` enforces, `ATTEMPT_LIMIT=3`) vs "After 2 failed fixes … `/clear`" |
| A2 | self-contradiction | `CLAUDE.md` Workflow | "Medium (2–5 files) → brief plan, then do it" contradicts the BLOCKING pipeline rule: anything touching 2+ files is not trivial and runs the pipeline |
| A3 | self-contradiction | `CLAUDE.md` Execution mode | "Larger features: interview the developer (`AskUserQuestion`)" contradicts the spec-interview rule, which is AUTO by default and asks only escalated or overflow questions |
| A4 | two stop lists | `.claude/rules/feature-pipeline.md` "When to stop" | a three-item subset of `continuous-execution.md`'s seven legitimate stops; a reader of the pipeline rule misses the register stop, the rewrite stop and the convergence stop |
| A5 | path | `.claude/skills/ui-ux-pro-max/SKILL.md` | every command runs `python3 skills/ui-ux-pro-max/scripts/search.py`; from a project root the script is at `.claude/skills/ui-ux-pro-max/scripts/search.py` |
| A6 | stale wizard CLAUDE.md | `.claude/skills/project-wizard/SKILL.md` 3B | points at "the hireflow CLAUDE.md" as the reference, and its embedded template carries A1–A3 and none of the template's BLOCKING rules (pipeline, interview, register, carve budget, scenarios), so a new project starts behind the template |
| A7 | old-model emphasis | the wizard's embedded template | `**ALWAYS**` on every line, `IMPORTANT:`, `NEVER`, "non-negotiable". Claude 5-family models follow plain instructions and over-apply shouted ones; the template's own `CLAUDE.md` already dropped this |
| A8 | language wording | `CLAUDE.md` Language | says English without saying where that comes from; the global `~/.claude/CLAUDE.md` makes a project's `language` setting the authority, and this one says `english`. The line should name it so the two never read as a contradiction again |

## Requirements

- **R1** fixes A1–A3 and A8 in `CLAUDE.md`, inside the 40 KB always-loaded cap.
- **R2** fixes A4: `feature-pipeline.md` "When to stop" points at `continuous-execution.md`'s list instead of keeping its own.
- **R3** fixes A5 in every command line of the ui-ux-pro-max skill.
- **R4** fixes A6 and A7 in the template's copy of the wizard: the reference is this template's `CLAUDE.md`, and the embedded general sections match it (the BLOCKING lines, the attempts, the workflow, the interview), without shouting. The project-specific placeholders stay. Other copies of the wizard (global, claude-skills) are not touched (memory: skill lineage divergence).
- **R5** no rule changes meaning beyond resolving a contradiction in favour of the side a hook or a BLOCKING rule enforces.

## Out of scope

- `~/.claude/CLAUDE.md` and the auto-memory: the developer's own files, outside the repository. Both are consistent with R1 already (global: a project's setting wins; memory: English here).
- A sweep of emphasis in `.claude/rules/`: `(BLOCKING)` is a label the hooks and DoD refer to, not shouting.

## Success criteria

- SC-A: `grep` finds no "2 failed fixes", no "hireflow", no `python3 skills/ui-ux-pro-max` in the repository's prompts.
- SC-B: `bash scripts/context-budget.sh` within budget; the full suite green (doc-citation and rule tests included).

## Clarifications

### Session 2026-10-03

- Q: Keep the wizard's embedded template at all, or point at the template's CLAUDE.md only? → A: Keep
  it (projects bootstrap offline from the skill), aligned with the template's CLAUDE.md; the instruction
  says the template's CLAUDE.md wins where they differ.
- Q: A8: change the language? → A: No. Name the source: the `language` key in `.claude/settings.json`.
