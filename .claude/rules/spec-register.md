# Spec register rule (per-project register, one-stop-per-spec)

Every project keeps a **spec register** at `specs/INDEX.md`: the numbered, ordered source of truth for what to build and how far the project has got. **Continuous within a spec, one stop between specs.** Long form (measurements, incidents, byte budgets, enforcement internals, the full pre-081 text): `.claude/docs/spec-register-rationale.md`.

## The contract (BLOCKING)

When `specs/INDEX.md` exists:

1. **Read the register first, targeted.** The SessionStart hook usually prints the next row. If you must open it, read only `## Specs`, never `## Register history` or `INDEX.history.md`. On a large register: `grep -nE '^- \[[ /!]\]' specs/INDEX.md | head`.
2. **Run the full pipeline for that one spec, end to end**, with no stops between phases.
3. **Commit and push to `main` directly** (solo, no PRs, no feature branches).
4. **Tick the register:** `[x]` on the row, committed and pushed with or right after the spec's final commit.
5. **Stop with the status summary.** That is the only legitimate stop between specs.

One spec per run. Chain specs only when the user explicitly says so.

## Two lanes (only with more than one developer)

A row may end with an owner tag `— @name`. Each machine sets `SPEC_OWNER` in `.claude/settings.local.json`, and the second lane sets `CLAUDE_TEMPLATE_AUTOSYNC=0`. The three guards and the orientation hook resolve the active spec through `scripts/spec_active.py`: **my in-progress row → my next row → an unowned in-progress row → the next unowned row**. A held row (`- [!]`) is never offered. The other lane's rows are not yours to tick, start or renumber. Details: `.claude/rules/lane-handoff.md`.

## The register format

```markdown
# Spec register

## Specs

- [x] 001 — user-auth — full track [hardened] — short one-line goal
- [ ] 002 — search — full track — short one-line goal
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after spec 005

## Register history (newest first)

- 2026-05-14 — initial register, 5 specs identified during project kickoff
```

A row has a 3-digit **id**, a kebab-case **slug** (it matches the spec folder), a **track** (`full` / `light` / `spec-only`, plus **`[hardened]`** when a risk threshold is crossed, `.claude/rules/spec-hardening.md`), and a **one-line goal**. Checkpoint rows (`H1`, `H2`, …) come after every 5th feature spec.

Markers: `- [ ]` not started · `- [/]` in progress (one at a time) · `- [x]` done, committed, pushed · `- [!]` blocked or needs a register rewrite.

## Keep the register lean (BLOCKING — context-cost hygiene)

- **History entries are one line, ≤ 300 bytes, about 5 inline.** The heading declares `(newest first)` or `(newest last)`. Archive the rest with `scripts/archive-spec-history.sh` (`--keep 5`, `--max-bytes`, `--dry-run`).
- **A row is ≤ 300 bytes and is a pointer.** The diagnosis lives in `specs/INDEX.completed.md` (ticked, verbatim) or `specs/INDEX.pending.md` (not started). Preserve first, shorten second: `scripts/archive-completed-rows.sh`, run when you tick.
- **Prose lives in `specs/INDEX.notes.md`.** `scripts/register-bytes.sh` names the moves when the 25 KB canary fires.
- **Never pick a row id by eye:** `bash scripts/next-register-id.sh` (`--count`, `--alpha`, `--checkpoint`, `--suffix NNN`). `scripts/validate-register-ids.sh` catches collisions.
- **A tick is a surgical Edit** of `- [ ]` → `- [x]`. It is refused while the project owes the template CORE work (`scripts/core-owed-tick-guard-hook.sh`). Fix that in the template and sync back.

## Failure memory across `/clear`

`<spec-dir>/run-log.md` gets a line per pipeline artifact (`scripts/spec-run-log-hook.sh`). Add notes for whatever a fresh session would otherwise rediscover: `bash scripts/spec-run-log-hook.sh --note "<one line>" [--spec NNN]`. It is not pipeline input; SessionStart shows the last 5 lines while the row is `- [/]`.

## The status summary (the one stop per spec)

```
**Spec NNN — <slug> — DONE**

- Track: <full|light|spec-only>[ +hardened]
- Commits: <count> (last: <short-sha> — "<commit subject>")
- Push: origin/main <short-sha>
- Pipeline: spec → interview (<I> answers, <interview mode>) + <acceptance status> → <clarify status> → <allium status> → impl → <N> functional + <M> destructive browser tests → <tla status>
- Hardening: <hardening status>
- Open findings: <count> (or "none")
- Row proposals: <count from this spec, each with its review verdict> (or "none")
- Maintenance due: <what ticking this row just made stale, or "nothing">

**Next: NNN — <slug>** (or "register complete")

→ Before starting the next spec, run `/clear`. Fresh context per spec is the cheap default; the register + orientation hook restore all the state the next spec needs.

(Resume when ready.)
```

Field values (interview mode, acceptance, clarify, allium, tla, hardening wording) are listed in `.claude/docs/spec-register-rationale.md`. `Maintenance due` comes from `bash scripts/maintenance-due.sh --brief` and is never composed by hand. Open findings must already have been surfaced one by one.

After the summary, stop. No follow-up question: the stop **is** the question. One exception: row proposals from this spec go in the same stop as one `AskUserQuestion`, one question per proposal with **Approve** / **Decline**, stating its need and its `finding.sh --review --proposals` verdict. Apply the answers with `finding.sh --approve / --decline`.

## Register rewrite exception (the legitimate mid-spec stop)

When spec N shows the register itself is wrong (a hidden dependency, an invalidated later spec, scope creep, a shifted goal): mark the row `- [!]`, surface it with `AskUserQuestion` (the conflict in one sentence, the source, concrete options), wait for the user, apply the change with a one-line history entry, and resume. Typos and missing test cases are not rewrites.

## Enforcement

SessionStart orientation (`scripts/spec-register-orientation-hook.sh`), the PreToolUse register guard (`scripts/spec-register-guard-hook.sh`: no source edits without `specs/INDEX.md`), the tick gate (`scripts/core-owed-tick-guard-hook.sh`, override `ALLOW_TICK_WITH_CORE_OWED=1`), and this file. Hooks stop at the `.git` boundary; the template repo trips none.

## Bootstrapping

`/project-wizard` writes the register. Fallback: interview the user for the initial specs and their order, triage each track, write `specs/INDEX.md` with a dated history entry, commit and push, then start spec 001. "Just one quick feature" is still spec 001.

## Forbidden

Feature work without checking the register. Working a spec that is not the next unchecked row. Chaining specs without explicit instruction. Mid-spec "should I continue?". Skipping the tick and commit. Silent scope growth (that is a register rewrite). Wrapping the stop in a question ("done, ready for 004?").
