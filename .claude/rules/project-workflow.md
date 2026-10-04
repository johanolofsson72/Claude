# Project workflow rule (solo vs team, PR usage)

Before suggesting a pull request or any PR-based flow, know whether the project is **solo or team** and whether it **uses PRs**. Long form (memory template, the full pre-081 and pre-099 text): `.claude/docs/project-workflow-rationale.md`.

## The check (BLOCKING — before any PR suggestion)

1. Read `project_workflow.md` in the project memory and follow it.
2. If it is missing, ask **once** with one `AskUserQuestion` holding two questions: staffing (`Solo` / `Team` / `Mixed`) and PRs (`No — direct push` / `Yes — always` / `Sometimes`).
3. Save the answer as memory `project_workflow.md` and add a pointer line to `MEMORY.md`.

## Acting on it

`PRs=no` → never mention or nudge toward PRs; commit and push directly (`commit-commands:commit` + `git push`, never `commit-push-pr`). `PRs=yes` → the standard PR flow. `PRs=sometimes` → ask per change. Re-ask only when the user says the workflow changed. This governs PR ceremony only: direct push never skips a pipeline phase, a hook, validation, or the register's per-spec stop.
