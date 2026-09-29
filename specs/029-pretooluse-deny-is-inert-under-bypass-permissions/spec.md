# 029 — pretooluse-deny-is-inert-under-bypass-permissions

## Problem

The row, as filed from rocky's checkpoint H13 on 2026-09-05: five PreToolUse guards return
`permissionDecision: deny` when fed a payload on stdin, yet the identical live `Edit` goes through.
The row blamed the permission mode, since those sessions run `bypassPermissions`.

## What the evidence says

The permission mode is not the cause. Measured live on 2026-09-29 (Claude Code 2.1.284), in
`bypassPermissions`, one `Edit`, one hook, one field changed:

| hook payload | live `Edit` |
|---|---|
| `{hookSpecificOutput:{permissionDecision:"deny",…}}` | went through |
| `{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",…}}` | blocked |

The template's own `spec-register-guard` also blocked a live `Edit` in this session, and this
session runs `bypassPermissions` (`.claude/settings.json` `defaultMode`).

rocky measured the defect spec 046 fixed a week later: every PreToolUse deny omitted
`hookEventName`, and the CLI drops a `hookSpecificOutput` without it. The PostToolUse detector
"bit" because its channel did not depend on that field. All 46 repos under `~/repos` that carry
the guards now carry the fixed copies (scanned 2026-09-29).

So the guarantee holds, and the rules that call these guards hard blocks are correct. What
remains is the reason rocky's probe was fooled. It is still there.

## The residual defect

Every guard test decodes the verdict the way rocky's probe did. It reads
`.hookSpecificOutput.permissionDecision` and ignores the discriminator. Five test files and
eleven assertions do this (`test-pipeline-hooks.sh`, `test-core-machinery-guard.sh`,
`test-core-owed-tick-guard.sh`, `test-active-spec-resolution.sh`, `test-bash-write-guard.sh`). None
of them checks `hookEventName`. Against the pre-046 guards every one of them passes. A guard test
that accepts a payload the CLI discards is how a week of inert guards looked correct.

046's static gate (`test-hook-channels.sh` §2) checks each file only for whether
`hookEventName` appears *anywhere* in it. A file with three deny sites and one bare one passes.

The static checks also cannot see the other half of the contract, which is the CLI's behaviour.
Whether a well-formed deny holds in every permission mode depends on the installed Claude Code
version, and no script in the template asks it.

## Requirements

- **R1 — one reader that decodes the way the CLI does.** `scripts/hook-verdict.sh` provides
  `hook_verdict <json>`, which prints `deny` / `ask` / `allow` when the payload is a well-formed
  PreToolUse decision, `dropped` when `hookSpecificOutput` exists but its `hookEventName` is not
  `PreToolUse`, `none` for empty or no decision, and `invalid` for non-JSON.
- **R2 — every guard test decodes through that rule.** The jq-based tests call `hook_verdict`.
  The python decoders apply the same rule and print `DROPPED` for a payload without the
  discriminator. A bare deny reads as not-a-deny, so the test goes red.
- **R3 — per-emit-site static check.** Every line that emits a `permissionDecision` (jq or
  heredoc JSON, in `scripts/*.sh` and in the inline hooks of `.claude/settings.json`) carries
  `hookEventName` in the same object. Readers (`jq -r`) and comments are exempt.
- **R4 — sabotage arms.** The gate proves it bites. A guard copy with the field stripped reads
  `dropped` through R1, an emit line without the field fails R3, and a python decoder fed the
  bare shape prints `DROPPED`.
- **R5 — a live probe of the CLI.** `scripts/probe-live-deny.sh` runs the A/B above against the
  installed `claude`, in `acceptEdits` and `bypassPermissions`, in a throwaway repo. It reports
  exit 0 when the well-formed deny blocks and the bare one passes in every mode, 1 when a
  well-formed deny is not applied, 3 when the control arm is blocked too (the probe cannot
  discriminate, so it proves nothing), and 2 when the CLI is missing. It is opt-in and never runs
  in a default suite, because it spends model calls. Rerun it after a CLI upgrade.
- **R6 — correct the record.** The register row and its pending diagnosis are rewritten to what
  was measured. `.claude/docs/workflows.md` names the probe next to its claim that hooks still
  fire under skip-permissions.

## Threat model

Trust boundary: hook stdout → Claude Code's hook reader. This spec adds no runtime surface. It
adds tests and one opt-in script that runs `claude -p` in a temp dir.

- **Spoofing** — n/a. No identity crosses the boundary.
- **Tampering** — a guard edited to drop the field silently turns a block into advice. R2 and R3
  catch it, and R4 proves they do. A test edited to decode leniently again is caught by R4's arm
  on the shared reader.
- **Repudiation** — n/a.
- **Information disclosure** — the probe runs in a `mktemp -d` repo with a fixed prompt and no
  project content, so nothing from the project reaches the model call.
- **Denial of service** — the probe is bounded by a per-arm `timeout`, refuses to run without
  one (exit 3), and runs only on demand. A hung CLI ends as exit 3 (inconclusive), never as a pass.
- **Elevation of privilege** — the probe passes `--permission-mode bypassPermissions` to a
  child CLI. A prompt does not confine anything, so the probe relies on flags: `--tools Edit Read`
  (no shell to fall back to after a deny), `--setting-sources ""` (no user or project settings,
  hooks or plugins), `--strict-mcp-config` (no MCP servers), and a `--settings` file that carries
  only the probe hook. `bypassPermissions` has no path sandbox, so Edit could in principle reach
  outside the temp repo. The residual risk is a model editing another file on a one-line
  instruction, and the prompt names one relative path.
- **False assurance** (the threat this spec exists for) — an arm counts as "held" only when the
  hook left its marker file and the CLI exited 0. An auth failure, a rate limit, a model that
  never called Edit, or an interrupt reads as inconclusive, never as a pass.

## Non-goals

- Changing any guard's logic. Their verdicts were right, and 046 fixed their shape.
- Scheduling the live probe. Its cost is model calls; F-finding if cadence is wanted.
- The four repos without the inline sensitive-file rule (ighweld, learnways-e-autism,
  learnways-sll…, learnways-stillhetsgrejen). Cross-project observation, notify only.

## Acceptance

1. `hook_verdict` returns `dropped` for the pre-046 shape and `deny` for the current one.
2. Every guard test is green, and each goes red when its guard emits the bare shape (spot-checked
   by sabotage on at least two guards).
3. `test-hook-channels.sh` fails on a synthetic bare emit line and passes on the repo.
4. `probe-live-deny.sh` exits 0 on this machine.

## Clarifications

### Session 2026-09-29

- Q: Repair the guarantee or correct the claim (the row's own scope question)? → A: Neither is
  needed. The guarantee holds, proven live under `bypassPermissions`, and the claim is true. The
  work is making the tests unable to be fooled again.
- Q: Track? → A: spec-only [hardened]. There are no new entities or state transitions, and the
  row's `[hardened]` tag is kept. It was filed as full track on the misdiagnosis.
- Q: Should the live probe cover `default` mode? → A: No. Headless `-p` in default mode denies the
  control edit for want of a prompt, so the arm could not discriminate. `acceptEdits` and
  `bypassPermissions` both auto-allow edits, so the hook is the only thing that can stop it.
