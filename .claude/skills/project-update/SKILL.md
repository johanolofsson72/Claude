---
name: project-update
description: "Update speckit and sync Claude Code config from the template repo. Use on existing projects to pull the latest rules, docs, agents, skills, hooks, settings. Triggers: update project, sync config, update claude config, sync rules, refresh project."
argument-hint: "[optional: 'speckit-only' or 'sync-only' to run just one part]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, Glob, Grep
---

# Project Update

You are updating an existing project's speckit installation and Claude Code configuration to the latest version from the template repo.

This skill does NOT run the project wizard interview, and it does NOT run a spec's per-spec interview. It only syncs infrastructure and tooling. (It DOES install/refresh the enforcement that *requires* the per-spec interview — see the spec-interview gate note in Step 5.)

## Input

```text
$ARGUMENTS
```

## Process

### Step 1: Verify prerequisites

Check that the required tools are available:

```bash
command -v uv && echo "[OK] uv found" || echo "[MISSING] uv — install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
command -v specify && echo "[OK] specify found" || echo "[MISSING] specify — will be installed"
```

If `uv` is missing, tell the user to install it and stop.

If `$ARGUMENTS` is `sync-only`, skip to Step 4.

### Step 2: Install/update speckit CLI

```bash
uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git
```

### Step 3: Reinitialize speckit (with constitution protection)

**Backup constitution if it exists:**

```bash
if [ -f .specify/memory/constitution.md ]; then
  cp .specify/memory/constitution.md .specify/memory/constitution-backup.md
  echo "[BACKUP] Constitution backed up"
else
  echo "[SKIP] No existing constitution to back up"
fi
```

**Reinitialize speckit:**

```bash
specify init --here --force --integration claude
```

> **NOTE**: The `--ai` flag was **removed in spec-kit v0.10.0** (deprecated in the v0.9.x line) — it no longer exists. Always use `--integration claude` (this matches `/project-wizard`'s bootstrap — the two skills must stay in sync).

**Restore constitution:**

```bash
if [ -f .specify/memory/constitution-backup.md ]; then
  mv .specify/memory/constitution-backup.md .specify/memory/constitution.md
  echo "[RESTORED] Constitution restored from backup"
else
  echo "[SKIP] No backup to restore"
fi
```

If `$ARGUMENTS` is `speckit-only`, skip to Step 7.

### Step 4: Fetch sync-prompt from template repo

```bash
curl -sL https://raw.githubusercontent.com/johanolofsson72/Claude/main/scripts/sync-prompt.md
```

Read the fetched content carefully.

### Step 5: Execute sync-prompt instructions

Execute all instructions between the `---` markers in the fetched sync-prompt. Specifically:

1. **Read template files** — For each file referenced in the sync-prompt, fetch it from the GitHub raw URL:
   - `/Users/jool/repos/Claude/CLAUDE.md` → `curl -sL https://raw.githubusercontent.com/johanolofsson72/Claude/main/CLAUDE.md`
   - `/Users/jool/repos/Claude/.claude/rules/dotnet.md` → `curl -sL https://raw.githubusercontent.com/johanolofsson72/Claude/main/.claude/rules/dotnet.md`
   - `/Users/jool/repos/Claude/.claude/docs/testing.md` → `curl -sL https://raw.githubusercontent.com/johanolofsson72/Claude/main/.claude/docs/testing.md`
   - etc. — translate ALL `/Users/jool/repos/Claude/` paths to `https://raw.githubusercontent.com/johanolofsson72/Claude/main/`

2. **Read this project's files** — Read existing `CLAUDE.md`, `.claude/settings.json`, and all files under `.claude/` in THIS project.

3. **Language migration** — If this project still has Swedish content in Claude Code config files, translate to English per the sync-prompt's instructions.

4. **Analyze and update** — For each template file:

   | Situation | Action |
   |-----------|--------|
   | File does NOT exist in this project | Copy from template |
   | File exists and matches template | Skip |
   | File exists but is older | Update to template version, preserve `# PROJECT-SPECIFIC` blocks |
   | File exists with project-specific content | Merge — template structure + project customizations |

5. **CLAUDE.md merge** — Update: critical rules, execution mode, workflow, verification, context management, reference files. Preserve: project description, tech stack, commands, project-specific principles.

   **Stack-aware testing docs (CRITICAL — do NOT re-stamp browser docs onto a mobile app).** The web `testing.md` and `spec-testing-checklist.md` are wrong for React Native / Expo (they assume a browser, Playwright, and `dotnet test`). Before overwriting either file:
   - **Read `.claude/.sync-stack` if it exists.** A line `testing=mobile` means this project was already decided mobile — keep it mobile, do NOT fetch the web `testing.md` over it.
   - **Auto-detect mobile** if `.sync-stack` is absent: a root `package.json` with `expo` or `react-native` in dependencies, or an `app.json` / `app.config.{js,ts}` / `eas.json` (→ React Native / Expo); OR a `pubspec.yaml` with a `flutter:` section / `sdk: flutter` (→ Flutter). Either means mobile.
   - **Mobile project (RN/Expo or Flutter)** → fetch `testing-mobile.md` and `spec-testing-checklist-mobile.md` from the template and write them to the project as `.claude/docs/testing.md` and `.claude/docs/spec-testing-checklist.md` (canonical names, mobile content — the doc carries both a React Native and a Flutter section). Do NOT also fetch the web versions. Write `testing=mobile` to `.claude/.sync-stack`.
   - **Hybrid** (.NET/web backend AND an Expo or Flutter client) → keep the web `testing.md` AND additionally install `.claude/docs/testing-mobile.md` + `spec-testing-checklist-mobile.md`. Write `testing=hybrid`.
   - **Web/.NET project** → normal web `testing.md` / `spec-testing-checklist.md`; remove any stray `-mobile` files. Write `testing=web`.
   - This is the exact mechanism in sync-prompt Step 7c — follow it. Re-stamping browser docs onto a native app is the documented failure that left rundan/iskvalp reading "browser back mid-flow" instructions for an app with no browser.

6. **settings.json merge** — UNION of hooks and permissions.deny. Hooks are wired DETERMINISTICALLY via the three helper scripts (`sync-local-llm-hooks.py`, `sync-graphify-wiring.py`, `sync-core-hooks.py`), NOT by hand. Preserve project-specific hooks.

7. **Verify spec testing pipeline** — Ensure rules/specs.md, docs/spec-testing-checklist.md, and the PostToolUse prompt-hook all exist.

8. **Verify Allium + TLA+ pipeline** — Ensure all verification pipeline files exist per sync-prompt instructions.

9. **Install required external skills** — Run the git clone commands for any missing skills (anthropics/skills, superpowers, trailofbits, qa-test, dotnet, vercel, playwright). Skip already-installed ones.

10. **Install TLC model checker** — Verify TLC is available, install if missing.

> **Spec-interview gate (anti-drift) — must land on every project.** As part of the sync-prompt's rule list + script list + core-hook wiring, this sync installs `.claude/rules/spec-interview.md` and `scripts/spec-interview-guard-hook.sh`, and `sync-core-hooks.py` wires the `spec-interview-guard` PreToolUse hook. That hook hard-blocks source-code edits until the active spec records ≥15 human-answered questions in `<spec-dir>/interview.md` (target 15–25). It is the per-spec complement to `/speckit-clarify`'s auto-pick: the interview is where a human pins down scope, edge cases, error/empty/loading states, authorization, and non-goals so the implementation can't drift. Confirm it landed in Step 7's wiring check.

### Step 6: Ask about tech stack and clean up

Use `AskUserQuestion` to confirm the project's tech stack (the sync-prompt has the exact question). Remove irrelevant files based on the answer.

**IMPORTANT**: If this is a re-sync (files already exist and tech stack was already decided), check if `.claude/rules/dotnet.md` etc. have been previously removed. If they were, don't re-add them — respect the previous tech stack decision. Ask the user:

> This project was previously synced. Should I re-evaluate the tech stack, or keep the current file selection?

### Step 7: Verify

- Verify `settings.json` is valid JSON: `python3 -m json.tool .claude/settings.json`
- Normalize hook paths: `python3 scripts/fix-hook-paths.py .claude/settings.json`
- Verify CLAUDE.md does not exceed ~200 lines
- Verify reference files in CLAUDE.md point to files that actually exist
- **Core-hook wiring check** — every core hook script present on disk MUST be wired (catches the prose-merge gap that previously dropped pipeline/register/interview hooks):

  ```bash
  for s in pipeline-trigger-match emit-pipeline-reminder spec-register-guard-hook pipeline-state-guard-hook spec-interview-guard-hook spec-md-coverage-reminder-hook scenario-map-reminder-hook continuous-execution-hook; do
    test -f "scripts/$s.sh" && ! grep -q "$s.sh" .claude/settings.json && echo "[GAP] $s present on disk but NOT wired — run: python3 scripts/sync-core-hooks.py \"\$TEMPLATE/.claude/settings.json\""
  done
  echo "core-hook wiring check done (no [GAP] lines above = complete)"
  ```

  If `spec-interview-guard-hook` prints `[GAP]`, the anti-drift gate is not active — re-run `sync-core-hooks.py` (and confirm `scripts/spec-interview-guard-hook.sh` was copied first).

### Step 8: Report

```markdown
## Project Update Complete

**Speckit**: [installed/updated/skipped] — version [X]
**Sync source**: johanolofsson72/Claude (main branch)
**Constitution**: [preserved/untouched]

### Files synced:
- [CREATED] filename — reason
- [UPDATED] filename — what changed
- [SKIPPED] filename — already current
- [REMOVED] filename — not relevant for tech stack
- [TRANSLATED] filename — migrated Swedish → English

### Enforcement gates:
- spec-interview-guard — [wired / GAP] (anti-drift: 15–25 questions per spec before source edits)
- pipeline-state-guard — [wired / GAP]
- spec-register-guard — [wired / GAP]

### Project-specific preserved:
- filename — what was preserved

### Manual review recommended:
- filename — why

Run `/project-wizard` if you need to update the project's core documents (CLAUDE.md project section, constitution, design system, project brief).
```

## Rules

1. NEVER change the project's core logic or application code.
2. ALWAYS preserve project-specific customizations (marked with `# PROJECT-SPECIFIC` or clearly unique to the project).
3. NEVER overwrite the constitution with speckit's default — always backup and restore.
4. If unsure about a merge conflict: report and ask instead of changing.
5. Do NOT commit automatically — let the developer review first.
6. All template file reads MUST go through GitHub raw URLs, not local paths. This ensures the skill works on any machine.
7. Communicate in English.
