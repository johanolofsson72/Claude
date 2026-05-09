---
name: sync-template
description: Syncs project configuration from the Claude Code template repo. Updates skills, agents, hooks, rules, and docs to match the latest template. Use when starting a new project or upgrading an existing project's Claude Code configuration.
disable-model-invocation: true
argument-hint: "[full|skills|agents|hooks|docs]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Sync from template repo

Update this project's Claude Code configuration from the template repo at `/Users/jool/repos/Claude`.

## What to sync

Argument controls scope. Default: `full`.

- `full` — sync everything below
- `skills` — only .claude/skills/
- `agents` — only .claude/agents/
- `hooks` — only .claude/settings.json hooks
- `docs` — only .claude/docs/

## Process

### 1. Read template files

Read these files from the template repo (`/Users/jool/repos/Claude`):

**Skills (`.claude/skills/`):**
- `code-review/SKILL.md`
- `explore-codebase/SKILL.md`
- `deploy-checklist/SKILL.md`
- `tla/SKILL.md`
- `allium/SKILL.md`
- `update-template/SKILL.md`
- `sync-template/SKILL.md`

**Agents (`.claude/agents/`):**
- `dotnet-reviewer.md`
- `security-scanner.md`
- `test-runner.md`
- `db-agent.md`

**Settings:** `.claude/settings.json`

**Rules (`.claude/rules/`):**
- `dotnet.md`
- `frontend.md`
- `security.md`
- `wordpress.md`
- `allium.md`
- `specs.md`
- `tests.md`

**Docs (`.claude/docs/`):**
- `skills.md`
- `workflows.md`
- `agents-templates.md`
- `conventions.md`
- `git.md`
- `security.md`
- `testing.md`
- `deployment.md`
- `stress-testing.md`
- `spec-testing-checklist.md`
- `project-template.md`

**Scripts:**
- `scripts/tla-hook.sh`
- `scripts/allium-hook.sh`
- `scripts/tlc-cleanup.sh`
- `scripts/test-coverage-hook.sh`
- `scripts/continuous-execution-hook.sh`
- `scripts/stop-validation-hook.sh`
- `scripts/ui-design-hook.sh`
- `scripts/after-specify-hook.sh`
- `scripts/local-llm-call.sh` (telemetry funnel + auto-detect)
- `scripts/local-llm-detect.sh`
- `scripts/local-llm-stats.sh` (per-hook ROI reporter)
- **Glob: every `scripts/local-llm-*-hook.sh`** — pull all matching files from the template. The template adds new local-LLM hook scripts over time; do not maintain a hand-edited list. Use `Glob` on `scripts/local-llm-*-hook.sh` against the template root and copy each file. Files present in the project but no longer in the template should also be removed (the template is the source of truth for the local-LLM hook script set).

### 2. Compare and merge

For each file:

1. If the file does not exist in the target project, copy it from the template
2. If the file exists, compare and identify differences
3. Preserve any project-specific customizations (marked with `# PROJECT-SPECIFIC` comments)
4. Update generic template content to match the latest version
5. Report what was changed

### 3. Settings.json merge rules

For `.claude/settings.json`:
- MERGE `permissions.deny` lists (union of both).
- For `hooks` entries that invoke `bash scripts/local-llm-*-hook.sh`: **REPLACE the project's set with the template's**. The template is the source of truth for which local-LLM hooks are wired by default (token-saver-only policy — quality-gate scripts stay on disk but unwired). Do NOT additively merge — that preserves stale wiring for hooks the template has retired.
- For other hook entries (project-specific or non-local-LLM template hooks): MERGE — add missing hooks, preserve existing custom hooks.
- Preserve any project-specific settings not in the template.

### 3a. .gitignore additions

Ensure the project's `.gitignore` covers these patterns. Add any that are missing:

- `.claude/validation/`
- `.claude/.local-llm-*` (draft artifact files written by hooks)
- `.claude/local-llm-*.log` (per-project telemetry log)
- `.claude/local-llm-*.log.errors` (telemetry write-error log)
- `.claude/projects/` (per-user memory directory — never commit)
- `.claude/settings.local.json` (per-machine settings)

### 4. CLAUDE.md handling

Do NOT overwrite the project's CLAUDE.md. Instead:
- Check if the project's CLAUDE.md references `.claude/docs/skills.md` — if not, update the reference
- Check if `.claude/skills/` is mentioned in the file organization section — if not, add it
- Report any sections that differ from the template for manual review

### 5. Bootstrap caveat

If the project's `sync-template/SKILL.md` is OLDER than the template's, the current sync run is using outdated instructions. After the run, the project's SKILL.md will have been updated — but the changes you just made followed the OLD rules. Tell the user to re-run `/project-update` once more so the new rules take effect. If the SKILL.md was already current, this step is a no-op.

### 6. Report

After syncing, output a summary:

```
Synced from template (YYYY-MM-DD):
- [CREATED/UPDATED/SKIPPED] .claude/skills/code-review/SKILL.md
- [CREATED/UPDATED/SKIPPED] .claude/agents/dotnet-reviewer.md
- ...

Project-specific files preserved:
- .claude/agents/custom-agent.md
- ...

Manual review needed:
- CLAUDE.md: section X differs from template
- ...
```
