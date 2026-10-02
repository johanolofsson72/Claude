# Acceptance cases — 089-settings-edit-guard

**Confirmed:** 2026-10-02 · d9cafe921189 — "Confirmed as written"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`089-AC-<n>`.

## AC-1 — An Edit that unwires a hook is refused
**Given** a project whose `.claude/settings.json` wires a PreToolUse hook, with `CLAUDE_PROJECT_DIR` set to it
**When** the guard is asked about an Edit that removes that hook entry, a Write that adds `"disableAllHooks": true`, or a MultiEdit that leaves the file invalid JSON
**Then** each is denied with a reason that names the file and the developer's two routes (edit by hand, or a `!` command)

## AC-2 — An env key in settings.local.json is refused, the rest is not
**Given** a project with no `.claude/settings.local.json`
**When** the guard is asked about a Write that creates it with `"env": {"SPEC_ACCEPTANCE": "off"}`, and about a Write that creates it with only a `permissions.allow` entry
**Then** the first is denied and the second is allowed with no output

## AC-3 — The shell route is refused, reads are not
**Given** the guard on PreToolUse for Bash, in the project directory
**When** it is asked about `sed -i '' 's/x/y/' .claude/settings.json`, `rm .claude/settings.local.json`, `cd .claude && mv settings.json x`, and `printf '{}' > ~/.claude/settings.json`
**Then** each is denied without echoing the command, while `jq .hooks .claude/settings.json`, `git add .claude/settings.json` and `grep -n env .claude/settings.local.json` are allowed

## AC-4 — Formatting and non-guarded keys stay editable
**Given** a project settings.json with hooks, env and permissions
**When** the guard is asked about an Edit that only re-indents the file, and one that adds a `permissions.allow` entry
**Then** both are allowed

## AC-5 — bash-write-guard hands a shell write to the guard
**Given** bash-write-guard with settings-edit-guard in its delegate list
**When** a command writes `.claude/settings.json` through `tee`, and a `python3 -c` one-liner names it
**Then** bash-write-guard denies both, with the settings guard's own reason under its lead line
