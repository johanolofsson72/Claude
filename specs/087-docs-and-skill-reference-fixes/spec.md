# 087 — docs and skill reference fixes

Track: spec-only. No entity, no state machine, no new external surface. Five small fixes to
reference docs, agent definitions and one spec-kit policy patch. Not hardened: no trigger fires.
The agent change narrows what review agents can do rather than widening it. Findings verbatim in
`specs/FINDINGS.md`.

## Problem

| Finding | Where | What goes wrong today |
|---|---|---|
| F008 | `.specify/templates/spec-template.md` (spec-kit) | Success Criteria are numbered `SC-001…`, the scenario map's id prefix. Every new spec re-introduces the collision; ighweld 198 renamed all of them by hand |
| F009 | `.claude/agents/{security-scanner,dotnet-reviewer,db-agent}.md` | `memory: project` plus `isolation: worktree`: the agent writes `.claude/agent-memory/**` inside a throwaway worktree, so the memory strands. rocky harvested 24 files over three checkpoints |
| F007 | the same agents | a worktree is cut from a commit, not the working tree. An agent reviewing uncommitted work reads an older tree; ighweld's scanner reported a whole spec unimplemented while it was on disk and green |
| F006 | `.claude/docs/testing.md` | nothing warns that `getComputedStyle` returns `color(srgb …)` 0–1 components for `color-mix()`, which an `rgb()` parser reads as near-black. A 2.83:1 badge "passed AA at 6.36:1" |
| F054 | `.claude/skills/allium/SKILL.md` | the v3 reference example draws warnings on allium 3.6.1 (`undeclaredTransition shipped→cancelled`, `unreachableValue` pending/delivered, unused `Priority`/`Address`), and every elicit copies it |

## Requirements

- **R1 (F008).** `scripts/speckit-extension-policy.sh` rewrites the Success Criteria ids in
  `.specify/templates/spec-template.md` from `SC-001`… to `SC-A`…, keeping the `SC-` prefix that
  `/speckit-analyze` and `/speckit-converge` key on while leaving the scenario map's `SC-<digits>`
  space alone. It adds one line telling the author to keep letters. Same mechanics as the existing
  stop patches: verbatim anchor, a marker, idempotent, `--dry-run` honoured, a missing template is
  skipped, a moved anchor is exit 2 with a `FAIL` line.
- **R2 (F009, F007).** The three template agents with `memory: project` drop `isolation: worktree`.
  A reviewer then reads the working tree the developer is on, uncommitted changes included, and
  writes its memory where the main session can see it.
- **R3 (F009).** `project-maintenance.sh` reports `[AGENTS]` for any `.claude/agents/*.md` whose
  frontmatter has both `memory:` and `isolation: worktree`, naming the file and pointing at the fix.
  A project-authored agent cannot reintroduce the defect unseen.
- **R4 (F007).** The review agents (`security-scanner`, `dotnet-reviewer`) start their report with
  the tree they read, and never report something as unimplemented without naming the path they
  looked for. `agents-templates.md` tells the dispatcher to pass the HEAD commit and changed paths in
  the prompt, and to check a "missing" claim on disk before acting on it.
- **R5 (F006).** `testing.md` gets a short contrast-check section: the `color(srgb …)` trap, and the
  two safe ways (axe-core's `color-contrast` rule, or let the browser normalise the colour through
  a canvas pixel before computing the ratio).
- **R6 (F054).** The allium v3 reference example passes `allium check` on 3.6.1 with zero warnings,
  while still showing every construct it shows today. On an older CLI the only warnings left are the
  ones `allium-check-hook.sh` already calls old-CLI noise.

## Non-goals

- Upgrading anyone's allium CLI.
- Harvesting memory already stranded in worktrees; `prune-agent-worktrees.sh` does that.
- Rewriting other spec-kit templates or the scenario map's own id scheme.

## Success criteria

- **SC-A.** A fresh spec-kit template passed through the policy has no `SC-0` id; a second run
  changes nothing.
- **SC-B.** No template agent has `memory:` with `isolation: worktree`, and maintenance flags a
  project agent that does.
- **SC-C.** `allium check` 3.6.1 on the extracted example exits 0.

## Clarifications

### Session 2026-10-02

- Q: Does R1 also rename the `SC-###` mentions in spec-kit's analyze/converge skills? → A: No. Those
  describe the format generically and key on the prefix, which `SC-A` keeps.
- Q: Does R3 read agents outside `.claude/agents/` (plugins, user-global)? → A: No. Only the
  project's own agents, which are the ones whose memory lands in the project.
- Q: Is a commented-out or quoted `isolation: worktree` a match? → A: Only a frontmatter line, read
  between the first two `---` lines.
