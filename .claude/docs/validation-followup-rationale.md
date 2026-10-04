# validation-followup — long form (rationale, history, examples)

> Reference, loaded on demand — never @-import it. The always-loaded contract is
> `.claude/rules/validation-followup.md`; if the two ever disagree, the rule governs and this file is the one to fix.
> Below is the full text of the rule as it stood before spec 073 (R8) split it, headings intact, so
> every section a hook or doc cites by name is still reachable here.

---


When `/allium`, `/allium:elicit`, `/allium:distill`, or `/tla` runs and produces a report — the findings are NOT background reading. They are the deliverable. Glossing over them defeats the entire pipeline.

## The contract (BLOCKING — applies after every Allium or TLA+ run)

After any Allium or TLA+ skill run completes, the very next response MUST do one of these — nothing else is acceptable:

1. **Findings exist** → list every single one as a numbered item, then immediately call `AskUserQuestion` with one decision per finding (fix now / defer / dismiss with reason).
2. **No findings** → state explicitly: "Allium/TLA+ run complete. Zero drift, zero gaps, zero open questions, zero ambiguities." If you cannot say this verbatim and mean it, you have findings — see option 1.
3. **Run failed or was inconclusive** → say so plainly, then ask whether to retry, fix the blocker, or skip.

A response that summarizes the report without surfacing every finding for explicit decision is a **rule violation** and must be retried.

## What counts as a "finding"

ALL of the following are findings and MUST be surfaced individually:

- Allium drift items (specified-but-not-implemented, implemented-but-not-specified, behavioral drift)
- Allium `open question "..."` entries
- Allium `-- AMBIGUITY:` comments produced during elicitation
- Allium `deferred` markers
- TLA+ `GAP-N` entries (safety, liveness, fairness)
- TLA+ counterexamples / state traces
- TLA+ "MISSING TEST" rows in the coverage matrix
- TLC errors, deadlocks, invariant violations
- Any "consider implementation change" recommendations
- Any "the spec is too vague to formalize" notes

If you find yourself thinking "this one is minor, I'll skip it" — that is exactly the failure mode this rule exists to prevent. Surface it. Let the user decide.

## Surfacing is not rowing (`.claude/rules/carve-budget.md`)

This rule requires every finding be **surfaced**. It has been read as requiring every finding become
a **register row**, and that reading is what took five projects to a carve ratio above 1.0 — the
register growing faster than it closes, measured 2026-09-03 at 2.15 on rocky and 2.08 on agentcrm.

Surface all of them. Then give each one of three dispositions, defaulting to the first:

1. **Fix it inside the current spec** — when the fix is smaller than the ceremony of recording it.
2. **Record it as a finding** — `bash scripts/finding.sh --add "<one line>" --spec NNN`. This is the
   default for everything else. It goes to `specs/FINDINGS.md` and is decided at the next 5-spec
   review, not now.
3. **Carve a row immediately** — the exception, for work that blocks the next spec and cannot wait.

All three satisfy this rule: the finding was named, decided, and recorded. Only the second one grows
the register. "Defer (track in spec)" in the option set below means the third when the budget is
spent — not "always make a row".

## How to surface findings

Use `AskUserQuestion` with one question per finding. Each question:

- States the finding in one line, exactly as the report described it (no softening, no paraphrasing-into-blandness).
- Cites the source (file path, line, rule name, or counterexample step).
- Offers concrete options. Default options are: `Fix now`, `Defer (track in spec)`, `Dismiss (with reason)`. Add a fourth bespoke option when one applies (e.g. `Update spec instead of code`).
- Defaults to `Fix now` framing — the language must make dismissing feel like an active choice, not the path of least resistance.

Batch questions in a single `AskUserQuestion` call when there are multiple findings (the tool supports that). Do not split across turns to "make it manageable" — the user wants the full picture at once.

## What this rule forbids

- "Looks good overall" / "mostly clean" summaries that bury findings.
- Acting on the easy fixes silently while ignoring the hard ones.
- Treating `open question` or `-- AMBIGUITY:` markers as the user's problem to discover later.
- Continuing to the next task while findings remain undecided.
- Asking a single vague question like "want me to address the issues?" — every finding gets its own decision.

## Scope

This rule applies whenever the Allium or TLA+ skills run, regardless of trigger (manual `/allium`, `/tla`, automatic post-implementation hook, or as part of a larger workflow like `/feature-dev`). It applies even if the user did not explicitly ask to see findings — surfacing them is the whole point of running these tools.

---

## The rule as it stood before spec 081

Spec 081 shortened `.claude/rules/validation-followup.md` to fit the 40 KB always-loaded budget. Its full text on
2026-10-01 follows, word for word, headings demoted one level.

## Validation follow-up rule (Allium + TLA+)

After `/allium`, `/allium:elicit`, `/allium:distill` or `/tla` produces a report, the findings are the deliverable, not background reading. Long form (examples, reasoning): `.claude/docs/validation-followup-rationale.md`.

### The contract (BLOCKING — applies after every Allium or TLA+ run)

The very next response MUST do exactly one of:

1. **Findings exist** → list every one as a numbered item, then immediately call `AskUserQuestion` with one decision per finding (fix now / defer / dismiss with reason).
2. **No findings** → state verbatim: "Allium/TLA+ run complete. Zero drift, zero gaps, zero open questions, zero ambiguities." If you cannot say this and mean it, you have findings — see 1.
3. **Run failed or inconclusive** → say so plainly, then ask whether to retry, fix the blocker, or skip.

A summary that does not surface every finding for explicit decision is a **rule violation** and must be retried.

### What counts as a "finding"

Every one of these, surfaced individually: Allium drift items (specified-not-implemented, implemented-not-specified, behavioral drift); Allium `open question "..."` entries; `-- AMBIGUITY:` comments; `deferred` markers; TLA+ `GAP-N` entries (safety, liveness, fairness); TLA+ counterexamples / state traces; "MISSING TEST" rows in the coverage matrix; TLC errors, deadlocks, invariant violations; any "consider implementation change" recommendation; any "the spec is too vague to formalize" note. "This one is minor, I'll skip it" is exactly the failure mode — surface it.

### Surfacing is not rowing (`.claude/rules/carve-budget.md`)

Surface all of them, then give each one of three dispositions, defaulting to the first:

1. **Fix it inside the current spec** — when the fix is smaller than the ceremony of recording it.
2. **Record it as a finding** — `bash scripts/finding.sh --add "<one line>" --spec NNN` → `specs/FINDINGS.md`, decided at the next 5-spec review. The default for everything else.
3. **Carve a row immediately** — the exception, for work that blocks the next spec.

All three satisfy this rule; only the third grows the register. "Defer (track in spec)" means the third only when the budget allows — not "always make a row".

### How to surface findings

`AskUserQuestion`, one question per finding, batched in a single call (never split across turns). Each question states the finding in one line exactly as reported (no softening), cites the source (file, line, rule, counterexample step), and offers `Fix now` / `Defer (track in spec)` / `Dismiss (with reason)` plus a bespoke option when one applies (e.g. `Update spec instead of code`). Frame it so dismissing is an active choice.

### What this rule forbids

- "Looks good overall" / "mostly clean" summaries that bury findings.
- Silently fixing the easy ones while ignoring the hard ones.
- Leaving `open question` / `-- AMBIGUITY:` markers for the user to discover later.
- Continuing to the next task while findings remain undecided.
- One vague question ("want me to address the issues?") instead of a decision per finding.

**Scope:** every Allium or TLA+ run, however triggered (manual, automatic hook, inside `/feature-dev`), even if the user did not ask to see findings.

---

## The rule as it stood before spec 099

Spec 099 shortened `.claude/rules/validation-followup.md` so the template's always-loaded rules fit 23,552 bytes and a synced project keeps room for its own CLAUDE.md (ighweld F168). Its full text on 2026-10-04 follows, word for word, headings demoted one level.

## Validation follow-up rule (Allium + TLA+)

After `/allium`, `/allium:elicit`, `/allium:distill` or `/tla` reports, the findings are the deliverable. Long form (examples, the full pre-081 text): `.claude/docs/validation-followup-rationale.md`.

### The contract (BLOCKING — after every run, however triggered)

The very next response does exactly one of these:

1. **Findings exist:** list every one as a numbered item, then call `AskUserQuestion` once with one question per finding. Each question states the finding exactly as reported, cites the source (file, line, rule, counterexample step), and offers `Fix now` / `Defer (track in spec)` / `Dismiss (with reason)`, plus a bespoke option when one fits.
2. **No findings:** say verbatim "Allium/TLA+ run complete. Zero drift, zero gaps, zero open questions, zero ambiguities."
3. **Run failed or inconclusive:** say so, and ask whether to retry, fix the blocker, or skip.

**A finding is** any of these: drift (specified-not-built, built-not-specified, behavioural), an `open question`, an `-- AMBIGUITY:`, a `deferred`, a TLA+ `GAP-N`, a counterexample, a MISSING TEST row, a TLC error or deadlock, a "consider implementation change", or a "too vague to formalize".

Surfacing is not rowing (`.claude/rules/carve-budget.md`). The default disposition is a fix inside the spec, then `finding.sh --add`. An immediate row is the exception.

### Forbidden

"Looks good overall" summaries. Silently fixing the easy ones. Leaving markers for the user to find. Moving on with findings undecided. One vague question instead of one per finding.
