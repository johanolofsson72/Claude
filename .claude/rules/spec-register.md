# Spec register rule (per-project register, one-stop-per-spec)

Every project keeps a **spec register** at `specs/INDEX.md`: the numbered, ordered source of truth for what to build and how far the project has got. **Continuous within a spec, one stop between specs.** Long form (the format example, measurements, enforcement internals, the full pre-081 and pre-099 text): `.claude/docs/spec-register-rationale.md`.

## The contract (BLOCKING)

When `specs/INDEX.md` exists:

1. **Read the register first, targeted.** SessionStart usually prints the next row; otherwise read only `## Specs` (`grep -nE '^- \[[ /!]\]' specs/INDEX.md | head`), never the history.
2. **Run the full pipeline for that one spec, end to end**, with no stops between phases.
3. **Commit and push to `main` directly** (solo, no PRs, no feature branches).
4. **Tick the register:** `[x]` on the row, committed and pushed with or right after the final commit.
5. **Stop with the status summary**, the only legitimate stop between specs.

One spec per run unless the user explicitly says to chain. Multi-lane: `.claude/rules/lane-handoff.md`; another lane's rows are not yours to tick, start or renumber.

## Rows and markers

`- [ ] NNN — <slug> — <full|light|spec-only> track[ [hardened]] — <one-line goal>`; the slug matches the spec folder; checkpoint rows `H<n>` (`.claude/rules/spec-hardening.md`). `- [ ]` not started · `- [/]` in progress (one at a time) · `- [x]` done and pushed · `- [!]` blocked or needs a rewrite. History: `## Register history (newest first)`, one dated line each.

## Keep the register lean (BLOCKING)

- **A row or history entry is ≤ 300 bytes, a pointer.** ~5 history entries inline (`scripts/archive-spec-history.sh`). Diagnosis lives in `specs/INDEX.completed.md` (ticked, verbatim), `specs/INDEX.pending.md` (open), prose in `specs/INDEX.notes.md`. Preserve first, shorten second: `scripts/archive-completed-rows.sh` when you tick; `scripts/register-bytes.sh` at the 25 KB canary.
- **Row ids:** `bash scripts/next-register-id.sh`, never by eye. **A tick** is a surgical Edit, refused while CORE work is owed (`scripts/core-owed-tick-guard-hook.sh`).
- **Failure memory across `/clear`:** `bash scripts/spec-run-log-hook.sh --note "<one line>"` → `<spec-dir>/run-log.md`.

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

Field values are listed in the rationale doc. `Maintenance due` comes from `bash scripts/maintenance-due.sh --brief`, never composed by hand. Open findings must already have been surfaced one by one. After the summary, stop: the stop **is** the question. One exception: this spec's row proposals go in the same stop as one `AskUserQuestion`, one question per proposal (**Approve** / **Decline**, its need and its `finding.sh --review --proposals` verdict), applied with `finding.sh --approve / --decline`.

## Register rewrite exception (the legitimate mid-spec stop)

When spec N shows the register is wrong (hidden dependency, invalidated later spec, scope creep, shifted goal): mark the row `- [!]`, `AskUserQuestion` (the conflict in one sentence, the source, concrete options), wait, apply it with a history line, resume. Typos and missing tests are not rewrites.

Enforced by `scripts/spec-register-orientation-hook.sh`, `scripts/spec-register-guard-hook.sh` (no source edits without `specs/INDEX.md`) and the tick gate. `/project-wizard` writes the register; "just one quick feature" is still spec 001.

## Forbidden

Feature work without checking the register. Working a spec that is not the next unchecked row. Chaining specs without explicit instruction. Mid-spec "should I continue?". Skipping the tick and commit. Silent scope growth (that is a register rewrite). Wrapping the stop in a question ("done, ready for 004?").
