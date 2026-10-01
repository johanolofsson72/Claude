# CLAUDE.md

Long form (the reasoning behind each line below): `.claude/docs/claude-md-rationale.md`.

## Critical rules (READ FIRST)

**(BLOCKING)** rules are enforced by hooks and by the Definition of Done. The rest are strong defaults.

- Read the code first. Base conclusions on evidence, and read the relevant files BEFORE answering about the codebase.
- Use Edit for surgical changes. Follow existing patterns. Verify with `dotnet build` + `dotnet test` before claiming done.
- **(BLOCKING)** Non-trivial work runs the full pipeline as **one task**, with no permission stops between phases. A trivial-fix bypass needs an explicit one-sentence classification. → `.claude/rules/feature-pipeline.md`
- **(BLOCKING)** Every spec gets a **15–25 question** interview in `<spec-dir>/interview.md` before `clarify`, AUTO-answered by default. Full/hardened specs also carry 3–5 developer-confirmed acceptance cases. → `.claude/rules/spec-interview.md`
- **(BLOCKING)** Before feature work, consult `specs/INDEX.md`. Work the next unchecked spec end to end (pipeline → commit → push → tick), then stop with the status summary. → `.claude/rules/spec-register.md`
- **(BLOCKING)** A spec that crosses a risk threshold runs the **hardened tier**. Every 5 specs, run an integration checkpoint. Full and hardened specs start after `/clear`. → `.claude/rules/spec-hardening.md`
- **(BLOCKING)** Carve budget: a finding is **recorded, not rowed** (`scripts/finding.sh --add`). → `.claude/rules/carve-budget.md`
- **(BLOCKING)** Keep the scenario map `specs/SCENARIOS.md` current. A gap or drift → **scenario interview**, never invent cases. → `.claude/rules/scenarios.md`
- **(BLOCKING)** Invoke the `frontend-design` skill BEFORE writing any UI code.
- **(BLOCKING)** Run generated human-facing text (docs, commits, PRs, email, README) through the `humanizer` skill.
- **(BLOCKING)** Testing: **unit + integration + E2E**, **PBT** for wide-input logic, **visual regression** for UI, one functional test per function, a destructive suite **sized per function**. The **mutation kill rate** is the gate. → `.claude/docs/testing.md`

## Execution mode (autonomous)

- Act without waiting for confirmation. Missing information is not a blocker: assume reasonably and continue. Fix errors yourself.
- Ask only about architecture or requirement interpretations that cannot reasonably be assumed.
- **Max 3 attempts per problem**, then `/clear` and try a different strategy. `scripts/repeat-failure-guard-hook.sh` enforces this.
- **Anti-stall:** with no clear task, pick the most likely one and act.
- **Hook feedback:** acknowledge it, handle it (fix it, or explain why it does not apply), and keep working. Never stop silently.
- **Larger features:** interview the developer (`AskUserQuestion`), then write a spec before coding.

## Priority order

1. Security 2. Correctness 3. Simplicity 4. Readability 5. Performance (optimize only when needed)

## Project description

A **template repo for Claude Code configuration**: rules, agents, hooks and skills for .NET/fullstack projects, copied as the starting point for new projects. On project start, fill in `.claude/docs/project-template.md`.

## Language

Conversation, commits and docs in **English**. Code, identifiers and comments in **English**.

## Tech stack

- **.NET** (Web API, Blazor, MVC, Razor Pages), latest stable
- **React** (first choice for new frontends), built to wwwroot for a single Docker image
- **SQLite** unless otherwise specified
- **WordPress** (PHP, themes, plugins)
- **HTML, CSS, JavaScript, jQuery** (legacy and simpler pages)

## CI/CD and deployment

Docker Swarm on Azure (live4.se). → `.claude/docs/deployment.md`

## Workflow

Trivial (one file, obvious) → do it. Medium (2–5 files) → brief plan, then do it. Complex → explore and plan first.
Explore → Plan → Implement → Verify (all tests) → Commit `<type>: <description>` (→ `.claude/docs/git.md`).

## Definition of "implemented"

Never say "implemented" or "done" until:

1. The spec's scenarios are in `specs/SCENARIOS.md` and `✓ validated` at runtime, with all four states proven: success, a specific visible **error**, empty, loading.
2. **Unit + integration** tests pass (`dotnet test`). **PBT** where the input is wide.
3. **E2E** passes (`dotnet test --filter "Category=UI"`).
4. UI: one functional test per function, a destructive suite per interactive function sized to its input domain, and visual-regression baselines.
5. **Mutation kill rate** on the changed critical modules meets the target (`dotnet stryker`, ~80%).
6. UI: `/tla` has run (full/light tracks).
7. Validated locally before any deploy: clean build, full suite green, runs in local dev AND `docker compose up`.
8. Web: visually verified in the browser.

If tests cannot be run, say so explicitly.

## Context management

- On compaction, keep the modified files, verbatim error messages, debugging steps and test commands.
- Use subagents for exploration. `/clear` between unrelated tasks. `/compact <focus>` for controlled compaction.
- After 2 failed fixes of the same problem: `/clear` and write a better prompt.

## Commands

```bash
dotnet build                           # Build the project
dotnet test                            # Run unit tests
dotnet run --project src/<ProjectName> # Run the application
dotnet test --filter "Category=UI"     # Playwright E2E tests
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"  # Single test
```

## Principles

**YAGNI** (three similar lines beat a premature abstraction) · **Fail fast** (clear errors, no silent fallbacks) · **DX** (names over comments).

## Reference files (read when needed, never @-import)

| Need | File |
|---|---|
| Project start, architecture | `.claude/docs/project-template.md` |
| Code style, naming, forbidden patterns | `.claude/docs/conventions.md` |
| Security | `.claude/docs/security.md` |
| Git | `.claude/docs/git.md` |
| Hooks, subagents, sessions | `.claude/docs/workflows.md` |
| Agents, skills | `.claude/docs/agents-templates.md`, `.claude/docs/skills.md` |
| Tests, destructive checklist | `.claude/docs/testing.md`, `.claude/docs/spec-testing-checklist.md` |
| Design references | `.claude/rules/design-references.md`, `.claude/docs/design-reference-library.md` |
| Deploy, stress tests | `.claude/docs/deployment.md`, `.claude/docs/stress-testing.md` |
| Local vs Claude cloud | `.claude/docs/workload-placement.md` |
| Template auto-sync | `.claude/docs/template-autosync.md` |
| Knowledge graph (opt-in) | `.claude/docs/graphify.md` |
| Why a rule says what it says | `.claude/docs/<rule>-rationale.md` |

Always-loaded context is capped at 40 KB (`bash scripts/context-budget.sh`). New explanation goes in a doc with a pointer, not in a rule.

## File organization

`scripts/` maintenance and hook scripts · `.claude/skills/` project skills (Agent Skills standard) · `.claude/agents/` subagents · `.claude/rules/` auto-loaded rules (path-scoped by frontmatter) · `.claude/docs/` on-demand reference · `CLAUDE.local.md` personal settings (gitignored).

## Iterative improvement

A repeated mistake → propose a rule or a hook. A review comment means missing context → update this file. Edit existing files rather than creating new ones. Keep this file focused.
