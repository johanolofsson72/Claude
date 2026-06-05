# Claude Code configuration template

A drop-in Claude Code setup for .NET/fullstack projects. Copy it into a repo and Claude gets rules it can't ignore, a spec pipeline it must follow, subagents for review and testing, and around 70 hook scripts that enforce all of it deterministically.

This is not an application. It's the configuration layer that sits next to one.

## Why this exists

CLAUDE.md files are advisory. Claude reads them, agrees enthusiastically, and then forgets half of it forty turns later. Hooks don't forget. The core idea of this template: every requirement that matters gets a hook that fires regardless of conversation state, and CLAUDE.md is reserved for context the hooks can't express.

The second idea is spec-driven development as a hard rail. Non-trivial work goes through a fixed pipeline (specify, clarify, formal spec, plan, tasks, analyze, implement, browser tests, TLA+ verification), and a PreToolUse hook blocks source-code edits until the pipeline artifacts exist. Claude can't skip to the fun part.

## What's inside

```
CLAUDE.md              Main instructions, ~155 lines, loaded every session
CLAUDE-HOWTO.md        Install guide (macOS, Linux, Windows Git Bash/WSL)
.claude/
├── settings.json      Hook wiring
├── rules/             15 rules, auto-loaded, path-scoped by file type
├── agents/            4 subagents: dotnet-reviewer, security-scanner,
│                      test-runner, db-agent
├── skills/            9 skills: project-wizard, sync-template, allium,
│                      tla, code-review, explore-codebase, deploy-checklist,
│                      ui-ux-pro-max, update-template
└── docs/              14 reference docs, loaded on demand
scripts/               ~70 hook scripts and sync tooling
```

### The pipeline

```
/specify → /clarify → /allium:elicit → /plan → /tasks → /speckit.analyze → /implement
                                                                              │
                                                              browser tests (functional + destructive)
                                                                              │
                                                                    /tla (formal verification)
```

Three enforcement layers back this up:

1. **Rules** in `.claude/rules/` load every session and define the contract.
2. **Reminder hooks** re-inject the contract when prompts contain feature-build trigger words, so long sessions don't drift.
3. **Guard hooks** hard-block `Edit`/`Write` on source files when required spec artifacts are missing. This is the layer that actually works at 2am.

### Spec register

Each project keeps a numbered spec register at `specs/INDEX.md`. Claude works the next unchecked spec end-to-end, commits, pushes, ticks the register, and stops with a status summary. One stop per spec, no permission-asking between phases. A SessionStart hook orients every new session on where the register stands.

### Formal verification

Two skills push specs beyond prose:

- **allium** elicits a formal spec from markdown requirements, then later distills one from the implementation to detect drift between what was specified and what got built.
- **tla** extracts invariants and state machines from the spec, runs TLC, and surfaces race conditions and liveness gaps before they ship.

Findings from either are surfaced one by one for explicit decisions. No "looks good overall" summaries that bury problems.

### Local-LLM hooks

About 45 of the hook scripts delegate small jobs (commit drafts, README skeletons, test-name checks, secret scans, stacktrace triage) to a local LLM instead of burning Claude tokens. They're opt-in per project; only the token-saver subset is wired by default. `scripts/local-llm-stats.sh` reports what they saved.

### Testing policy

The template enforces full functional coverage in browser tests: one Playwright test per implemented function, minimum, plus 8+ destructive tests across six attack categories. Testing 3 of 12 functions was the most common failure mode before this rule existed. Now a hook counts.

### CI minimalism

Solo projects get at most one GitHub Actions workflow: a `workflow_dispatch` deploy with a confirmation input. Everything else (security scans, mutation testing, a11y audits) runs locally before deploy. This rule exists because one project burned a month's 3000-minute Actions budget in four days on checks that already ran locally.

## Getting started

Full instructions live in [CLAUDE-HOWTO.md](CLAUDE-HOWTO.md). The short version:

**New project:** run the `project-wizard` skill from a Claude Code session. It interviews you (50 questions, 9 categories), then generates CLAUDE.md, a speckit constitution, a design system, and the project brief, and syncs the full template config.

**Existing project:** run the `sync-template` skill, or copy manually:

```bash
TEMPLATE="$HOME/repos/Claude"
mkdir -p .claude
cp "$TEMPLATE/CLAUDE.md" .
cp "$TEMPLATE/.claude/settings.json" .claude/
cp -r "$TEMPLATE/.claude/rules" "$TEMPLATE/.claude/agents" "$TEMPLATE/.claude/docs" .claude/
```

Then fill in the project description in `CLAUDE.md`, complete `.claude/docs/project-template.md`, and delete the rules and agents that don't apply (WordPress rules in a pure .NET repo just take up space).

Works on macOS, Linux (apt/dnf/pacman/zypper), and Windows via Git Bash or WSL2. Prerequisites and per-platform install commands are in the HOWTO.

## Keeping it current

The `update-template` skill searches for the latest Claude Code changelog and best practices, then updates the template's structure to match. `scripts/update-template.sh` and `scripts/sync-prompt.md` push those updates out to projects already using the config.

## Tech stack assumptions

Built for .NET (Web API, Blazor, MVC) with React frontends, SQLite, Playwright for E2E, and Docker Swarm deploys. Most of the rules and agents are stack-specific on purpose. If your stack differs, the structure still applies; swap the contents.
