# Acceptance cases — 095a-mod-loading-guard

**Confirmed:** 2026-10-03 · 4eb82fb4dbb6 — "Confirm"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`095a-AC-<n>`.

## AC-1 — Creating a mod in the user skills folder is refused on every route
**Given** the settings guard on PreToolUse and a config directory with a `skills/` folder
**When** the agent writes `skills/probe/.claude-plugin/plugin.json` with Write, writes `skills/probe/hooks/hooks.json` with a shell heredoc, copies a prepared folder with `cp -r /tmp/m <config>/skills/probe`, and calls `mcp__fs__write_file` with a path to `skills/probe/hooks/register.ts`
**Then** each call is denied with a reason that names the path and says a loaded mod can allow any tool call past every hook

## AC-2 — A plugin folder anywhere is off limits to writes and open to reads
**Given** a folder `mods/x/` outside every load root holding `hooks/hooks.json` and `hooks/register.ts`, and a folder `mods/y/` with no markers
**When** the agent Edits `mods/x/hooks/register.ts`, Writes `mods/x/lib/util.ts`, Writes `mods/y/hooks/hooks.json`, runs `cat mods/x/hooks/register.ts`, and Writes `mods/y/notes.md`
**Then** the first three are denied and the read and the notes write are allowed with no output

## AC-3 — Git cannot bring a mod into the tree
**Given** a fixture repository with a commit REV that adds `.claude/skills/z/hooks/hooks.json`, and HEAD without it
**When** the guard is asked about `git checkout REV -- .`, `git restore --source=REV .`, and `git checkout HEAD -- README.md`
**Then** the first two are denied as mod writes and the third is allowed with no output

## AC-4 — Ordinary skill and template work is unaffected
**Given** the template repository with its `.claude/skills/<name>/SKILL.md` files and no plugin markers
**When** the agent Edits `.claude/skills/tla/SKILL.md`, runs `git add .claude/skills/tla/SKILL.md`, and runs `ls ~/.claude/plugins`
**Then** all three are allowed with no output, while `mv /tmp/s .claude/skills/tla` is denied as a write that replaces a skill folder
