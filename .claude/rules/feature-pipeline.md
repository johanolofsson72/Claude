# Feature pipeline rule (auto-trigger, end-to-end execution)

The speckit + Allium + TLA+ pipeline is **not optional** for non-trivial work. Skipping it is the single biggest quality regression in this project — it loses functional inventory, drift detection, formal invariants, and destructive test coverage all at once. This rule closes that hole.

## The contract (BLOCKING)

Every developer request that is **not** a trivial one-file fix MUST go through the pipeline. You do not need the user's permission to start it — the user authorized it by giving you the work. Starting the pipeline is the default, not the exception.

```
/specify  →  /allium:elicit  →  /plan  →  /tasks  →  /speckit.analyze  →  /implement
                                                          (auto-applies         │
                                                          all suggested         │
                                                          remediations)         ▼
                                                                 browser tests (functional + destructive)
                                                                                │
                                                                                ▼
                                                                       /tla (distill + drift + invariants)
```

`/speckit.analyze` is **mandatory** between `/tasks` and `/implement`. The hook in `.claude/settings.json` auto-applies every remediation from the analysis report and auto-chains to `/implement` without prompting. There is no stop between `/tasks` → `/speckit.analyze` → auto-apply → `/implement` — the whole sub-chain is one continuous segment of the larger pipeline.

The whole chain is **one task**. Per `continuous-execution.md` you do not stop between phases. Per `validation-followup.md` Allium and TLA+ findings get explicit per-finding decisions — those are the only legitimate stops other than genuine ambiguity or hard blockers.

## Triage — what to actually run

After `/specify` produces the spec, classify it per `specs.md` and pick the matching track. Do **not** force the full pipeline on everything — over-application produces fabricated `.allium` files that surface as false drift in `/tla`.

| Spec shape | Pipeline track |
|---|---|
| Behavior-changing (new feature, new entity, new state machine, new concurrency, new API surface) | **Full:** spec → `/allium:elicit` → impl → browser tests → `/tla` |
| UI feature, single actor, no concurrency (CRUD form, search/filter, simple linear workflow) | **Light:** spec → `/allium:elicit` → impl → browser tests (skip `/tla` unless state machine non-trivial) |
| Non-behavior (refactor, doc, dependency bump, config tweak, cosmetic, i18n, logging) | **Spec-only:** no `.allium`, no `/tla`. Browser tests still apply if user-facing surface changes. |
| Fix / hardening / security with no new entities AND no new state transitions | **Spec-only.** Express the constraint as a test, not as an Allium invariant. |

When the track is unclear, ask **once** with `AskUserQuestion` and then proceed. Do not default to "full" out of caution.

## When the pipeline is NOT required

Only these qualify as "trivial" and may skip the pipeline:

- Single-file typo, formatting fix, or whitespace change
- Renaming a single local variable
- Single-line bug fix where the wrong-value is obvious and the spec impact is zero
- Doc-only changes to comments inside one file (CLAUDE.md, README, etc. still count as doc work but typically spec-only track, not "trivial")
- Reverting a single recent commit verbatim

If you find yourself thinking "this is small enough to skip the pipeline" but the change touches 2+ files, introduces a new function, modifies state, or changes user-visible behavior — **it is not trivial**. Run the pipeline (spec-only track is fine if no new behavior).

When you skip the pipeline because the work is trivial, state that classification explicitly in your first sentence ("This is a trivial typo fix — skipping the pipeline."). That sentence is the audit trail for why the pipeline did not run.

## How this rule fires

Two enforcement layers:

1. **`UserPromptSubmit` hook** (`scripts/feature-pipeline-detect.sh`) — when your prompt contains feature-build trigger words (build, implement, add, create, refactor, fix, bygg, lägg till, skapa, ändra, ny, etc.) and is not already a pipeline command (`/specify`, `/plan`, `/tasks`, `/implement`, `/allium`, `/tla`, `speckit:*`), the hook injects a mandatory-pipeline reminder into the conversation. The reminder is non-blocking — Claude can still classify the request as trivial — but the reminder will appear on every feature-shaped prompt.

2. **This rule file** — auto-loaded each session via `.claude/rules/`. The rule is the source of truth; the hook is just the deterministic re-injection so the rule cannot be silently forgotten across long sessions.

## What this rule forbids

- Jumping straight to `Edit`/`Write` on production code for a multi-file feature without `/specify` first.
- Writing a spec without then running `/allium:elicit` on the full/light track.
- Implementing without `/plan` and `/tasks` derived from the spec (so the functional inventory is explicit before code is written).
- Writing browser tests that cover only "the happy path" — functional coverage means **every implemented function**, plus 8+ destructive scenarios across the 6 attack categories.
- Declaring "done" without running `/tla` (or stating spec-only track and why).
- Asking "should I start with /specify?" — the answer is yes for any non-trivial work; just start.

## When to stop (the only legitimate cases)

You may stop and ask during pipeline execution **only** when:

1. **Genuine ambiguity** the spec/triage cannot resolve — use `AskUserQuestion`, not free-text questions.
2. **Hard blocker** outside your control — missing credentials, missing infra, conflicting requirements that need arbitration.
3. **Allium or TLA+ findings** — these have their own per-finding decision protocol in `validation-followup.md`.

Otherwise: keep going. The pipeline is one task, not seven.

## Why this rule exists

Without it, Claude tends to short-circuit the pipeline on prompts that "feel small" or arrive without an explicit `/specify` invocation. The result is: no functional inventory (so tests cover 3 of 12 functions), no Allium baseline (so drift cannot be detected), no TLA+ invariants (so race conditions are not caught), and no destructive tests (so the feature ships brittle). Every one of those failure modes has bitten this project before. The pipeline is the deterministic fix.
