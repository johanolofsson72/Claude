# 046 — hook output channels

## Problem

Claude Code gives a hook three ways to speak, and the template used them
backwards in both directions.

**Backwards one — advisories shouted at the developer.** Every reminder hook
emitted `systemMessage`, which the CLI's own reference defines as *"Warning
shown to user in UI"*. The UI renders one notification per line. So a 26-line
register-orientation brief written for Claude arrived as 26 red warnings at
every `/clear`, and a per-edit reminder repeated on every pass over the same
file until it was wallpaper. Measured on ighweld-2026: 3.1 KB of warning text
at session start, before a word of work.

**Backwards two — instructions that reached nobody.** 42 hooks emitted a
top-level `additionalContext`, which Claude Code silently ignores (*"Did you
mean hookSpecificOutput.additionalContext (with a hookEventName)?"*). Four were
wired as UserPromptSubmit hooks, so enforcement layer 1 of
`.claude/rules/feature-pipeline.md` had never said anything since it was
written.

**Backwards three — the one that matters.** `hookSpecificOutput` requires
`hookEventName`; it is the schema's discriminator. Six PreToolUse guards and
the inline sensitive-file rule omitted it, so every deny was dropped whole.

Proven live 2026-09-12, A/B on one file with one field changed:

| payload | result |
|---|---|
| `{hookSpecificOutput:{permissionDecision:"deny",…}}` | edit **succeeded** |
| `{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",…}}` | edit **blocked** |

Every `(BLOCKING)` hard block in `CLAUDE.md` was therefore advisory, including
the rule that blocks reads of `~/.ssh`, `~/.aws` and `.env`. This is the half
nothing could have noticed: a guard that silently permits and a guard with
nothing to stop produce identical transcripts.

## Root cause

Each hook picked its own channel at its own call site, and no test could tell a
right pick from a wrong one. `.claude/docs/workflows.md` listed
`additionalContext` as a top-level field, so hooks written from the docs were
wrong by construction.

## Scope

IN: one shared emitter (`scripts/hook-notice.sh`); every hook converted to it;
`hookEventName` on every nested payload; once-per-session de-duplication;
the `specs/INDEX.md` false positive in the spec-coverage reminder; the
`after_specify` branch nag that contradicts the solo/direct-push rule; a GC for
the scratch the harness leaves on disk; the docs table that taught the bug; a
regression gate.

OUT: the local-LLM hooks stay unwired (register row 020 owns that decision) —
their payloads are corrected, not enabled.

## Acceptance

1. No hook emits a top-level `additionalContext`.
2. Every emitted `hookSpecificOutput` carries `hookEventName`.
3. No advisory hook uses `systemMessage`; the allowlist is the four that carry
   real news for a person.
4. A `systemMessage` is one line.
5. A PreToolUse deny actually denies (verified live, not asserted).
6. The same reminder fires once per session per file.
7. The spec-coverage reminder is silent on the register and its archives, and
   still fires on a real `spec.md`.
8. The GC removes TLC scratch and stale attempt fingerprints, and removes
   neither a source directory named `states/` nor a hand-written `.tla` model.
9. `scripts/test-hook-channels.sh` and `scripts/test-pipeline-hooks.sh` green.

## Functional coverage

| # | Function | Test |
|---|---|---|
| 1 | `notice_model` shape | test-hook-channels 5 |
| 2 | `notice_user` one-line collapse | test-hook-channels 4 |
| 3 | `notice_once` de-duplication | test-hook-channels 7 |
| 4 | no-session-id never suppresses | test-hook-channels 7 |
| 5 | JSON escaping (quote / backslash / tab / newline) | test-hook-channels 6 |
| 6 | no top-level additionalContext | test-hook-channels 1 |
| 7 | hookEventName on every emit | test-hook-channels 2 |
| 8 | advisory-channel allowlist | test-hook-channels 3 |
| 9 | register false positive | test-hook-channels 8 |
| 10 | GC keeps unrecognised content | test-hook-channels 9 |
| 11 | GC collects TLC scratch | test-hook-channels 9 |
| 12 | orientation hooks emit on the model channel | test-pipeline-hooks (orientation block) |
| 13 | autosync headline + detail split | test-pipeline-hooks (autosync block) |
| 14 | PreToolUse deny is honoured | live A/B, recorded above |

## Clarifications

- **Why not keep `systemMessage` for orientation?** Because it is read at every
  session start by a person who did not ask for it, and the content is a work
  instruction. The developer's channel is kept for the four hooks that report a
  side effect on disk.
- **Why de-duplicate per session rather than rate-limit?** The reminder is about
  a *file*, not about an edit. A test file written in six passes needs the
  reminder once.
- **Why no session id means no suppression.** A hook run by hand or by a test
  has none. Losing a reminder is worse than repeating one.
- **Why the GC matches on contents, not on the name `states/`.** Two real
  directories on this machine carry that name and are not scratch — a React
  component and a hand-written TLA+ model.
