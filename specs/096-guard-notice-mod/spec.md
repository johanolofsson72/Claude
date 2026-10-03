# 096 — guard-notice mod

Track: light (one actor, the developer at the terminal; no concurrency; UI is a toast and a band).
Not hardened: the mod reads and displays, it writes nothing and widens no trust boundary. The one
security-relevant piece, the installer, is closed by refusing it to the agent (R6). Source: F148
(approved proposal), F144. Depends on 095a (M2: staged source, `!` install).

## Problem

Two things the developer should see only reach the model or scroll away:

- A guard that fails open says so with `guard_announce`, which writes `additionalContext`. The model
  reads it; the developer never does (F144). A guard deny reaches the developer only as the model's
  paraphrase.
- The SessionStart banner (next register row, checkpoint due, maintenance due) is printed once and
  scrolls off within a few turns.

Claude Code 2.1.287+ mods can draw a toast and a band above the prompt. A mod is also what 095a
guards, so this one is staged in the repository under names that do not load, and the developer
installs it with a script they run with the `!` prefix.

## Requirements

- **R1 — staged source.** `mods/guard-notice/` holds the mod under names that do not load: no
  `.claude-plugin/` component and no `hooks/hooks.json`. The manifest is `plugin.json.staged`, the
  hooks list is `hooks.json.staged`, the module is `register.tsx`, the pure logic is `lib.ts`, the
  `$.state` contract is `types/index.d.ts`. 095a's guard leaves every one of these editable.
- **R2 — fail-open toast.** On `tool.call`, after `next(e)`, every `context` entry that a guard's
  fail-open note wrote (`… could not decide and ALLOWED this call: <cause>` or `… crashed and ALLOWED
  this edit unchecked …`) raises one toast naming the guard and the cause, at most once per session
  per guard and cause. The note still reaches the model unchanged.
- **R3 — deny toast.** A result whose `deny` starts with `BLOCKED —` raises a toast with that first
  line (cut at 160 characters), at most once per distinct first line per session. The deny reaches
  the model unchanged.
- **R4 — register band.** Above the prompt, one dim line: `Next: <id> <slug>` for the active register
  row (the first `- [/]`, else the first `- [ ]`, never a held `- [!]`), then `   Due: <names>` when
  `scripts/maintenance-due.sh --brief` lists any (`full test suite` shown as `suite`, `mutation kill
  rate` as `mutation`, others by their first word), then `   Checkpoint next` when the active row is
  a checkpoint (`H<n>`). Toast copy (frontend-design pass): `<guard> didn't check this call: <cause>`
  for 6 seconds (a toast is text only, so its length of stay is the emphasis), `Blocked: <first line
  without "BLOCKED — ">` for the default 4. A `Hide` button hides it for the session. No `specs/INDEX.md`
  in the session's directory: no band. The register is read at session start and after each turn;
  the maintenance script runs at most once every 10 minutes, with a 20-second limit, and a failure
  shows `maintenance: unknown`, never an error in the transcript.
- **R5 — install.** `scripts/install-guard-notice-mod.sh [--target DIR] [--uninstall]` copies the
  staged files into `DIR` (default `<config>/skills/guard-notice`, which Claude Code 2.1.288 loads
  without a flag), renaming the two staged files into place, and runs `claude plugin validate` on the
  result when `claude` is on PATH. It refuses to overwrite a folder it did not install (no
  `.guard-notice-installed` marker). `--uninstall` removes only a folder carrying that marker.
- **R6 — the installer is the developer's.** The settings guard denies (`mod-bash`) any command that
  runs a script named `install-*-mod.sh`, so the agent cannot install a mod through it. The pre-check
  wakes on `-mod.sh`. A `!` command runs outside every hook, which is the intended route.
- **R7 — docs.** `.claude/docs/workflows.md` (the mods note) and the installer header say how to
  install, load, hide and remove it, and that the agent cannot.

## Out of scope

- F144 itself (the predictable dedupe stamp). The mod sees a notice only when the guard emits one;
  a pre-created stamp still silences both. Stays a finding.
- Toasts for hooks other than this template's guards; a pane; desktop/VS Code surfaces beyond what
  the band and toast draw by default.

## Success criteria

- SC-A: with the mod installed and a guard forced to fail open, the developer sees a toast naming the
  guard and the cause; with a guard deny, a toast with the deny's first line.
- SC-B: the band shows the active row and the maintenance-due names in this template.
- SC-C: the agent's `bash scripts/install-guard-notice-mod.sh` is denied; the developer's
  `! bash scripts/install-guard-notice-mod.sh` installs a folder `claude plugin validate` accepts.

## Functional coverage

| Function | Test |
|---|---|
| R2 fail-open classify + dedupe | `lib.test.ts` (`failOpenNotices`, `Seen`) |
| R3 deny classify + dedupe | `lib.test.ts` (`denyLine`) |
| R4 register row, maintenance parse, band text | `lib.test.ts` (`activeRow`, `maintenanceDue`, `bandText`) |
| R1, R5 staged layout, install, refuse, uninstall, validate | `scripts/test-guard-notice-mod.sh` |
| R6 installer refused to the agent | `scripts/test-settings-edit-guard.sh` [096-R6] |

The four states: success (toast or band drawn); error (maintenance script fails → `maintenance:
unknown`; installer refuses with a reason and a non-zero exit); empty (no register → no band; no
notice → no toast); loading (the band draws the register row at once and adds maintenance when the
script answers).

## Destructive suite (per function, sized to its input domain)

| Function | Partitions | Floor |
|---|---|---|
| fail-open classify | announce text, crash text, ordinary context, empty array, undefined, a near miss ("allowed" lower case), a notice embedded mid-text, a very long cause | 8 |
| deny classify | `BLOCKED —` deny, other deny, no deny, multi-line, over 160 chars, empty string | 6 |
| register row | `[/]` first, only `[ ]`, `[!]` skipped, all `[x]`, no Specs section, CRLF, a checkpoint row, rows in history ignored | 8 |
| maintenance parse | two due, none due ("nothing"), garbage, empty, non-zero exit | 5 |
| installer | fresh install, re-install over own folder, foreign folder refused, uninstall own, uninstall foreign refused, `--target` with a space, missing staged file | 7 |
| R6 refusal | `bash scripts/install-…-mod.sh`, `./scripts/…`, `sh …`, behind `env`; a `cat` of it is a read | 5 |
</content>
</invoke>

## Clarifications

### Session 2026-10-03

- Q: Toast duration? → A: 6000 ms for a fail-open (it means a check is off), the 4000 ms default for a
  deny.
- Q: The band on a terminal narrower than the text? → A: The text is cut to the width the surface
  gives; the row id comes first so it survives.
- Q: `Hide` permanent? → A: For the session only (`$.state`), so a new session shows it again.
- Q: Re-install when the staged source changes? → A: The installer overwrites a folder carrying its
  own marker, so `! bash scripts/install-guard-notice-mod.sh` is also the update.
- Q: A deny toast for every repeat of the same deny? → A: Once per distinct first line per session.
