#!/usr/bin/env bash
# update-template.sh — Analyzes latest Claude Code best practices online
# and updates the template repo structure (.claude/, CLAUDE.md, etc.)
#
# Usage:
#   ./scripts/update-template.sh              # Full update
#   ./scripts/update-template.sh --dry-run    # Report only, no changes
#   ./scripts/update-template.sh --focus hooks # Focus on a specific area
#
# Requires: claude CLI (Claude Code) installed

set -euo pipefail

REPO_ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=false
FOCUS=""
DATE=$(date +%Y-%m-%d)

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --focus)   FOCUS="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--focus <area>]"
      echo ""
      echo "Areas: hooks, skills, agents, rules, docs, settings, claude-md"
      echo ""
      echo "Examples:"
      echo "  $0                    # Full update"
      echo "  $0 --dry-run          # Report only"
      echo "  $0 --focus skills     # Skills-related only"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Validate that claude CLI exists
if ! command -v claude &>/dev/null; then
  echo "Error: 'claude' CLI not found. Install Claude Code first."
  echo "  curl -fsSL https://claude.ai/install.sh | bash"
  exit 1
fi

# Spec 082 (F066): the review step is `git diff`, which only shows this run's work on a clean tree.
# Repository config that can execute (core.fsmonitor, hooks) is switched off for every git call this
# script makes: the tree is about to be edited by a model that read the open web (spec 082).
if [ -n "$(git -C "$REPO_ROOT" -c core.fsmonitor=false -c core.hooksPath=/dev/null status --porcelain 2>/dev/null)" ]; then
  echo "Error: $REPO_ROOT has uncommitted changes. Commit or stash them first, so the diff at the end is only this run's."
  exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Claude Code Template Updater                       ║"
echo "║  Date: $DATE                                   ║"
echo "║  Mode: $([ "$DRY_RUN" = true ] && echo 'DRY RUN (no changes)       ' || echo 'LIVE (updating files)       ')║"
[ -n "$FOCUS" ] && \
echo "║  Focus: $(printf '%-44s' "$FOCUS")║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Build focus filter
FOCUS_INSTRUCTION=""
if [ -n "$FOCUS" ]; then
  FOCUS_INSTRUCTION="Focus ONLY on the area: $FOCUS. Ignore other areas."
fi

# Build dry-run instruction
MODE_INSTRUCTION=""
if [ "$DRY_RUN" = true ]; then
  MODE_INSTRUCTION="IMPORTANT: This is a DRY RUN. Do NOT change any files. ONLY write a report with recommendations."
else
  MODE_INSTRUCTION="Apply all recommended changes directly to the files. Do NOT commit: you have no shell, and the changes stay uncommitted so a human reviews them before anything ships to the projects."
fi

# Main prompt sent to Claude
read -r -d '' PROMPT <<'PROMPT_EOF' || true
You are an expert on Claude Code configuration. Your task is to analyze the latest news, guidelines, and best practices for Claude Code and then update this template repo.

## Step 1: Research (MANDATORY)

Search online for ALL of the following. Use the WebSearch tool for each search:

1. **Claude Code changelog & release notes** — Search: "Claude Code changelog 2026", "Claude Code release notes latest"
2. **CLAUDE.md best practices** — Search: "CLAUDE.md best practices 2026", "claude code configuration guide"
3. **Agent Skills standard** — Search: "agentskills.io", "claude code skills SKILL.md"
4. **Claude Code hooks** — Search: "claude code hooks PostToolUse PreToolUse 2026"
5. **Claude Code new features** — Search: "claude code new features 2026", "anthropic claude code update"
6. **Context engineering** — Search: "context engineering claude code", "claude code context management best practices"
7. **Claude Code settings.json schema** — Search: "claude code settings.json schema permissions"
8. **Community best practices** — Search: "claude code CLAUDE.md examples github", "claude code configuration template"

Collect ALL relevant information before proceeding.

## Step 2: Analyze current structure

Read the following files in this repo:
- CLAUDE.md
- .claude/settings.json
- .claude/docs/skills.md
- .claude/docs/workflows.md
- .claude/docs/conventions.md
- .claude/rules/*.md
- .claude/agents/*.md
- .claude/skills/*/SKILL.md

## Step 3: Identify gaps

Compare what you found online (step 1) with the current structure (step 2). Identify:

1. **New features** that should be used but are missing
2. **Deprecated patterns** that should be removed or replaced
3. **Improved patterns** that should be updated
4. **New hooks/settings** that should be added
5. **New skill types** that should be created
6. **Security improvements** that are missing
7. **Performance/context optimizations** that can be made

## Step 4: Report and actions

Write a clear report in the following format:

```
## Update report ($DATE)

### New features found
- [feature]: [description] → [action]

### Deprecated/changed patterns
- [pattern]: [what changed] → [action]

### Recommended updates
1. [file]: [change]
2. [file]: [change]

### No changes needed
- [area]: [reason]
```

$MODE_INSTRUCTION

$FOCUS_INSTRUCTION

## Rules

- Write ALL communication in English
- Keep the size of CLAUDE.md as small as possible
- Code and technical terms in English
- Preserve ALL project-specific customizations (marked with # PROJECT-SPECIFIC)
- NEVER change the fundamental structure without strong reasons
- Priority: Security > Correctness > Simplicity
- If unsure, report instead of changing
- Do not edit scripts/, .git/ or .claude/settings*.json (those edits are denied). Put any change they need in the report as a recommendation, with the file and the exact change
- Run the humanizer skill on ALL generated text aimed at humans
PROMPT_EOF

# Replace variables in the prompt
PROMPT="${PROMPT//\$MODE_INSTRUCTION/$MODE_INSTRUCTION}"
PROMPT="${PROMPT//\$FOCUS_INSTRUCTION/$FOCUS_INSTRUCTION}"
PROMPT="${PROMPT//\$DATE/$DATE}"

echo "Starting Claude Code analysis..."
echo ""

# Spec 082 (F066). The prompt sends the model to the open web, so every page it reads is a chance to
# inject instructions, and what it edits here syncs into every project. So the model gets no shell
# and no sub-agents: `--disallowedTools` is a deny, and a deny holds even under a bypassPermissions
# default, where `--allowedTools` alone restricts nothing. A dry run gets no write tools either.
# Edit/Write stay in a live run (they are the job); the changes are left uncommitted and the run
# ends on `git diff --stat`, so a human is the last step before anything reaches a project.
#
# Review finding 4: Edit/Write without limits still reached code that runs later -- .git/ (hooks,
# core.fsmonitor, run by the closing `git diff`), settings.json (hook commands) and scripts/ (the
# hooks themselves, run on the next tool call in this very session). So those paths are denied, and
# script changes come back as recommendations in the report. Read is denied on the credential
# stores, because Read plus WebFetch is an exfiltration channel. Space-separated: `claude --help`
# documents the flag as a comma- or space-separated list.
# Spec 091 R5 (F080). Those path rules are relative to the repository, so an injected model could still
# Write ~/.claude/settings.json, a shell rc file or .mcp.json. --restricted confines the file tools to the
# working directory, ignores user/project/local settings, refuses bypassPermissions and leaves writes to
# settings, git and tool-configuration files to a person; dontAsk denies whatever is not pre-allowed
# instead of prompting nobody; --tools must name WebFetch, which restricted mode otherwise removes. A
# claude that does not know --restricted cannot confine the model, so the run does not start.
CLAUDE_HELP=$(claude --help 2>/dev/null || true)
if ! grep -Eq '^[[:space:]]*--restricted([^[:alnum:]-]|$)' <<< "$CLAUDE_HELP"; then
  echo "Error: this claude has no --restricted mode, so the model could write outside $REPO_ROOT." >&2
  echo "       Update Claude Code (claude update) and run this again. Nothing was started." >&2
  exit 2
fi
ALLOWED="WebSearch,WebFetch,Read,Glob,Grep,Skill"
GUARDED="Edit(.git/**) Write(.git/**) Edit(.claude/settings*.json) Write(.claude/settings*.json)"
GUARDED="$GUARDED Edit(.mcp.json) Write(.mcp.json)"
GUARDED="$GUARDED Edit(scripts/**) Write(scripts/**)"
GUARDED="$GUARDED Read(~/.ssh/**) Read(~/.aws/**) Read(~/.gnupg/**) Read(~/.config/gh/**) Read(~/.netrc) Read(~/.git-credentials)"
DISALLOWED="Bash Agent $GUARDED"
if [ "$DRY_RUN" = true ]; then
  DISALLOWED="Bash Agent Edit Write $GUARDED"
else
  ALLOWED="$ALLOWED,Edit,Write"
fi

# A predictable /tmp name can be pre-created as a symlink by another local user; mktemp cannot.
LOG=$(mktemp "${TMPDIR:-/tmp}/claude-template-update.XXXXXX")
echo "Log: $LOG"

cd "$REPO_ROOT"
# set +e around the pipe: under -e with pipefail a failing claude would end the script here, before
# the exit code is reported and before the diff a human needs to see.
set +e
claude -p "$PROMPT" --restricted --permission-mode dontAsk --tools "$ALLOWED" \
  --allowedTools "$ALLOWED" --disallowedTools "$DISALLOWED" 2>&1 | tee "$LOG"
EXIT_CODE=${PIPESTATUS[0]}
set -e

# Spec 091 R5, 095 R11. --restricted may not count a skill's or agent's frontmatter as tool configuration, and a
# `hooks:` key there runs commands in every project the sync reaches. Every changed or new file under
# .claude/skills, .claude/agents or .claude/commands is read: a frontmatter key that grants or wires
# something, or any file that is not markdown (a script), is named for review. Nothing is reverted.
REVIEW=$(git -C "$REPO_ROOT" -c core.fsmonitor=false -c core.quotePath=false status --porcelain -uall \
           -- .claude/skills .claude/agents .claude/commands .claude/rules .claude/docs CLAUDE.md 2>/dev/null \
         | cut -c4- | sed 's/.* -> //' | while IFS= read -r f; do
  [ -f "$REPO_ROOT/$f" ] || continue
  # Spec 095 R11 (F135): rules, docs and CLAUDE.md are prompt text the sync carries into every project.
  if [ "$f" = CLAUDE.md ] || [ "${f#.claude/rules/}" != "$f" ] || [ "${f#.claude/docs/}" != "$f" ]; then
    echo "[REVIEW] $f: prompt text that syncs into every project"
    continue
  fi
  if [ "${f%.md}" != "$f" ]; then   # an if: bash 3.2 cannot parse a case inside $(...)
      if awk 'NR == 1 { sub(/^\xef\xbb\xbf/, ""); sub(/[[:space:]]+$/, ""); if ($0 != "---") exit 1; next }
              { sub(/\r$/, "") }
              /^---[[:space:]]*$/ { exit 1 }
              /^[[:space:]]*["\047]?(hooks|allowed-tools|allowedTools|permissionMode|mcpServers)["\047]?[[:space:]]*:/ { found = 1; exit 0 }
              END { exit found ? 0 : 1 }' "$REPO_ROOT/$f"; then
        echo "[REVIEW] $f: its frontmatter sets hooks, allowed-tools, permissionMode or mcpServers"
      fi
  else
    echo "[REVIEW] $f: not markdown, so it can run in every project the sync reaches"
  fi
done)

echo ""
echo "════════════════════════════════════════════════════════"
if [ $EXIT_CODE -eq 0 ]; then
  echo "Done! Log saved: $LOG"
else
  echo "Error occurred (exit code: $EXIT_CODE)"
  echo "See log: $LOG"
fi
echo ""
echo "Review before committing (git diff --stat):"
git -C "$REPO_ROOT" -c core.fsmonitor=false -c core.hooksPath=/dev/null --no-pager diff --no-ext-diff --no-textconv --stat
if [ -n "$REVIEW" ]; then
  echo ""
  printf '%s\n' "$REVIEW"
  # claude's own failure wins: exit 4 only replaces a clean run's 0.
  [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=4
fi
exit $EXIT_CODE
