# CLAUDE.md

## Critical rules (READ FIRST)

- **ALWAYS** read the code first — base ALL conclusions on evidence from the codebase, not assumptions.
- **ALWAYS** verify with `dotnet build` and `dotnet test` before claiming anything is "done".
- **ALWAYS** use the Edit tool for surgical changes — never copy entire files.
- **ALWAYS** invoke the `frontend-design` skill via the Skill tool BEFORE writing UI code (HTML, CSS, JS, design, layout, appearance). This is a **BLOCKING REQUIREMENT**.
- **ALWAYS** run generated text through the `humanizer` skill via the Skill tool BEFORE delivering to humans (documentation, commit messages, PR descriptions, emails, README). This is a **BLOCKING REQUIREMENT**.
- **ALWAYS** follow existing patterns in the codebase — look at similar components first.
- **ALWAYS** end every spec/feature involving UI with **destructive browser tests** (Playwright). Target is **99% E2E coverage**. Tests that only verify happy path are NOT enough. BEFORE writing a spec/task file: read `.claude/docs/spec-testing-checklist.md` and include destructive tests as a dedicated phase.

## Execution mode

### Autonomous mode (NON-INTERACTIVE)

- Act immediately without waiting for confirmation.
- Missing information is not a blocker — make reasonable assumptions and continue.
- Errors should be handled and fixed independently.
- Questions are allowed ONLY for architecture decisions or requirement interpretations that cannot reasonably be assumed.
- **Max 3 attempts per problem** — if the same approach fails 3 times, run `/clear` and try a completely different strategy with a better prompt.

### Anti-stall rule

If no clear task is found — pick the most likely task and act. Stagnation is treated as failure.

### Interview pattern

For larger features: interview the developer with `AskUserQuestion` before implementation. Ask about technical implementation, edge cases, and tradeoffs. Then write a spec before coding begins.

## Priority order

1. **Security** — never compromise
2. **Correctness** — the code must do the right thing
3. **Simplicity** — minimum necessary complexity
4. **Readability** — clear code over clever code
5. **Performance** — optimize only when needed

## Project description

This is a **template repo for Claude Code configuration** — a reusable set of rules, agents, hooks, and skills for .NET/fullstack projects. The repo is copied as a starting point for new projects.

> **On project start:** Fill in core principles, architecture, and dev environment in `.claude/docs/project-template.md`

## Language

- Communicate in **English** in conversations, commit messages, and documentation.
- Code, variable names, and technical terms are written in **English**.
- Comments in code are written in **English**.

## Tech stack

- **.NET** (Web API, Blazor, MVC, Razor Pages) — latest stable version
- **React** (first choice for frontend in new projects) — built to wwwroot in the .NET project for a single Docker image
- **SQLite** as database (unless otherwise specified)
- **WordPress** (PHP, themes, plugins)
- **HTML, CSS, JavaScript, jQuery** (legacy projects / simpler pages)

## CI/CD and deployment

Docker Swarm cluster on Azure (live4.se). For IP addresses, pipeline, commands, and checklist, see `.claude/docs/deployment.md`

## Workflow

### Complexity assessment

- **Trivial** (one file, obvious fix) → execute immediately
- **Medium** (2-5 files, clear scope) → brief planning, then execute
- **Complex** (architecture impact, unclear requirements) → full exploration and plan first

### Plan → Implement → Verify

1. **Explore** — read existing code, understand patterns and dependencies.
2. **Plan** — for medium/complex: use Plan Mode (Shift+Tab) to write a plan before implementation.
3. **Implement** — switch to Normal Mode, write code according to the plan. Follow existing patterns.
4. **Verify** — run all tests, typecheck, confirm everything works.
5. **Commit** — commit in English: `<type>: <description>` (feat/fix/refactor/test/docs/style/chore). Details in `.claude/docs/git.md`

## Verification and grounding

> Giving Claude ways to verify its own work is the single most important measure for quality. — Anthropic Best Practices

- **IMPORTANT:** ALWAYS read relevant files BEFORE answering about the codebase. NEVER guess.
- Run tests after every implementation.
- Run individual tests over the full suite for faster feedback.

### Definition of "implemented"

NEVER say something is "implemented" or "done" until:

1. All **unit tests** pass (`dotnet test`).
2. All **E2E tests in Playwright** pass (`dotnet test --filter "Category=UI"`).
3. For UI features: **destructive browser tests** have been written and pass. Target is **99% E2E coverage** — every spec should cover all relevant attack categories (see `.claude/docs/spec-testing-checklist.md` and `.claude/docs/testing.md`).
4. For web projects: **visually verified** in the browser.
5. The code is assessed as **100% functional**.

If tests cannot be run (missing infrastructure), clearly inform about this.

## Context management

- During compaction: ALWAYS preserve modified files, error messages verbatim, debugging steps, and test commands. Compaction instruction: `"When compacting, always preserve the full list of modified files and any test commands"`.
- Use subagents for exploration and research — keep the main context clean.
- Use `/clear` between unrelated tasks — never mix unrelated tasks in the same session.
- Use `/compact <focus>` for controlled compaction, e.g., `/compact Focus on the API changes`.
- Break down large tasks into discrete subtasks — never request 5+ features in one step.
- After 2 failed fixes of the same problem: `/clear` and write a better prompt from scratch.

## Commands

```bash
dotnet build                           # Build the project
dotnet test                            # Run unit tests
dotnet run --project src/<ProjectName> # Run the application
dotnet test --filter "Category=UI"     # Playwright E2E tests
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"  # Single test
```

## Principles

- **YAGNI** — only build what is needed now. Three similar lines > premature abstraction.
- **Fail fast** — clear error messages with context. Never silent fallbacks.
- **DX** — code should be readable without comments. Good naming is usually enough.

## Reference files (loaded on demand)

Read these files WHEN you need them — do not load everything upfront:

- **New project start** or architecture questions → `.claude/docs/project-template.md`
- **Code style, naming, forbidden patterns** → `.claude/docs/conventions.md`
- **Security questions** (SQL injection, XSS, secrets) → `.claude/docs/security.md`
- **Git commit/branch/PR** → `.claude/docs/git.md`
- **Hooks, subagents, plugins, sessions** → `.claude/docs/workflows.md`
- **Creating new agents** → `.claude/docs/agents-templates.md`
- **Skills, SKILL.md format, Agent Skills standard** → `.claude/docs/skills.md`
- **Tests (xUnit, Playwright)** → `.claude/docs/testing.md`
- **Spec testing checklist (destructive tests)** → `.claude/docs/spec-testing-checklist.md`
- **Deploy, Docker, CI/CD** → `.claude/docs/deployment.md`

## File organization

- **`scripts/`** — Maintenance scripts (`update-template.sh` to keep the template repo updated, `sync-prompt.md` with prompt for syncing other projects).
- **`.claude/skills/`** — Project skills with SKILL.md (code-review, explore-codebase, deploy-checklist, update-template). Follows the Agent Skills standard (agentskills.io).
- **`.claude/agents/`** — Subagents (dotnet-reviewer, security-scanner, test-runner, db-agent). Supports `isolation: worktree`, `background`, `hooks` in frontmatter.
- **`.claude/rules/`** — Rules auto-loaded every session. Supports path-scoping with YAML frontmatter.
- **`.claude/docs/`** — Reference material loaded on demand. Reference WITHOUT `@` prefix to avoid auto-expansion.
- **`CLAUDE.local.md`** — Personal project settings not committed (auto-gitignored).

## Iterative improvement

- If the same mistake repeats: suggest a new rule for CLAUDE.md or a hook that prevents it.
- Every code review comment is a signal that the agent lacked context — update CLAUDE.md.
- Edit existing files over creating new ones.
- Keep this file focused — if an instruction can be removed without Claude making errors, remove it.
