# Sync-prompt for other projects

Copy everything between the `---` markers below and paste it into a Claude Code session
in the project you want to update.

---

## Update project with the latest Claude Code configuration

The template repo is at `/Users/jool/repos/Claude`. Your job: sync THIS project's Claude Code setup against the template repo's latest version.

### Step 0: Version check (MANDATORY — saves tokens)

Before reading anything, check if this project is already up to date.

```bash
TEMPLATE_SHA=$(curl -sL https://api.github.com/repos/johanolofsson72/Claude/commits/main | jq -r '.sha // empty')
LAST_SHA=$(cat .claude/.sync-version 2>/dev/null)

if [ -z "$TEMPLATE_SHA" ]; then
  echo "[WARN] Could not fetch template SHA — falling back to full sync"
elif [ "$TEMPLATE_SHA" = "$LAST_SHA" ]; then
  echo "[UP TO DATE] Already synced with template @ $TEMPLATE_SHA"
  # Nothing changed since last sync — skip Steps 1-8, but STILL run Step 9 (CLAUDE.md slim check).
  # (If the user says "force resync" or "full resync", ignore this and continue with a full sync.)
elif [ -n "$LAST_SHA" ]; then
  echo "[INCREMENTAL SYNC] $LAST_SHA → $TEMPLATE_SHA"
  CHANGED=$(curl -sL "https://api.github.com/repos/johanolofsson72/Claude/compare/${LAST_SHA}...${TEMPLATE_SHA}" | jq -r '.files[]?.filename // empty')
  echo "Changed files since last sync:"
  echo "$CHANGED"
else
  echo "[FIRST SYNC] No .sync-version found — performing full sync"
fi
```

**Decision logic:**

- **SHAs equal** → project is up to date. Report "already current", skip Steps 1-8, then **jump to Step 9** (CLAUDE.md slim check always runs). Do NOT read template files.
- **LAST_SHA exists, SHAs differ** → **incremental mode**. Read ONLY files in `$CHANGED`, skip steps that involve files not in that list. Still run Step 7 (tech stack confirmation), Step 8 (verify), and Step 9 (slim check) unconditionally.
- **No LAST_SHA** → **full sync**. Read all template files per Step 1 below.
- **Force override** → if the user prompt contains "force", "full resync", or "--force", ignore `.sync-version` and do a full sync regardless.

**CRITICAL:** Only read files from the template that you actually need. In incremental mode, skipping 28 unchanged files saves ~80-90% of the tokens.

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
- `.claude/rules/tests.md` — browser test rules requiring functional coverage inventory (paths: `**/*Test*.cs`, `**/*test*.ts`, etc.)
- `.claude/rules/wordpress.md` — WordPress rules
- `.claude/rules/allium.md` — Allium spec language rules (paths: `**/*.allium`)

**Docs (loaded on demand, referenced from CLAUDE.md):**
- `.claude/docs/testing.md` — test conventions, functional coverage + destructive browser tests (6+1 attack categories)
- `.claude/docs/spec-testing-checklist.md` — mandatory checklist: functional coverage inventory + destructive tests in specs
- `.claude/docs/conventions.md` — code style and naming
- `.claude/docs/security.md` — security reference
- `.claude/docs/git.md` — commit/branch/PR conventions
- `.claude/docs/workflows.md` — hooks (27 events), skills, subagents, plugins, agent teams
- `.claude/docs/skills.md` — SKILL.md format, frontmatter fields, recommended skills
- `.claude/docs/agents-templates.md` — copy-paste agent templates
- `.claude/docs/deployment.md` — Docker Swarm, CI/CD
- `.claude/docs/stress-testing.md` — mandatory pre-deploy stress testing (k6, Lighthouse)
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
- `.claude/skills/tla/SKILL.md` — TLA+ formal verification (auto-triggered after browser tests)
- `.claude/skills/allium/SKILL.md` — Allium spec language skill (/allium:elicit, /allium:distill)

**Scripts:**

- `scripts/tla-hook.sh` — PostToolUse hook script for TLA+ auto-trigger
- `scripts/allium-hook.sh` — PostToolUse hook that blocks if spec lacks .allium companion
- `scripts/tlc-cleanup.sh` — TLC process cleanup (kills orphaned Java/TLC processes after execution)
- `scripts/test-coverage-hook.sh` — Deterministic functional test coverage enforcement (blocks if tests < inventory items)

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

### Step 5b: Verify Allium + TLA+ verification pipeline

The template includes a full spec-to-verification pipeline:

```text
Spec (markdown) → /allium:elicit → .allium → Implementation →
Browser tests (destructive) → /tla (distill + drift + invariants) → Done
```

**Files to sync:**

1. **`.claude/skills/tla/SKILL.md`** — formal verification skill with Allium drift detection
2. **`.claude/rules/allium.md`** — prescriptive Allium rules (triggers on spec AND .allium files)
3. **`.claude/rules/specs.md`** — updated with Allium pre-implementation + TLA+ post-implementation steps
4. **`scripts/tla-hook.sh`** — PostToolUse hook that detects browser/E2E test files
5. **PostToolUse hook in settings.json** — triggers `scripts/tla-hook.sh` on Edit/Write of test files
6. **UserPromptSubmit hook in settings.json** — updated to include Allium + TLA+ instructions on speckit keywords

If any are missing — copy from template.

**Optional: Install Allium CLI** for automatic `.allium` file validation:

```bash
# Homebrew
brew tap juxt/allium && brew install allium
# Or Cargo
cargo install allium-cli
```

### Step 6: Install required skills

Install the following external skills to `~/.claude/skills/` if not already present. These are shared across all projects.

```bash
# anthropics/skills — Official Anthropic collection (includes frontend-design, PDF, PPTX, XLSX)
# CRITICAL: frontend-design is a BLOCKING REQUIREMENT in CLAUDE.md
if [ ! -d "$HOME/.claude/skills/anthropics-skills" ]; then
  git clone https://github.com/anthropics/skills.git "$HOME/.claude/skills/anthropics-skills"
  echo "[INSTALLED] anthropics/skills — official collection (frontend-design, PDF, PPTX, XLSX)"
else
  echo "[SKIPPED] anthropics/skills — already installed"
fi

# obra/superpowers — Planning, TDD, code review
if [ ! -d "$HOME/.claude/skills/superpowers" ]; then
  git clone https://github.com/obra/superpowers.git "$HOME/.claude/skills/superpowers"
  echo "[INSTALLED] obra/superpowers — planning, TDD, code review"
else
  echo "[SKIPPED] obra/superpowers — already installed"
fi

# trailofbits/skills — Security research skills from Trail of Bits
if [ ! -d "$HOME/.claude/skills/trailofbits-skills" ]; then
  git clone https://github.com/trailofbits/skills.git "$HOME/.claude/skills/trailofbits-skills"
  echo "[INSTALLED] trailofbits/skills — security research"
else
  echo "[SKIPPED] trailofbits/skills — already installed"
fi

# adampaulwalker/qa-test — Destructive/adversarial browser testing with Playwright
if [ ! -d "$HOME/.claude/skills/qa-test" ]; then
  git clone https://github.com/adampaulwalker/qa-test.git "$HOME/.claude/skills/qa-test"
  echo "[INSTALLED] qa-test — destructive browser testing (Jinx persona)"
else
  echo "[SKIPPED] qa-test — already installed"
fi

# dotnet/skills — Official Microsoft .NET skills (ASP.NET Core, EF Core, Blazor)
if [ ! -d "$HOME/.claude/skills/dotnet-skills" ]; then
  git clone https://github.com/dotnet/skills.git "$HOME/.claude/skills/dotnet-skills"
  echo "[INSTALLED] dotnet/skills — official .NET patterns and best practices"
else
  echo "[SKIPPED] dotnet/skills — already installed"
fi

# vercel-labs/skills — React performance rules and web design guidelines
if [ ! -d "$HOME/.claude/skills/vercel-skills" ]; then
  git clone https://github.com/vercel-labs/skills.git "$HOME/.claude/skills/vercel-skills"
  echo "[INSTALLED] vercel-labs/skills — React performance (45 rules), web design"
else
  echo "[SKIPPED] vercel-labs/skills — already installed"
fi

# lackeyjb/playwright-skill — Deep Playwright knowledge (POM, patterns, CI/CD)
if [ ! -d "$HOME/.claude/skills/playwright-skill" ]; then
  git clone https://github.com/lackeyjb/playwright-skill.git "$HOME/.claude/skills/playwright-skill"
  echo "[INSTALLED] playwright-skill — Playwright patterns, POM, test generation"
else
  echo "[SKIPPED] playwright-skill — already installed"
fi
```

**npm-based skills (installed via CLI):**

```bash
# ui-ux-pro-max — Design intelligence (67 styles, 96 palettes, 57 font pairings, 25 charts, 13 stacks)
if ! uipro --version &>/dev/null 2>&1; then
  npm install -g uipro-cli
  echo "[INSTALLED] uipro-cli — UI/UX Pro Max CLI"
else
  echo "[SKIPPED] uipro-cli — already installed"
fi

# Initialize in the project if not already present
if [ ! -d ".claude/skills/ui-ux-pro-max" ]; then
  uipro init --ai claude
  echo "[INSTALLED] ui-ux-pro-max skill — design intelligence for Claude Code"
else
  echo "[SKIPPED] ui-ux-pro-max — already initialized in project"
fi
```

**What each skill provides:**

| Skill | Source | Key capabilities |
|---|---|---|
| **anthropics/skills** | Anthropic (official) | `frontend-design` (blocking requirement), PDF/PPTX/XLSX generation |
| **superpowers** | obra | TDD workflow, implementation planning, thorough code review |
| **trailofbits/skills** | Trail of Bits | OWASP security analysis, vulnerability research, secure code patterns |
| **qa-test** | Community | Destructive browser testing — Quinn (systematic QA) + Jinx (chaos tester) |
| **dotnet/skills** | Microsoft (official) | ASP.NET Core, EF Core, Blazor patterns, project scaffolding |
| **vercel-labs/skills** | Vercel (official) | React performance rules (45 rules ranked by impact), web design |
| **playwright-skill** | Community (2k+ stars) | Deep Playwright knowledge, Page Object Model, CI/CD patterns |
| **ui-ux-pro-max** | Community (npm: uipro-cli) | 67 UI styles, 96 palettes, 57 font pairings, 25 chart types, 13 stacks |

The qa-test and playwright-skill require the Playwright MCP server. If the project has UI components, verify Playwright MCP is configured.

### Step 6b: Install TLC model checker (required for /tla)

The TLA+ skill auto-installs TLC if missing, but verify it's available on the machine:

```bash
# Check if TLC is already available
if command -v tlc &>/dev/null; then
  echo "[SKIPPED] TLC model checker — already installed ($(which tlc))"
elif command -v brew &>/dev/null; then
  echo "[INSTALLING] TLC model checker via Homebrew..."
  brew install --quiet tlaplus
  echo "[INSTALLED] TLC model checker (tlaplus)"
else
  echo "[INSTALLING] TLC model checker via JAR download..."
  curl -fsSL -o /usr/local/lib/tla2tools.jar https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
  echo "[INSTALLED] TLC model checker (JAR at /usr/local/lib/tla2tools.jar)"
fi
```

Without TLC, the /tla skill falls back to reasoning-based verification (LLM-only, no mathematical proof). With TLC, it runs actual model checking.

### Step 7: Ask about tech stack, then remove irrelevant files

**IMPORTANT: Do NOT guess the tech stack from files alone.** A new project may not have any source files yet. ALWAYS ask the developer before removing anything.

Use `AskUserQuestion` to confirm:

> Which of the following does this project use (or will use)?
>
> - .NET (C#, ASP.NET Core, Blazor, EF Core)
> - WordPress (PHP, themes, plugins)
> - React / frontend with UI
> - SQLite / database
>
> List all that apply, or say "all" to keep everything.

Then, based on the developer's answer:

- Developer says NO to WordPress → remove `.claude/rules/wordpress.md`
- Developer says NO to .NET → remove `.claude/rules/dotnet.md`, `.claude/rules/security.md`, `.claude/agents/dotnet-reviewer.md`, `.claude/agents/db-agent.md`
- Developer says NO to UI → remove `.claude/rules/specs.md`, `.claude/docs/spec-testing-checklist.md`, `.claude/skills/tla/SKILL.md`, `.claude/rules/allium.md`, `scripts/tla-hook.sh`, spec hook, TLA+ hook
- ALWAYS keep regardless of answer: `testing.md`, `conventions.md`, `workflows.md`, `skills.md`, `git.md`
- When in doubt, **keep the file** — extra rules cost nothing, missing rules cost bugs

### Step 8: Verify

After syncing:
- Run `dotnet build` if the project is .NET
- Verify that `settings.json` is valid JSON (`python3 -m json.tool .claude/settings.json`)
- Verify that the reference files section in CLAUDE.md points to files that actually exist

### Step 8b: Record sync version (MANDATORY)

Write the template SHA fetched in Step 0 to `.claude/.sync-version`, ensure it's not gitignored, and stage it so the developer's next commit includes it. Without this, team members re-sync from scratch on every fresh clone.

```bash
mkdir -p .claude
echo "$TEMPLATE_SHA" > .claude/.sync-version
echo "[VERSIONED] Recorded template SHA: $TEMPLATE_SHA"

# Ensure .claude/.sync-version is NOT gitignored. Strip any matching patterns.
if [ -f .gitignore ]; then
  # Match exact paths and common accidental catches
  for PATTERN in '.claude/.sync-version' '.sync-version' '.claude/\.sync-version'; do
    if grep -qxF "$PATTERN" .gitignore 2>/dev/null; then
      grep -vxF "$PATTERN" .gitignore > .gitignore.tmp && mv .gitignore.tmp .gitignore
      echo "[UNIGNORED] Removed '$PATTERN' from .gitignore"
    fi
  done
  # Warn if .claude/ itself is ignored — that's a bigger problem the developer must resolve
  if git check-ignore -q .claude/.sync-version 2>/dev/null; then
    echo "[WARN] .claude/.sync-version is still ignored (likely via '.claude/' rule). Add '!.claude/.sync-version' as a negation to .gitignore, OR commit the file with 'git add -f'."
  fi
fi

# Stage the sync-version file so the developer's review commit includes it
git add -f .claude/.sync-version 2>/dev/null && echo "[STAGED] .claude/.sync-version ready to commit"
```

**Why this matters:** `.sync-version` is per-project cache state. If it's gitignored or left unstaged, a teammate who clones the repo fresh has no record of the last sync SHA, and their next `/project-update` will do a full 100% sync instead of the incremental path. Committing it is the only way the cache survives across machines.

### Step 9: Slim CLAUDE.md (ALWAYS RUNS — regardless of sync mode)

**This step runs unconditionally — even when Step 0 reports "[UP TO DATE]" and even when the user forces a full resync.** The goal is to keep `CLAUDE.md` as lean as possible on every run, since drift accumulates over time.

```bash
LINES=$(wc -l < CLAUDE.md | tr -d ' ')
echo "[SLIM CHECK] CLAUDE.md is $LINES lines (Anthropic recommends <= 200)"
```

If `CLAUDE.md` exceeds **200 lines**:

1. Identify the sections that can be moved out without losing critical in-session context. Good candidates:
   - Detailed conventions → `.claude/docs/conventions.md`
   - Security rules → `.claude/docs/security.md`
   - Git workflows → `.claude/docs/git.md`
   - Testing details → `.claude/docs/testing.md`
   - Deployment / CI/CD → `.claude/docs/deployment.md`
   - Project-specific long sections → a new file under `.claude/docs/`
2. Replace the moved section in `CLAUDE.md` with a one-line pointer in the "Reference files (loaded on demand)" section (no `@`-prefix — those auto-expand and defeat the purpose).
3. Verify `CLAUDE.md` is now ≤ 200 lines with `wc -l`.
4. Report what was moved where in the Step 10 summary.

**Keep in `CLAUDE.md` regardless of length:** Critical rules, execution mode, priority order, workflow overview, and the reference-files pointer section. These must stay in-session because they govern every action.

If `CLAUDE.md` is already ≤ 200 lines, report `[SLIM CHECK] OK` and move on.

### Step 10: Report

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
- **Step 9 (slim CLAUDE.md check) runs ALWAYS** — including when the project is reported as up-to-date in Step 0

---
