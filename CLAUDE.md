# CLAUDE.md

## Critical rules (READ FIRST)

Rules tagged **(BLOCKING)** are enforced — by hooks (some are hard PreToolUse denies, some are advisory reminders or interviews you MUST act on) and by the Definition of Done. They are requirements, not suggestions. The rest are strong defaults. (Markers are scarce on purpose: when everything is "ALWAYS", nothing is.)

- Read the code first — base conclusions on evidence, never assumptions. Read relevant files BEFORE answering about the codebase; never guess.
- Use the Edit tool for surgical changes — never copy whole files.
- Verify with `dotnet build` + `dotnet test` before claiming anything is "done".
- Follow existing patterns — look at similar components first.
- **(BLOCKING)** Non-trivial feature/refactor/fix → run the full pipeline as **one task** (`specify → clarify → elicit → plan → tasks → analyze → implement → tests → tla`); no permission stops between phases. `clarify` runs on all tracks (auto-pick); `elicit` on full/light only. Trivial-fix bypass needs an explicit one-sentence classification. See `.claude/rules/feature-pipeline.md`.
- **(BLOCKING)** Before feature work, consult the spec register `specs/INDEX.md`; work the next unchecked spec end-to-end (pipeline → commit → push → tick), then stop with the status summary. See `.claude/rules/spec-register.md`.
- **(BLOCKING)** Hardening — a spec that crosses a risk threshold (auth / payments / PII / upload / new external surface, full-track state machine, new entity or ≥6 files, or tagged `[hardened]`) runs the **hardened tier**: the full pipeline **plus** threat-model pass, expanded destructive + stress, a hard mutation-kill gate, and an adversarial review. Every 5 completed specs, work an **integration-hardening checkpoint** (register row: full-system regression + security sweep). Full-track and hardened specs **start in a fresh session** — when the SessionStart banner says so, run `/clear` first (a hook cannot clear context for you). See `.claude/rules/spec-hardening.md`.
- **(BLOCKING)** Keep the scenario map `specs/SCENARIOS.md` current — a diagram-led, surveyable exploded view (Mermaid use-case diagram + per-feature user-flow flowchart + SC-id ledger; journey/wireflow/storyboard on-demand). A gap or drift → **start a scenario interview**, never invent the missing cases silently. See `.claude/rules/scenarios.md`.
- **(BLOCKING)** Invoke the `frontend-design` skill BEFORE writing any UI code (HTML/CSS/JS, React Native / Flutter widgets).
- **(BLOCKING)** Run generated human-facing text through the `humanizer` skill before delivering (docs, commits, PRs, email, README).
- **(BLOCKING)** Testing — every behaviour-changing feature gets **unit + integration + E2E** (integration is where AI code most often breaks), **PBT** for wide-input logic, **visual-regression** baselines for UI, and a functional test for **every** implemented function. The destructive suite is **sized per interactive function from its input domain** (toggle ~3 → multi-step/auth ~20-30+), NOT a flat quota. The **mutation kill rate** (Stryker, nightly/on-demand, ~80% on critical modules) is the gate — test count is not. See `.claude/docs/testing.md` + `.claude/rules/scenarios.md`.

## Execution mode

### Autonomous mode (NON-INTERACTIVE)

- Act immediately without waiting for confirmation.
- Missing information is not a blocker — make reasonable assumptions and continue.
- Errors should be handled and fixed independently.
- Questions are allowed ONLY for architecture decisions or requirement interpretations that cannot reasonably be assumed.
- **Max 3 attempts per problem** — if the same approach fails 3 times, run `/clear` and try a completely different strategy with a better prompt.

### Anti-stall rule

If no clear task is found — pick the most likely task and act. Stagnation is treated as failure.

### Hook recovery rule

When a hook stops continuation or provides feedback: acknowledge the feedback, handle it (fix the issue OR explain why it's not applicable), and **continue working autonomously**. Never stop and wait silently after hook feedback — that is treated as stalling.

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

1. This spec's scenarios are in `specs/SCENARIOS.md` AND marked `✓ validated` — each one observed *actually working at runtime* (real behaviour, not a stub), with all four states proven: success, a specific visible **error** message (never silent — a failed login must say why), empty, loading. Validate prerequisite scenarios first; a broken prerequisite is a hard stop. See `.claude/rules/scenarios.md`.
2. **Unit + integration tests** pass (`dotnet test`) — both layers, not just one. Integration is where AI code most often fails (units pass, the seams don't). **PBT** added for wide-input logic.
3. **E2E tests** pass (`dotnet test --filter "Category=UI"`).
4. For UI features: **functional coverage** for EVERY implemented function (1 test each), PLUS a **destructive suite per interactive function sized to its input domain** (toggle ~3 → multi-step/auth ~20-30+, not a flat quota), PLUS **visual-regression** baselines for the key states.
5. **Mutation kill rate** on the changed critical module(s) meets target (`dotnet stryker`, ~80%, nightly/on-demand — NOT per-push CI). This is the gate that proves the tests bite; a green suite that kills no mutants is not done.
6. For UI features: **TLA+** has been run (`/tla`) — race conditions, state-machine gaps, missing invariants (full/light tracks; auto-triggered after tests).
7. **Validated locally before any deploy** — `dotnet build` clean, full suite green, and the app runs in local dev AND in `docker compose up` (the artifact you ship is the container, so prove the container works).
8. For web: **visually verified** in the browser. The code is assessed as **fully functional**.

If tests cannot be run (missing infrastructure), say so explicitly.

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
- **Tests (layers, risk-tiered destructive, PBT, VRT, mutation gate)** → `.claude/docs/testing.md`
- **Spec testing checklist (destructive tests)** → `.claude/docs/spec-testing-checklist.md`
- **Scenario map (`SCENARIOS.md`, gap/drift → interview)** → `.claude/rules/scenarios.md`
- **Design references (decompile "feeling of Spotify" → primitives)** → `.claude/rules/design-references.md` + `.claude/docs/design-reference-library.md`
- **Feature pipeline (auto-trigger, end-to-end execution)** → `.claude/rules/feature-pipeline.md`
- **Spec register (one stop per spec, project-level rail)** → `.claude/rules/spec-register.md`
- **Spec hardening (risk tier above full, integration checkpoints, /clear for big specs)** → `.claude/rules/spec-hardening.md`
- **Deploy, Docker, CI/CD** → `.claude/docs/deployment.md`
- **Stress testing (pre-deploy)** → `.claude/docs/stress-testing.md`
- **Codebase knowledge graph (opt-in per project)** → `.claude/docs/graphify.md`

## File organization

- **`scripts/`** — Maintenance scripts (`update-template.sh` to keep the template repo updated, `sync-prompt.md` with prompt for syncing other projects).
- **`.claude/skills/`** — Project skills with SKILL.md (allium, code-review, deploy-checklist, explore-codebase, sync-template, tla, update-template). Follows the Agent Skills standard (agentskills.io).
- **`.claude/agents/`** — Subagents (dotnet-reviewer, security-scanner, test-runner, db-agent). Supports `isolation: worktree`, `background`, `hooks` in frontmatter.
- **`.claude/rules/`** — Rules auto-loaded every session. Supports path-scoping with YAML frontmatter.
- **`.claude/docs/`** — Reference material loaded on demand. Reference WITHOUT `@` prefix to avoid auto-expansion.
- **`CLAUDE.local.md`** — Personal project settings not committed (auto-gitignored).

## Iterative improvement

- If the same mistake repeats: suggest a new rule for CLAUDE.md or a hook that prevents it.
- Every code review comment is a signal that the agent lacked context — update CLAUDE.md.
- Edit existing files over creating new ones.
- Keep this file focused — if an instruction can be removed without Claude making errors, remove it.
