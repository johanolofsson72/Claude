# Feature pipeline rule (auto-trigger, end-to-end execution)

The speckit + Allium + TLA+ pipeline is **not optional** for non-trivial work, on web and mobile alike. Long form (version history, why each phase exists, the full pre-081 text): `.claude/docs/feature-pipeline-rationale.md`.

## The contract (BLOCKING)

Every request that is not a trivial one-file fix goes through the pipeline. You need no permission to start: the user authorized it by giving you the work.

```
/speckit-specify → SPEC INTERVIEW → /speckit-clarify → /allium:elicit → /speckit-plan → /speckit-tasks → /speckit-analyze → /speckit-implement
→ /speckit-converge (loop until it appends nothing) → /simplify → browser tests (functional + destructive) → /tla
```

- **Spec interview:** every spec, after specify, before clarify (`.claude/rules/spec-interview.md`).
- **`/speckit-clarify`:** every track. The auto-pick hook accepts recommended answers. Going straight from `specify` to `plan` is forbidden.
- **`/allium:elicit`:** full and light tracks only.
- **`/speckit-analyze`:** between tasks and implement. Its hook applies every remediation and chains to implement.
- **`/speckit-converge`:** after implement. If it appends anything, implement that and converge again. Skipped on spec-only.
- **`/simplify`:** after converge, on the changed code, before tests. Skipped on spec-only.
- **Native apps:** Maestro/Patrol/`integration_test` flows replace browser tests (`.claude/docs/testing-mobile.md`). Every phase and guard still applies.

**The spec-kit 1.0 checklist stop is not a permission gate.** Never relay "Some checklists have unchecked items. Do you want to proceed…?" in any form. Judge the items yourself: tick what is satisfied, and record real gaps in the spec and `run-log.md` for the status summary. `scripts/speckit-extension-policy.sh` rewrites the stop out after every `specify init`.

Use the hyphenated skills (`/speckit-specify` … `/speckit-converge`). `/speckit-taskstoissues` is not used. spec-kit is pinned in `scripts/speckit-version`; `bash scripts/speckit-sync.sh` brings it in line.

The whole chain is **one task** (`.claude/rules/continuous-execution.md`). Allium and TLA+ findings get per-finding decisions (`.claude/rules/validation-followup.md`).

## Triage — what to run

| Spec shape | Track |
|---|---|
| Full-track spec that crosses a risk threshold (auth/payments/PII/upload/new external surface, state machine/concurrency, new entity or ≥6 files, or tagged) | **Full + hardened** (`.claude/rules/spec-hardening.md`) |
| Behaviour-changing (new feature, entity, state machine, concurrency, API surface) | **Full:** … → `/allium:elicit` → … → browser tests → `/tla` |
| UI feature, single actor, no concurrency | **Light:** as full, skip `/tla` unless the state is non-trivial |
| Non-behaviour (refactor, docs, deps, config, cosmetic, i18n, logging), or a fix with no new entities or transitions | **Spec-only:** spec → interview → clarify → impl. No `.allium`, no `/tla` |

When the track is unclear, ask **once** with `AskUserQuestion`, then proceed.

## When the pipeline is NOT required

A single-file typo, formatting or whitespace change; renaming one local variable; a one-line obvious bug fix with no spec impact; comment-only changes in one file; reverting one recent commit verbatim. Anything touching 2+ files, adding a function, changing state or changing user-visible behaviour is not trivial. When you skip, say so in your first sentence.

## Enforcement

`scripts/feature-pipeline-detect.sh` (reminder), `spec-interview-guard`, and `pipeline-state-guard`. The last two hard-block source edits until the active spec has `interview.md` (≥15 answers, plus confirmed acceptance cases on full/hardened specs), `spec.md` with `## Clarifications`, `spec.allium` (full/light), `plan.md` and `tasks.md`.

## Forbidden

Editing production code for a multi-file feature without `/speckit-specify`. Skipping clarify, the interview, `/allium:elicit` (full/light), or plan + tasks. Inventing answers to genuinely ambiguous questions. Happy-path-only tests. Declaring done without `/tla` (or saying it is spec-only and why). Asking "should I start with /speckit-specify?".

## When to stop

Only for genuine ambiguity (`AskUserQuestion`), a hard blocker outside your control, or Allium/TLA+ findings. Otherwise keep going.
