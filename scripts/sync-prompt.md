# Sync-prompt for other projects

Copy everything between the `---` markers below and paste it into a Claude Code session
in the project you want to update.

---

## Update project with the latest Claude Code configuration

The template repo is at `/Users/jool/repos/Claude`. Your job: sync THIS project's Claude Code setup against the template repo's latest version.

### Step 1: Read the template repo

Read the following files from `/Users/jool/repos/Claude` (all are important — do not skip any):

**Configuration:**
- `CLAUDE.md` — main configuration with critical rules and workflow
- `.claude/settings.json` — hooks, permissions, hook types (command, prompt, http, agent)

**Rules (auto-loaded, path-scoped via YAML frontmatter):**
- `.claude/rules/dotnet.md` — .NET code rules (paths: `**/*.cs`, `**/*.csproj`)
- `.claude/rules/frontend.md` — frontend rules
- `.claude/rules/security.md` — security rules for C#
- `.claude/rules/specs.md` — spec/task rules with destructive test requirements (paths: `**/spec*.md`, `**/tasks*.md`, etc.)
- `.claude/rules/wordpress.md` — WordPress rules

**Docs (loaded on demand, referenced from CLAUDE.md):**
- `.claude/docs/testing.md` — test conventions, destructive browser tests (6+1 attack categories)
- `.claude/docs/spec-testing-checklist.md` — mandatory checklist for destructive tests in specs
- `.claude/docs/conventions.md` — code style and naming
- `.claude/docs/security.md` — security reference
- `.claude/docs/git.md` — commit/branch/PR conventions
- `.claude/docs/workflows.md` — hooks (27 events), skills, subagents, plugins, agent teams
- `.claude/docs/skills.md` — SKILL.md format, frontmatter fields, recommended skills
- `.claude/docs/agents-templates.md` — copy-paste agent templates
- `.claude/docs/deployment.md` — Docker Swarm, CI/CD
- `.claude/docs/project-template.md` — template for project start

**Agents (subagents with YAML frontmatter):**
- `.claude/agents/dotnet-reviewer.md` — code review (isolation: worktree)
- `.claude/agents/security-scanner.md` — security scanning (isolation: worktree)
- `.claude/agents/test-runner.md` — test execution (background: true)
- `.claude/agents/db-agent.md` — EF Core/SQLite

**Skills (SKILL.md with frontmatter):**
- `.claude/skills/code-review/SKILL.md`
- `.claude/skills/explore-codebase/SKILL.md`
- `.claude/skills/deploy-checklist/SKILL.md`

### Step 2: Read this project's files

Read existing `CLAUDE.md`, `.claude/settings.json`, and all files under `.claude/` in THIS project. Note what is project-specific.

### Step 3: Language migration (CRITICAL)

The template has been migrated from Swedish to English. If THIS project still has Swedish content in its Claude Code configuration files:

1. **CLAUDE.md** — Translate all Swedish sections to English. Update the Language section to specify English.
2. **All .claude/docs/*.md** — Translate any Swedish content to English.
3. **All .claude/rules/*.md** — Translate any Swedish content to English.
4. **.claude/settings.json** — Change `"language": "swedish"` to `"language": "english"` (or remove the field entirely).
5. **Commit messages and PR descriptions** — Should now be written in English.

Preserve all project-specific technical content during translation — only the human language changes, not the meaning.

### Step 4: Analyze and update

For each file in the template:

| Situation | Action |
|-----------|--------|
| File does NOT exist in this project | Copy from template |
| File exists and matches template | Skip |
| File exists but is older | Update to template version, preserve `# PROJECT-SPECIFIC` blocks |
| File exists with project-specific content | Merge — template structure + project customizations |

**CLAUDE.md merge:**
- Update: critical rules, execution mode, workflow, verification, context management, reference files
- Preserve: project description, tech stack, commands, project-specific principles

**settings.json merge:**
- UNION of hooks — add template hooks without removing project's own
- UNION of permissions.deny — combine both lists
- Preserve project-specific hooks and permissions
- NOTE: the template uses hook types that may not exist in the project:
  - `type: "prompt"` — LLM evaluation (for spec validation)
  - `type: "agent"` — multi-turn verification with tool access
  - `type: "http"` — webhook integration
  - `if` field (v2.1.85) — filtering with permission rule syntax
  - `"defer"` permission decision (v2.1.89) — for headless sessions

### Step 5: Verify spec testing (CRITICAL)

These three components work together to ensure destructive browser tests are included at spec-writing time — not as an afterthought:

1. **`.claude/rules/specs.md`** — path-scoped rule triggered on spec/task/plan files. Requires testing.md and the checklist to be read BEFORE the spec is written.

2. **`.claude/docs/spec-testing-checklist.md`** — concrete template with task structure per attack category. Defines minimum requirements per feature type (8-15 tests). Target: 99% E2E coverage.

3. **PostToolUse prompt-hook in settings.json** — triggers on Edit/Write for spec files and blocks if destructive tests are missing. Verify this hook exists:
   ```json
   {
     "matcher": "Edit|Write",
     "hooks": [{
       "type": "prompt",
       "prompt": "A file was just written/edited. Check: if the file path contains spec, tasks, plan, or feature AND is a .md file AND involves UI features, verify it includes destructive browser test scenarios...",
       "statusMessage": "Validating spec completeness..."
     }]
   }
   ```

If ANY of these three are missing — copy from the template.

### Step 6: Install required skills

Install the following skill if it is not already present. This skill is critical for destructive browser testing:

```bash
# qa-test skill — destructive/adversarial browser testing with Playwright
if [ ! -d "$HOME/.claude/skills/qa-test" ]; then
  git clone https://github.com/adampaulwalker/qa-test.git "$HOME/.claude/skills/qa-test"
  echo "[INSTALLED] qa-test skill — destructive browser testing (Jinx persona)"
else
  echo "[SKIPPED] qa-test skill — already installed"
fi
```

This skill provides two personas:
- **Quinn** — systematic QA engineer for criteria-based testing
- **Jinx** — chaos tester that actively tries to break the application (input attacks, interaction attacks, navigation attacks, state attacks, visual/layout attacks)

Requires the Playwright MCP server. If the project has UI components, verify Playwright MCP is configured.

### Step 7: Remove irrelevant files

- Project does NOT use WordPress? → remove `.claude/rules/wordpress.md`
- Project does NOT use .NET? → remove `.claude/rules/dotnet.md`, `.claude/rules/security.md`, `.claude/agents/dotnet-reviewer.md`, `.claude/agents/db-agent.md`
- Project does NOT have UI? → remove `.claude/rules/specs.md`, `.claude/docs/spec-testing-checklist.md`, spec hook
- ALWAYS keep: `testing.md`, `conventions.md`, `workflows.md`, `skills.md`, `git.md`

### Step 8: Verify

After syncing:
- Run `dotnet build` if the project is .NET
- Verify that `settings.json` is valid JSON (`python3 -m json.tool .claude/settings.json`)
- Verify that CLAUDE.md does not exceed ~200 lines (Anthropic recommendation)
- Verify that the reference files section in CLAUDE.md points to files that actually exist

### Step 9: Report

Write a summary:

```
Synced from template repo (YYYY-MM-DD):
- [CREATED] filename — reason
- [UPDATED] filename — what changed
- [SKIPPED] filename — why (already current / not relevant)
- [REMOVED] filename — not relevant for project tech stack
- [TRANSLATED] filename — migrated from Swedish to English

Project-specific preserved:
- filename — what was preserved

Manual review recommended:
- filename — why
```

### Rules

- Communicate in English
- Code is written in English
- NEVER change the project's core logic or application code
- ALWAYS preserve project-specific customizations (marked with `# PROJECT-SPECIFIC` or clearly unique to the project)
- If unsure: report and ask instead of changing
- Do NOT commit automatically — let the developer review first

Then check that `CLAUDE.md` does not exceed 200 lines; if it does, split out sections and place them into separate file(s).


---
