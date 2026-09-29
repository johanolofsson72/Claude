# Spec interview — 029-pretooluse-deny-is-inert-under-bypass-permissions

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Hardened by the row tag. Overflow was declined by judgment: the row's premise was
refuted by a live A/B before the spec was written, the remaining work adds no runtime surface, and
none of the open questions changes behaviour anyone depends on. Recorded as `[interview:auto]`
behaviour.

## Q1 — Scope boundary
**Q:** Does this spec change any guard's decision logic?
**A (auto):** No. The verdicts were right; the shape was fixed by 046. IN: the test-side reader, the per-site static check, sabotage arms, the live probe, and the record.

## Q2 — Primary actor & trigger
**Q:** Who runs the new checks and when?
**A (auto):** The guard tests and `test-hook-channels.sh` run wherever they run today (maintenance, sync verify). The live probe is run by a developer on demand, after a Claude Code upgrade.

## Q3 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** Every guard test is green on the repo and red on a guard that emits the bare shape, and the probe exits 0.

## Q4 — Data model
**Q:** What vocabulary does `hook_verdict` return?
**A (auto):** `deny`, `ask`, `allow`, `dropped`, `none`, `invalid`. `dropped` is the new word, and it names what the CLI does with the payload.

## Q5 — Validation rules
**Q:** What counts as a well-formed PreToolUse decision?
**A (auto):** A `hookSpecificOutput` object whose `hookEventName` is exactly `PreToolUse` and whose `permissionDecision` is set. A wrong event name counts as `dropped` too.

## Q6 — Four observable states
**Q:** What are the probe's success, error, empty and loading states?
**A (auto):** On success it prints a per-mode table and exits 0. On error it names the failing mode and arm, with exit 1 or 3. Empty is the CLI missing, which is exit 2 with a message. Loading is one progress line per arm, since each arm takes ~10–30 s.

## Q7 — Error semantics
**Q:** A hung or crashed CLI arm, what is it?
**A (auto):** Inconclusive, exit 3, never a pass. A probe that cannot run cannot prove the guard holds.

## Q8 — Authorization
**Q:** Does the probe need credentials?
**A (auto):** It uses the developer's logged-in `claude`. It reads no secret and writes none.

## Q9 — Concurrency / ordering
**Q:** Can two probe runs collide?
**A (auto):** No. Each arm works in its own `mktemp -d` repo.

## Q10 — Integration points
**Q:** Which files change beyond the new ones?
**A (auto):** The five guard tests' decoders, `test-hook-channels.sh`, the CORE list in `template-autosync.sh`, `.claude/docs/workflows.md`, and the register plus its pending/completed archives.

## Q11 — Edge cases
**Q:** Heredoc JSON emits, the kind pipeline-state-guard uses for its fail-closed deny?
**A (auto):** The per-site check accepts `hookEventName` within the same object, i.e. up to 3 lines above the `permissionDecision` line. That is the observed layout.

## Q12 — Edge cases
**Q:** Inline hooks in `.claude/settings.json`?
**A (auto):** Included in R3. The sensitive-file rule is an inline emitter, and 046 §10 already repairs it on sync.

## Q13 — Non-functional limits
**Q:** Cost of the probe?
**A (auto):** Four haiku calls (2 modes × 2 arms), each under 180 s via `timeout`. Opt-in only.

## Q14 — Acceptance criteria
**Q:** How is "the tests bite" proven without Stryker (no bash target)?
**A (auto):** With sabotage arms, the same proxy 077 and 011 used. Each arm mutates a copy and must turn a check red.

## Q15 — Non-goals
**Q:** Scheduling the probe in maintenance-due?
**A (auto):** Out. It costs model calls. If a cadence is wanted, that is a finding for the 5-spec review.

## Q16 — Reversibility
**Q:** Rollback story?
**A (auto):** Tests and one opt-in script only. A revert of the commit restores the prior state with no data impact.

## Q17 — Threat surface: tampering
**Q:** Can a future edit re-open the hole silently?
**A (auto):** Only by weakening the shared reader or the static check. Both are pinned by sabotage arms in `test-hook-channels.sh`.

## Q18 — Threat surface: information disclosure
**Q:** Does the probe leak project content to the model?
**A (auto):** No. It runs in an empty temp repo with a fixed prompt, and its cwd is never the project.
