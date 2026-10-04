# feature-pipeline — long form (rationale, history, examples)

> Reference, loaded on demand — never @-import it. The always-loaded contract is
> `.claude/rules/feature-pipeline.md`; if the two ever disagree, the rule governs and this file is the one to fix.
> Below is the full text of the rule as it stood before spec 073 (R8) split it, headings intact, so
> every section a hook or doc cites by name is still reachable here.

---


The speckit + Allium + TLA+ pipeline is **not optional** for non-trivial work. Skipping it is the single biggest quality regression in this project — it loses functional inventory, drift detection, formal invariants, and destructive test coverage all at once. This rule closes that hole.

> **Platform-neutral — EVERY spec runs the full speckit pipeline, web or mobile (non-negotiable).** This pipeline is identical for web/.NET (client-server) and native mobile (React Native / Expo · Flutter). Where this rule and its diagram say "browser tests", a native app substitutes Maestro/Patrol/`integration_test` flows + component/widget tests — see `.claude/rules/specs.md` and `.claude/docs/testing-mobile.md`. Every phase (specify → clarify → allium:elicit → plan → tasks → analyze → implement → tests → tla) and every enforcement hook fires on mobile too: `pubspec.yaml` is a recognized language marker (alongside `package.json` for RN), and the test hooks match `npm test`/`maestro`/`flutter test`/`patrol`.
>
> The "always via speckit" guarantee is deterministic, not advisory — three `PreToolUse` guards block source edits (`.dart`, `.tsx`, …) until the artifacts exist: **`spec-register-guard`** denies the edit until `specs/INDEX.md` and a spec row exist, **`pipeline-state-guard`** denies it until that spec has `spec.md` (with a `## Clarifications` section), `spec.allium` (full/light), `plan.md`, and `tasks.md`, and **`spec-interview-guard`** denies it until that spec's `interview.md` records ≥15 answered questions (the anti-drift interview — base auto-answered by default, human on flag; `.claude/rules/spec-interview.md`). There is no bypass for mobile — a Flutter `lib/` edit is blocked exactly like a `.cs` edit. Mobile gets the same teeth as client-server.

## The contract (BLOCKING)

Every developer request that is **not** a trivial one-file fix MUST go through the pipeline. You do not need the user's permission to start it — the user authorized it by giving you the work. Starting the pipeline is the default, not the exception.

```
/speckit-specify  →  SPEC INTERVIEW  →  /speckit-clarify  →  /allium:elicit  →  /speckit-plan  →  /speckit-tasks  →  /speckit-analyze  →  /speckit-implement
                (15–25 Q, base       (auto-pick     (full/light                              (auto-applies         │
                 AUTO-answered w/     recommended,   tracks only)                             all suggested         │
                 recommended;         residual                                                remediations)         ▼
                 human overflow if                                                              /speckit-converge
                 flagged; every spec)  only)                                          (unbuilt work → tasks.md; loop
                                                                                       back to implement if any)
                                                                                             │
                                                                                             ▼
                                                                                            /simplify
                                                                                  (quality-only pass on the
                                                                                   changed code; no bug hunt)
                                                                                             │
                                                                                             ▼
                                                                                    browser tests (functional + destructive)
                                                                                             │
                                                                                             ▼
                                                                                    /tla (distill + drift + invariants)
```

**`/speckit-converge` is mandatory after `/speckit-implement`** (spec-kit 0.16+). It assesses the codebase against the spec, plan and tasks, and appends any remaining unbuilt work to `tasks.md`. If it appends anything, go back and implement it — then converge again, until it appends nothing. This is the phase that catches "the spec described twelve behaviours and nine got built", which is the same failure the functional-coverage inventory exists to prevent, caught one stage earlier and mechanically rather than by eye. It complements `/allium:distill` (semantic drift between spec and code) by working at task granularity. Skip only on the spec-only track.

**After converge stops appending, run `/simplify` on the changed code.** It is a built-in, quality-only pass — reuse,
simplification, efficiency, altitude — and it does not hunt for bugs, so it never substitutes for `/code-review` or the test
matrix. It exists in this chain because "Simplicity — minimum necessary complexity" is priority 3 in `CLAUDE.md` and nothing else
in the pipeline enforces it: converge proves the work is *complete*, the tests prove it is *correct*, and neither notices that a
behaviour got built three times in three shapes. Run it before the test phase, so the tests are written against the code that will
actually ship rather than against a draft you are about to restructure. Skip on the spec-only track.

> **spec-kit is pinned (spec 073, 2026-09-28).** `scripts/speckit-version` holds one tag (v1.0.12 at the time of writing) and
> `scripts/speckit-sync.sh` is the only installer. Before that, `/project-wizard` and `/project-update` installed from
> `git+https://github.com/github/spec-kit.git` — whatever `main` was that day — and the projects ended up on untagged
> 1.0.2.dev0 and 1.0.5.dev0 snapshots, so two developers could run different phases without knowing it.
>
> **spec-kit 1.0 (released 2026-08-21) — what changed for us.** A project updated after 2026-08-21 lands on
> **1.0.x** and one updated before it stays on 0.16.x. Verify with `.specify/init-options.json` → `speckit_version`. Three
> consequences:
>
> 1. **Extensions are opt-in (`--extension`), not default-on.** The git extension no longer re-enables itself on every
>    `specify init --force`, and a 1.0 project has no `.specify/extensions/` at all. `scripts/speckit-extension-policy.sh` is
>    therefore a **confirmation** on 1.0.x rather than a repair — it exits silently when there is no registry. Keep running it:
>    0.16.x projects still exist (rocky carries five neutralized `speckit-git-*` skills) and it is the only thing holding them.
> 2. **`/speckit-specify` now maintains a built-in `checklists/requirements.md`.** That is spec-kit's own requirements-quality
>    checklist, distinct from the optional `/speckit-checklist` artifacts and from this project's `spec-testing-checklist.md`.
> 3. **`/speckit-implement` halts on unchecked checklist items** — see the override immediately below, because as shipped it
>    breaks a BLOCKING rule.
>
> **Override (BLOCKING) — the 1.0 checklist stop is not a permission gate.** `/speckit-implement` counts unchecked items across
> the checklists and, when any are unchecked, instructs: *"STOP and ask: Some checklists have unchecked items. Do you want to
> proceed with implementation anyway? (yes/no)"*. That is precisely the anti-pattern `.claude/rules/continuous-execution.md`
> forbids — a permission-check mid-pipeline on work the developer already authorized. **Do not ask it.** Instead:
>
> - **Read the unchecked items and judge them.** Tick the ones already satisfied.
> - **Record the rest; do not stop for them.** An unchecked item that names a real gap — a missing acceptance criterion, an
>   unanswered authorization question, an absent error state — goes into the spec and into `<spec-dir>/run-log.md`, and is
>   reported in the **per-spec status summary**. That summary is the one stop this pipeline has (`.claude/rules/spec-register.md`),
>   and it is where the developer sees what was left unchecked — after the work, not instead of it.
> - **Never relay the prompt, in any form.** Not as a yes/no question, and not converted into an `AskUserQuestion`. There is no
>   version of this gate that is allowed to halt the run.
>
> This is enforced deterministically, not just in prose: `scripts/speckit-extension-policy.sh` rewrites the STOP block in
> `speckit-implement/SKILL.md` (and the `_[Wait for user response]_` line in `speckit-specify/SKILL.md`) after every
> `specify init`, stamping a marker so re-runs are no-ops. It fires on the verbatim upstream text and, when spec-kit changes its
> wording, warns instead of half-editing — at which point this rule is what governs.
>
> The stop lives in spec-kit's own SKILL.md, which `specify init --force` regenerates on every update, so patching that file does
> not survive — the same lesson the git extension taught. This rule is the durable override.

> **Command names (spec-kit v0.10.0+ — **1.0.2 as of August 2026**, see the 1.0 note above — with `--integration claude`).** The hyphenated skill names below have been stable since the v0.10 line; v0.11–v0.14 normalized hyphenation across integrations, moved Claude Code files from `.claude/commands/` to `.claude/skills/`, and added a `py` script type (v0.14.0) alongside `sh`/`ps`. The install commands in `/project-wizard` and `/project-update` pull from `git+…/spec-kit.git` (i.e. whatever `main` is that day) — pin a tag (`uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.14.2`) when two developers need identical phases.
>
> **Skill names.** `specify init` installs these phases as **skills** with hyphenated names: `/speckit-specify`, `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze`, `/speckit-implement` (plus `/speckit-constitution` and `/speckit-checklist`). Earlier spec-kit used bare `/specify` etc. — those no longer match the installed skills, so always use the `/speckit-` prefix. `/allium:elicit` and `/tla` are this project's OWN skills (not spec-kit) and keep their names.
>
> **Other phases 0.16.2 installs, and what we do with them:** `/speckit-converge` is **in** the chain (above). `/speckit-agent-context-update` refreshes the managed Spec Kit section of the agent context file — harmless, run it when that section goes stale. `/speckit-taskstoissues` converts tasks into GitHub issues and is **not used**: these are solo, direct-push projects with no issue workflow (`.claude/rules/project-workflow.md`), and it adds GitHub surface for nothing. The five `speckit-git-*` skills are disabled per the extension policy above.
>
> **Two spec-kit phases sit outside the per-spec blocking chain above:**
> - **`/speckit-constitution`** — establishes the project's principles. Runs **once at project init** (the `/project-wizard` skill generates the constitution), not per spec. Re-run only when amending principles.
> - **`/speckit-checklist`** — generates a requirements quality-checklist for a spec, after `/speckit-clarify`. **Optional** here: this project already enforces a stronger destructive-test checklist (`spec-testing-checklist.md`) plus Allium invariants, so `/speckit-checklist` is available as an extra gate but not mandatory. Use it on a large/ambiguous spec where a requirements sanity pass adds value.

The **spec interview** is **mandatory** immediately after `/speckit-specify`, on **every** spec regardless of track, and runs **before** `/speckit-clarify`. It is a 15–25 question anti-drift interview recorded in `<spec-dir>/interview.md`, and the `spec-interview-guard` PreToolUse hook hard-blocks source-code edits until it records ≥15 answered questions. **By default (AUTO mode) Claude auto-answers the base** with the recommended option for each (tagged `**A (auto):**`), escalating only genuinely-ambiguous questions to the developer via `AskUserQuestion`, and — when it judges the spec **large/advanced** (the hardened triggers are the strong prior) — asking the developer the **overflow** questions the complexity demands. The developer can override per spec (`[interview:manual]` / `[interview:auto]`), and a project can force fully-human answering with `SPEC_INTERVIEW_MODE=manual`. See `.claude/rules/spec-interview.md`. The interview's answers then feed clarify, plan, tasks, and the Allium elicitation — it is part of the same uninterrupted task, with no "ready to implement?" stop after it.

`/speckit-clarify` is **mandatory** immediately after `/speckit-specify` on every track. The auto-pick hook in `.claude/settings.json` accepts the recommended answer for every clarification question without prompting (and only falls back to `AskUserQuestion` for the rare question with no defensible recommendation). It is the canonical speckit phase that catches under-specified requirements before `/speckit-plan` and `/speckit-tasks` lock them in — running `/speckit-specify → /speckit-plan` directly is the single most common pipeline-skip failure mode and it is forbidden.

`/speckit-analyze` is **mandatory** between `/speckit-tasks` and `/speckit-implement`. The hook in `.claude/settings.json` auto-applies every remediation from the analysis report and auto-chains to `/speckit-implement` without prompting. There is no stop between `/speckit-tasks` → `/speckit-analyze` → auto-apply → `/speckit-implement` — the whole sub-chain is one continuous segment of the larger pipeline.

The whole chain is **one task**. Per `continuous-execution.md` you do not stop between phases. Per `validation-followup.md` Allium and TLA+ findings get explicit per-finding decisions — those are the only legitimate stops other than genuine ambiguity or hard blockers.

## Triage — what to actually run

After `/speckit-specify` produces the spec, classify it per `specs.md` and pick the matching track. Do **not** force the full pipeline on everything — over-application produces fabricated `.allium` files that surface as false drift in `/tla`.

| Spec shape | Pipeline track |
|---|---|
| **Hardened** (full-track AND crosses a risk threshold — auth/payments/PII/upload/new external surface, full-track state machine/concurrency, new entity or ≥6 files, or explicitly tagged) | **Hardened:** the full track **plus** the four hardening additions — threat-model pass, expanded destructive + stress, hard mutation-kill gate, adversarial review. See `.claude/rules/spec-hardening.md`. |
| Behavior-changing (new feature, new entity, new state machine, new concurrency, new API surface) | **Full:** spec → `/speckit-clarify` → `/allium:elicit` → impl → browser tests → `/tla` |
| UI feature, single actor, no concurrency (CRUD form, search/filter, simple linear workflow) | **Light:** spec → `/speckit-clarify` → `/allium:elicit` → impl → browser tests (skip `/tla` unless state machine non-trivial) |
| Non-behavior (refactor, doc, dependency bump, config tweak, cosmetic, i18n, logging) | **Spec-only:** spec → `/speckit-clarify` → impl. No `.allium`, no `/tla`. Browser tests still apply if user-facing surface changes. |
| Fix / hardening / security with no new entities AND no new state transitions | **Spec-only.** spec → `/speckit-clarify` → impl. Express the constraint as a test, not as an Allium invariant. |

The **spec interview** (15–25 questions → `interview.md`, base AUTO-answered with recommended, human overflow when flagged) and `/speckit-clarify` (auto-pick) both run on **every** track — not just full/light; the interview is the deliberate pass over the spec, clarify mops up residual trivia. `/allium:elicit` is the step that varies by track. **Hardened is full + a surcharge, not a separate path** — a hardened spec runs the entire full pipeline and adds the four checks; mark its register row `full track [hardened]`.

When the track is unclear, ask **once** with `AskUserQuestion` and then proceed. Do not default to "full" out of caution. (The cross-spec **integration-hardening checkpoint** — every 5 completed specs — is a register row, not a per-spec track; see `.claude/rules/spec-hardening.md`.)

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

Four enforcement layers — the first two are a reminder hook and this rule (the source of truth); the last two are the hard `PreToolUse` blocks (interview-guard and state-guard, alongside the spec-register guard described in `.claude/rules/spec-register.md`):

1. **`UserPromptSubmit` reminder hooks** (`scripts/feature-pipeline-detect.sh` + the three speckit-command hooks wired through `scripts/pipeline-trigger-match.sh`) — when your prompt contains feature-build trigger words or a clean invocation of a speckit command (`/speckit-specify`, `/speckit-clarify`, `/speckit-analyze`, etc.), the hook injects a pipeline reminder into the conversation. The reminder is non-blocking. The trigger matcher anchors to line-start and strips quoted regions (markdown code blocks, blockquotes, table cells, Claude transcript bullets, pipeline-flow diagrams) so pasted transcripts that *mention* a command do not fire the hook. Test harness: `bash scripts/test-pipeline-hooks.sh`.

2. **This rule file** — auto-loaded each session via `.claude/rules/`. The rule is the source of truth; the reminder hooks are deterministic re-injection so the rule cannot be silently forgotten across long sessions.

3. **`PreToolUse` interview-guard hook** (`scripts/spec-interview-guard-hook.sh`) — a second **hard block**, sibling to the state-guard. On every `Edit`/`Write`/`MultiEdit` against a source-code file it walks to the project root, finds the active spec in `specs/INDEX.md`, and counts answered questions in that spec's `interview.md`. Fewer than 15 → `permissionDecision: deny` with instructions to run the interview. In the default AUTO mode it counts both auto (`**A (auto):**`) and human (`**A:**`) answers; with `SPEC_INTERVIEW_MODE=manual` it counts only human answers. Same scope rules as the state-guard (source extensions only; markdown/config/`.claude/**`/`scripts/**`/`specs/**` pass through; silent on template/scratch repos; fails open). See `.claude/rules/spec-interview.md`.

4. **`PreToolUse` state-guard hook** (`scripts/pipeline-state-guard-hook.sh`) — this is the **hard block**. On every `Edit` / `Write` / `MultiEdit` against a source-code file, the hook walks up to the project root, reads `specs/INDEX.md` to find the active spec (`- [/]` row or first `- [ ]` row), parses the track from the row, and verifies that the required artifacts exist in the spec directory (`spec.md` with a `## Clarifications` section, `spec.allium` on full/light tracks, `plan.md`, `tasks.md`). If any required phase is missing, the hook returns `permissionDecision: deny` with a phase-by-phase deny reason. The block scope is strictly source-code extensions — markdown, config, `.claude/**`, `scripts/**`, and `specs/**` edits remain allowed so the pipeline can produce its artifacts. The hook is silent on template/scratch repos (no language marker at the `.git` root) and fails open on internal errors.

## What this rule forbids

- Jumping straight to `Edit`/`Write` on production code for a multi-file feature without `/speckit-specify` first.
- Skipping `/speckit-clarify` after `/speckit-specify`. The auto-pick hook makes it zero-cost when the spec has no real gaps; running `/speckit-specify → /speckit-plan` directly is the canonical pipeline-skip failure mode this rule exists to prevent.
- Skipping the **spec interview** entirely. Every spec carries a 15–25 question interview in `interview.md` before source code is touched, and the `spec-interview-guard` hook blocks source edits until it is done. In AUTO mode Claude auto-answers the base with recommended options but MUST still (a) escalate genuinely-ambiguous, spec-affecting questions to the developer rather than inventing a "recommended" answer, and (b) ask the developer the overflow questions when it judges the spec large/advanced — silently auto-answering a risky spec is exactly the drift this gate exists to stop. See `.claude/rules/spec-interview.md`.
- Writing a spec without then running `/allium:elicit` on the full/light track.
- Implementing without `/speckit-plan` and `/speckit-tasks` derived from the spec (so the functional inventory is explicit before code is written).
- Writing browser tests that cover only "the happy path" — functional coverage means **every implemented function**, plus a **destructive suite per interactive UI function, sized to its input domain** (not a flat quota, not one batch per spec) across the relevant attack categories, plus **unit + integration tests** underneath. The **mutation kill rate** (Stryker, nightly/on-demand) is what proves the suite actually bites.
- Declaring "done" without running `/tla` (or stating spec-only track and why).
- Asking "should I start with /speckit-specify?" — the answer is yes for any non-trivial work; just start.

## When to stop (the only legitimate cases)

You may stop and ask during pipeline execution **only** when:

1. **Genuine ambiguity** the spec/triage cannot resolve — use `AskUserQuestion`, not free-text questions.
2. **Hard blocker** outside your control — missing credentials, missing infra, conflicting requirements that need arbitration.
3. **Allium or TLA+ findings** — these have their own per-finding decision protocol in `validation-followup.md`.

Otherwise: keep going. The pipeline is one task, not seven.

## Why this rule exists

Without it, Claude tends to short-circuit the pipeline on prompts that "feel small" or arrive without an explicit `/speckit-specify` invocation. The result is: no functional inventory (so tests cover 3 of 12 functions), no Allium baseline (so drift cannot be detected), no TLA+ invariants (so race conditions are not caught), and no destructive tests (so the feature ships brittle). Every one of those failure modes has bitten this project before. The pipeline is the deterministic fix.

---

## The rule as it stood before spec 081

Spec 081 shortened `.claude/rules/feature-pipeline.md` to fit the 40 KB always-loaded budget. Its full text on
2026-10-01 follows, word for word, headings demoted one level.

## Feature pipeline rule (auto-trigger, end-to-end execution)

The speckit + Allium + TLA+ pipeline is **not optional** for non-trivial work. Long form (spec-kit version history, 1.0 changes, why each phase exists, enforcement internals): `.claude/docs/feature-pipeline-rationale.md`.

> **Platform-neutral — EVERY spec runs the full speckit pipeline, web or mobile (non-negotiable).** Native apps (React Native / Expo · Flutter) substitute Maestro/Patrol/`integration_test` flows + component/widget tests for "browser tests" (`.claude/rules/specs.md`, `.claude/docs/testing-mobile.md`); every phase and hook fires on mobile too (`pubspec.yaml` and `package.json` are language markers). Three `PreToolUse` guards block source edits (`.dart`, `.tsx`, `.cs`, …) until the artifacts exist — **`spec-register-guard`**, **`pipeline-state-guard`**, **`spec-interview-guard`** — with no mobile bypass.

### The contract (BLOCKING)

Every request that is **not** a trivial one-file fix goes through the pipeline. You need no permission to start it — the user authorized it by giving you the work.

```
/speckit-specify → SPEC INTERVIEW → /speckit-clarify → /allium:elicit → /speckit-plan → /speckit-tasks → /speckit-analyze → /speckit-implement
                   (15–25 Q, every   (auto-pick,       (full/light                                         (auto-applies
                    spec)             every track)      tracks only)                                        remediations)
→ /speckit-converge (loop back to implement until it appends nothing) → /simplify → browser tests (functional + destructive) → /tla
```

- **Spec interview** — mandatory on every spec, after specify, before clarify; `interview.md` ≥ 15 answers, base AUTO-answered (`.claude/rules/spec-interview.md`).
- **`/speckit-clarify`** — mandatory on every track right after the interview; auto-pick hook accepts recommended answers (falls back to `AskUserQuestion` only with no defensible recommendation). `specify → plan` directly is the canonical skip and is forbidden.
- **`/speckit-analyze`** — mandatory between tasks and implement; its hook auto-applies every remediation and auto-chains to implement. No stop in `tasks → analyze → apply → implement`.
- **`/speckit-converge`** — mandatory after implement (spec-kit 0.16+): appends unbuilt work to `tasks.md`; if it appends anything, implement it and converge again. Skip only on spec-only.
- **`/simplify`** — after converge stops appending, on the changed code, before tests (quality only; never substitutes for `/code-review` or tests). Skip on spec-only.

**Override (BLOCKING) — the spec-kit 1.0 checklist stop is not a permission gate.** `/speckit-implement` says *"STOP and ask: Some checklists have unchecked items. Do you want to proceed with implementation anyway? (yes/no)"*. **Do not ask it.** Read and judge the unchecked items; tick the satisfied ones; record real gaps in the spec and `<spec-dir>/run-log.md` and report them in the per-spec status summary. Never relay the prompt in any form, including as an `AskUserQuestion`. `scripts/speckit-extension-policy.sh` rewrites the STOP block (and the `_[Wait for user response]_` line in `speckit-specify/SKILL.md`) after every `specify init`; when upstream wording changes it warns instead, and this rule governs.

**Command names.** Use the hyphenated skills: `/speckit-specify`, `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze`, `/speckit-implement`, `/speckit-converge` (plus `/speckit-constitution` — once at project init via `/project-wizard` — and optional `/speckit-checklist`). `/allium:elicit` and `/tla` are this project's own skills. `/speckit-taskstoissues` is **not used**; the `speckit-git-*` skills are disabled by the extension policy. spec-kit is **pinned** in `scripts/speckit-version`; `bash scripts/speckit-sync.sh` brings the CLI and `.specify/` to it (`--check` to only look). Never install it from an untagged `git+…spec-kit.git`.

The whole chain is **one task** (`.claude/rules/continuous-execution.md`). Allium/TLA+ findings get per-finding decisions (`.claude/rules/validation-followup.md`).

### Triage — what to actually run

Classify after `/speckit-specify` per `specs.md`. Do not force full on everything (fabricated `.allium` files surface as false drift).

| Spec shape | Pipeline track |
|---|---|
| **Hardened** (full-track AND a risk threshold — auth/payments/PII/upload/new external surface, state machine/concurrency, new entity or ≥6 files, or tagged) | Full **plus** threat model, expanded destructive + stress, hard mutation gate, adversarial review (`.claude/rules/spec-hardening.md`). Row: `full track [hardened]`. |
| Behavior-changing (new feature, entity, state machine, concurrency, API surface) | **Full:** spec → clarify → `/allium:elicit` → impl → browser tests → `/tla` |
| UI feature, single actor, no concurrency (CRUD, search/filter, linear workflow) | **Light:** spec → clarify → `/allium:elicit` → impl → browser tests (skip `/tla` unless state machine non-trivial) |
| Non-behavior (refactor, doc, dependency bump, config, cosmetic, i18n, logging) | **Spec-only:** spec → clarify → impl. No `.allium`, no `/tla`. Browser tests if user-facing surface changes. |
| Fix / hardening / security with no new entities AND no new state transitions | **Spec-only.** Express the constraint as a test, not an Allium invariant. |

The interview and clarify run on **every** track. When the track is unclear, ask **once** with `AskUserQuestion`, then proceed. The every-5 integration checkpoint is a register row, not a track.

### When the pipeline is NOT required

Only: single-file typo/formatting/whitespace; renaming one local variable; single-line obvious bug fix with zero spec impact; comment-only doc changes inside one file; reverting one recent commit verbatim. Touching 2+ files, adding a function, modifying state, or changing user-visible behavior is **not trivial**. When skipping, say so in your first sentence ("This is a trivial typo fix — skipping the pipeline.").

### How this rule fires

1. **`UserPromptSubmit` reminders** — `scripts/feature-pipeline-detect.sh` + speckit-command hooks via `scripts/pipeline-trigger-match.sh` (non-blocking; test: `bash scripts/test-pipeline-hooks.sh`).
2. **This rule file** — the source of truth.
3. **`scripts/spec-interview-guard-hook.sh`** — hard block until `interview.md` has ≥ 15 answers.
4. **`scripts/pipeline-state-guard-hook.sh`** — hard block until the active spec (`- [/]` or first `- [ ]` row) has `spec.md` with `## Clarifications`, `spec.allium` (full/light), `plan.md`, `tasks.md`. Markdown, config, `.claude/**`, `scripts/**`, `specs/**` stay editable; silent on template/scratch repos; fails open.

### What this rule forbids

- Editing production code for a multi-file feature without `/speckit-specify` first.
- Skipping `/speckit-clarify`, the spec interview, `/allium:elicit` (full/light), or `/speckit-plan` + `/speckit-tasks`.
- AUTO interview: inventing answers to genuinely-ambiguous questions, or skipping overflow on a large/advanced spec.
- Happy-path-only browser tests — every implemented function, a destructive suite per interactive function sized to its input domain, unit + integration underneath; mutation kill rate proves it bites.
- Declaring "done" without `/tla` (or stating spec-only and why).
- Asking "should I start with /speckit-specify?" — just start.

### When to stop

Only for: (1) genuine ambiguity (`AskUserQuestion`); (2) a hard blocker outside your control; (3) Allium/TLA+ findings (`validation-followup.md`). Otherwise keep going — the pipeline is one task, not seven.

---

## The rule as it stood before spec 099

Spec 099 shortened `.claude/rules/feature-pipeline.md` so the template's always-loaded rules fit 23,552 bytes and a synced project keeps room for its own CLAUDE.md (ighweld F168). Its full text on 2026-10-04 follows, word for word, headings demoted one level.

## Feature pipeline rule (auto-trigger, end-to-end execution)

The speckit + Allium + TLA+ pipeline is **not optional** for non-trivial work, on web and mobile alike. Long form (version history, why each phase exists, the full pre-081 text): `.claude/docs/feature-pipeline-rationale.md`.

### The contract (BLOCKING)

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

### Triage — what to run

| Spec shape | Track |
|---|---|
| Full-track spec that crosses a risk threshold (auth/payments/PII/upload/new external surface, state machine/concurrency, new entity or ≥6 files, or tagged) | **Full + hardened** (`.claude/rules/spec-hardening.md`) |
| Behaviour-changing (new feature, entity, state machine, concurrency, API surface) | **Full:** … → `/allium:elicit` → … → browser tests → `/tla` |
| UI feature, single actor, no concurrency | **Light:** as full, skip `/tla` unless the state is non-trivial |
| Non-behaviour (refactor, docs, deps, config, cosmetic, i18n, logging), or a fix with no new entities or transitions | **Spec-only:** spec → interview → clarify → impl. No `.allium`, no `/tla` |

When the track is unclear, ask **once** with `AskUserQuestion`, then proceed.

### When the pipeline is NOT required

A single-file typo, formatting or whitespace change; renaming one local variable; a one-line obvious bug fix with no spec impact; comment-only changes in one file; reverting one recent commit verbatim. Anything touching 2+ files, adding a function, changing state or changing user-visible behaviour is not trivial. When you skip, say so in your first sentence.

### Enforcement

`scripts/feature-pipeline-detect.sh` (reminder), `spec-interview-guard`, and `pipeline-state-guard`. The last two hard-block source edits until the active spec has `interview.md` (≥15 answers, plus confirmed acceptance cases on full/hardened specs), `spec.md` with `## Clarifications`, `spec.allium` (full/light), `plan.md` and `tasks.md`.

### Forbidden

Editing production code for a multi-file feature without `/speckit-specify`. Skipping clarify, the interview, `/allium:elicit` (full/light), or plan + tasks. Inventing answers to genuinely ambiguous questions. Happy-path-only tests. Declaring done without `/tla` (or saying it is spec-only and why). Asking "should I start with /speckit-specify?".

### When to stop

Only at a legitimate stop (`.claude/rules/continuous-execution.md` lists them). Otherwise keep going.
