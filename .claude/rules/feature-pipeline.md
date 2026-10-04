# Feature pipeline rule (auto-trigger, end-to-end execution)

The speckit + Allium + TLA+ pipeline is **not optional** for non-trivial work, on web and mobile alike. Long form (version history, why each phase exists, the full pre-081 and pre-099 text): `.claude/docs/feature-pipeline-rationale.md`.

## The contract (BLOCKING)

Every request that is not a trivial one-file fix goes through the pipeline. You need no permission to start: the user authorized it by giving you the work.

```
/speckit-specify → SPEC INTERVIEW → /speckit-clarify → /allium:elicit → /speckit-plan → /speckit-tasks → /speckit-analyze → /speckit-implement
→ /speckit-converge (loop until it appends nothing) → /simplify → browser tests (functional + destructive) → /tla
```

- **Spec interview** on every spec (`.claude/rules/spec-interview.md`). **`/speckit-clarify`** on every track (the auto-pick hook accepts recommended answers); specify → plan directly is forbidden. **`/allium:elicit`** on full and light only.
- **`/speckit-analyze`** between tasks and implement; its hook applies every remediation and chains to implement. **`/speckit-converge`** after implement, repeated until it appends nothing; then **`/simplify`** on the changed code. Both skipped on spec-only.
- **Native apps:** Maestro/Patrol/`integration_test` flows replace browser tests (`.claude/docs/testing-mobile.md`).
- **The spec-kit checklist stop is not a permission gate.** Never relay "Some checklists have unchecked items… proceed?". Judge the items, tick what holds, record real gaps in the spec and `run-log.md`.
- Use the hyphenated skills; spec-kit is pinned (`bash scripts/speckit-sync.sh`).

The whole chain is **one task** (`.claude/rules/continuous-execution.md`). Allium and TLA+ findings get per-finding decisions (`.claude/rules/validation-followup.md`).

## Triage — what to run

| Spec shape | Track |
|---|---|
| Full-track spec that crosses a risk threshold (`.claude/rules/spec-hardening.md`) | **Full + hardened** |
| Behaviour-changing (new feature, entity, state machine, concurrency, API surface) | **Full:** … → `/allium:elicit` → … → browser tests → `/tla` |
| UI feature, single actor, no concurrency | **Light:** as full, skip `/tla` unless the state is non-trivial |
| Non-behaviour (refactor, docs, deps, config, cosmetic, i18n, logging), or a fix with no new entities or transitions | **Spec-only:** spec → interview → clarify → impl. No `.allium`, no `/tla` |

When the track is unclear, ask **once** with `AskUserQuestion`, then proceed.

## When the pipeline is NOT required

A single-file typo, formatting or whitespace change; renaming one local variable; a one-line obvious bug fix with no spec impact; comment-only changes in one file; reverting one recent commit verbatim. Anything touching 2+ files, adding a function, changing state or changing user-visible behaviour is not trivial. When you skip, say so in your first sentence.

## Enforcement

`spec-interview-guard` and `pipeline-state-guard` hard-block source edits until the active spec has `interview.md` (plus confirmed acceptance cases on full/hardened), `spec.md` with `## Clarifications`, `spec.allium` (full/light), `plan.md` and `tasks.md`.

## Forbidden

Editing production code for a multi-file feature without `/speckit-specify`. Skipping clarify, the interview, `/allium:elicit` (full/light), or plan + tasks. Inventing answers to genuinely ambiguous questions. Happy-path-only tests. Declaring done without `/tla` (or saying it is spec-only and why). Asking "should I start with /speckit-specify?". Stopping anywhere but a legitimate stop (`.claude/rules/continuous-execution.md`).
