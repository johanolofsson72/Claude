# Acceptance cases — 095-guard-fail-open-sweep

**Confirmed:** 2026-10-03 · 0ef26972f5af — "Confirm"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`095-AC-<n>`.

## AC-1 — A git command that would rewrite the hooks is refused, a harmless one is not
**Given** a fixture repository whose committed `.claude/settings.json` wires a PreToolUse hook, and an older commit REV whose settings file lacks it
**When** the settings guard is asked about `git checkout REV -- .`, `git restore --source=REV .`, `git stash pop` of a stash that removes the hook, and `git apply` of a patch that touches the settings file
**Then** each is denied with a reason that names the settings file, while `git checkout HEAD -- .` on an unchanged settings file and `git switch -c topic` are allowed with no output

## AC-2 — Any settings key outside the safe list is guarded
**Given** a project settings.json with hooks, permissions and outputStyle
**When** the guard is asked about Edits that add `apiKeyHelper`, add `statusLine`, add `enabledPlugins`, and remove an entry from `permissions.deny`, and about Edits that add a `permissions.allow` entry and change `language`
**Then** the first four are denied and the last two are allowed

## AC-3 — An MCP write tool is judged like a built-in one
**Given** both guards and the template's settings.json matchers
**When** `mcp__fs__write_file` is called with a path to `.claude/settings.json`, and with a path to `.git/claude-developer-words`, and with a path to `src/a.txt`
**Then** the settings guard denies the first, trust-anchor-guard denies the second, the third is allowed, and both guards' matchers in `.claude/settings.json` match the tool name `mcp__fs__write_file`

## AC-4 — Removing the language marker no longer turns the pipeline guards off
**Given** a git repository that is not the template, with `specs/INDEX.md` naming an active full-track spec that has no interview, and no language marker anywhere
**When** the spec-interview guard is asked about an Edit to `src/app.ts`
**Then** it denies the edit as it would with a `package.json` present, while the same edit in the template repository itself is allowed

## AC-5 — Shell reads are trusted only in a clean command, and harmless reads pass
**Given** the settings guard and trust-anchor-guard on PreToolUse for Bash
**When** they are asked about `export GIT_EXTERNAL_DIFF=/tmp/x; git diff <settings>`, a function named `cat` defined before `cat <settings>`, and `git config core.hooksPath /tmp/h`, and about `sed -n 1,5p <settings>`, `git -c core.fsmonitor=false status` and a `finding.sh --add` whose prose contains `--trust`
**Then** the first three are denied and the last three are allowed
