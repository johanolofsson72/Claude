# Acceptance cases — 082-harness-supply-chain-and-unattended-exec

**Confirmed:** 2026-10-01 · 851ea91cc3c2 — "Confirmed as written"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`082-AC-<n>`.

## AC-1 — A dirty template clone does not reach the projects
**Given** a local template clone with an uncommitted edit to a CORE script and no override set
**When** template-autosync.sh runs in a project
**Then** the project gets no file write, no commit and no push, exit is 0, and a [warn] names the clone and both overrides (--force, CLAUDE_TEMPLATE_ALLOW_DIRTY=1)

## AC-2 — The nightly does not run a changed suite command
**Given** a project whose .claude/.suite-command was trusted with --trust and then changed by a commit
**When** project-maintenance.sh --suite --unattended runs
**Then** the command does not execute, a [SUITE] finding names --trust, and the suite job is not stamped; after --trust the same run executes it

## AC-3 — lane-catchup keeps credential denies
**Given** ~/.claude/settings.json with deny rules Read(~/.ssh/**), Read(~/.aws/**) and Read(~/Documents/**)
**When** lane-catchup.sh --apply runs
**Then** the .ssh and .aws rules remain, the Documents rule is removed, and a timestamped backup of the original file exists next to it

## AC-4 — Prune keeps unmerged or untracked agent work
**Given** one agent worktree on a detached HEAD with a commit not in main's HEAD, and another with only an untracked new file
**When** prune-agent-worktrees.sh runs
**Then** both worktrees still exist and each is reported KEEP with its reason

## AC-5 — A remote OLLAMA_HOST sends nothing
**Given** OLLAMA_HOST=http://example.com:11434 and LOCAL_LLM_ALLOW_REMOTE unset
**When** a local-llm hook sources local-llm-detect.sh
**Then** LOCAL_LLM_AVAILABLE is 0 and no request leaves the machine; with LOCAL_LLM_ALLOW_REMOTE=1 the host is accepted
