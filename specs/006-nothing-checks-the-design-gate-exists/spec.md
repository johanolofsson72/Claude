# 006 — nothing checks the design gate exists

Track: spec-only (tooling fix, no new entity, no state machine). Diagnosis: `specs/INDEX.pending.md` § 006.

## Problem

`CLAUDE.md` names two skills as BLOCKING by bare name, and neither ships with the template:

| Skill | Where it actually lives | What installs it |
|---|---|---|
| `frontend-design` | plugin `frontend-design@claude-plugins-official` (plugin cache) | `project-wizard` Step 6 |
| `humanizer` | `~/.claude/skills/humanizer` (git clone of blader/humanizer) | nothing in the template |

The bare name does resolve when the skill is there (measured 2026-09-03), so the names are fine.
The problem is presence. Every caller is prose that tells the model to invoke a skill, and none of
them checks the skill can be invoked. On a machine without it (fresh clone, a second lane, a cleared
plugin cache, a disabled plugin) the `Skill` call fails and the BLOCKING gate becomes nothing. No
hook fires and no report shows it.

The other skills the rules name are either shipped in `.claude/skills/` (allium, tla, code-review…)
or installed per project by spec-kit, which `project-maintenance.sh` §3b already checks. That
leaves these two.

## Requirements

- **R1** One predicate, `scripts/skill-reachable.sh`, answers "can the Skill tool load skill X on
  this machine for this project". It looks in the project's `.claude/skills/`, the user's
  `skills/` under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, and every installed plugin's `skills/`
  directory from `plugins/installed_plugins.json`. A plugin explicitly disabled (`false` in
  `enabledPlugins`, with local > project > user precedence) does not count.
- **R2** `--required` checks the BLOCKING external set (`frontend-design`, `humanizer`), which is
  kept in that one script. It prints one line per missing skill with its install command.
- **R3** Exit codes: 0 all reachable · 1 at least one missing · 2 usage error · 3 cannot tell
  (no python3 to read the plugin registry). "Cannot tell" never reads as "reachable".
- **R4** `scripts/ui-design-hook.sh`: when a UI edit is detected and `frontend-design` is missing,
  the model gets a message saying the gate cannot be met and why, and the developer gets a
  one-line notice with the install command (`notice_both`). When it is present, the output is the
  same as today. When the check cannot tell (exit 3), or the script is absent, the output is the
  same as today (fail open).
- **R5** `scripts/project-maintenance.sh` gets a section that reports each missing required skill
  as a finding. Exit 3 becomes a note. The section is silent when the script is absent.
- **R6** Both scripts are CORE (`template-autosync.sh` `CORE_SCRIPTS`) so every project gets them.
- **R7** `scripts/test-skill-reachable.sh` covers each location, the disabled-plugin case, the
  qualified `plugin:skill` form, missing skills, usage errors and the hook's two outputs, all on
  fixtures under `CLAUDE_CONFIG_DIR`, never the real `~/.claude`.

## Non-goals

- Renaming the bare names (refuted in the diagnosis).
- Installing anything automatically. The check reports and the developer installs.
- Denying UI edits when the plugin is missing. The gate reports loudly and stays advisory, like
  every other reminder-class hook.
- Checking skills that ship in `.claude/skills/` or come from spec-kit (§3b already covers those).

## Acceptance

- `bash scripts/test-skill-reachable.sh` green; each case has been bite-checked by breaking the
  code it covers.
- `bash scripts/skill-reachable.sh --required` exits 0 on this machine.
- With a fixture config dir that has no plugin, the hook's output carries `systemMessage` naming
  the install command.
- `bash scripts/test-project-maintenance.sh` and `bash scripts/test-pipeline-hooks.sh` still green.

## Clarifications

### Session 2026-09-29

- Q: Should a missing plugin deny the UI edit? → A: No. Report it on both channels and let the
  edit through. A deny would stop every UI edit on a machine that simply lacks a plugin, and the
  developer can't fix that from inside the edit. (auto-picked, recommended)
- Q: Should `humanizer` be in the required set even though no hook enforces it today? → A: Yes. It
  is BLOCKING in `CLAUDE.md`, and a check that covers only `frontend-design` would leave the same
  gap with a smaller radius (diagnosis scope note). (auto-picked, recommended)
- Q: Does the maintenance check apply to the template repo itself? → A: Yes. Unlike §3b it is about
  the machine, not the project, and the template's own `CLAUDE.md` calls both gates BLOCKING.
  (auto-picked, recommended)
