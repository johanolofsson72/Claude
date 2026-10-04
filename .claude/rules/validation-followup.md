# Validation follow-up rule (Allium + TLA+)

After `/allium`, `/allium:elicit`, `/allium:distill` or `/tla` reports, the findings are the deliverable. Long form (examples, the full pre-081 and pre-099 text): `.claude/docs/validation-followup-rationale.md`.

## The contract (BLOCKING — after every run, however triggered)

The very next response does exactly one of these:

1. **Findings exist:** list every one as a numbered item, then call `AskUserQuestion` once with one question per finding. Each question states the finding exactly as reported, cites the source (file, line, rule, counterexample step), and offers `Fix now` / `Defer (track in spec)` / `Dismiss (with reason)`, plus a bespoke option when one fits.
2. **No findings:** say verbatim "Allium/TLA+ run complete. Zero drift, zero gaps, zero open questions, zero ambiguities."
3. **Run failed or inconclusive:** say so, and ask whether to retry, fix the blocker, or skip.

**A finding is** any of these: drift (specified-not-built, built-not-specified, behavioural), an `open question`, an `-- AMBIGUITY:`, a `deferred`, a TLA+ `GAP-N`, a counterexample, a MISSING TEST row, a TLC error or deadlock, a "consider implementation change", or a "too vague to formalize".

Surfacing is not rowing (`.claude/rules/carve-budget.md`): fix inside the spec, else `finding.sh --add`.

## Forbidden

"Looks good overall" summaries. Silently fixing the easy ones. Leaving markers for the user. Moving on undecided. One vague question instead of one per finding.
