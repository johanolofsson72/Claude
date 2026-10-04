# Spec interview rule (per-spec anti-drift interview — auto by default, human on flag, hard-gated)

Every spec carries a 15–25 question interview in `<spec-dir>/interview.md`, run right after `/speckit-specify` and before `/speckit-clarify`, on **every** track. It pins down where AI implementations drift: scope, data shape, edge cases, error/empty/loading states, authorization, integrations, non-goals. Long form (the 15 question categories, the artifact example, reasoning, the full pre-099 text): `.claude/docs/spec-interview-rationale.md`.

## Two modes

- **AUTO (default).** Claude auto-answers the base 15–25 with the **recommended** option, tagged `**A (auto):**`. **Escalate** a question with no defensible recommendation via `AskUserQuestion` (auto-pick OFF), recorded as `**A:**`. **Human overflow** on large/advanced specs: questions beyond the base, answered by the developer.
- **MANUAL (opt-in).** `SPEC_INTERVIEW_MODE=manual`: every question human-answered via `AskUserQuestion`, one per turn; only `**A:**` counts.

**The flag (AUTO).** The hardened triggers (`.claude/rules/spec-hardening.md`) are the strong prior for large/advanced; such a spec should almost always get overflow questions. Bias toward asking. On a hardened spec the overflow includes threat-surface questions (authz, input tampering, information disclosure, resource exhaustion). Override per spec: `[interview:manual]` on the row → fully human; `[interview:auto]` → no overflow. Claude proposes, the developer disposes.

## Hard-gated

`scripts/spec-interview-guard-hook.sh` denies every source edit for the active spec until `interview.md` records **≥ 15 answered questions** (AUTO counts `**A:**` + `**A (auto):**`, MANUAL only `**A:**`). 15 is the floor (`SPEC_INTERVIEW_MIN`), 25 is guidance. The header line is `Mode: AUTO` or `Mode: MANUAL`; each question is `## Q<n> — <topic>` with a `**Q:**` line and a non-empty answer line.

## Acceptance cases — full and hardened specs (BLOCKING)

A full-track spec, or any `[hardened]` row, also carries `<spec-dir>/acceptance.md`: 3–5 cases, each `## AC-<n> — <title>` with `**Given**` / `**When**` / `**Then**`. Claude drafts them; the developer confirms in one `AskUserQuestion` showing `bash scripts/acceptance-cases.sh --question <spec-dir>` (option `Confirm`), then `--confirm <spec-dir> --quote "Confirm"`. Never confirm for the developer. Unconfirmed or edited cases deny every source edit; then tests unlock, and production once a test names every case `<spec-id>-AC-<n>`. Exempt: light, spec-only, checkpoint rows. `SPEC_ACCEPTANCE=off` disables it.

The interview sits in the same continuous task: no "ready to implement?" stop after it. Surprising or contradictory answers are findings (`.claude/rules/validation-followup.md`).

## Forbidden

Editing source with < 15 counted answers (calling real work "trivial" to route around it). AUTO: inventing a recommended answer for a genuinely ambiguous, spec-affecting question instead of escalating, or silently auto-answering a large/advanced spec without overflow unless overridden. MANUAL: expecting `**A (auto):**` to unlock code. Dumping all questions in one message (one per turn; 2–3 tightly related trivial ones may share). Treating the project-wizard interview as a substitute.
