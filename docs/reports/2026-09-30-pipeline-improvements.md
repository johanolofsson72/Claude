# Pipeline improvements report

2026-09-30 · Johan Olofsson · live version: https://claude.ai/code/artifact/8394432a-7d31-4e15-a605-dd46b5455f5a

Baseline snapshot for the next template update or bug hunt. Template HEAD at the time of writing: `9faf211`.

## Summary

Between 2026-09-03 and 2026-09-30 the template closed 75 of its 77 register rows in 129 commits. The pipeline is the same chain as before (specify, interview, clarify, plan, implement, test, verify). What changed is that far more of it is now checked by hooks and scripts instead of trusted to the model, and the checks themselves were tested until they stopped lying.

Three things moved the most. Hooks that looked active were silent until 2026-09-12, and now they reach the model. The register can no longer grow faster than it closes: a freeze is in force and new rows need an approved proposal. Projects update themselves from one sync engine that refuses to overwrite local edits and leaves a verification obligation behind.

It is not finished. Two rows are held, the second integration checkpoint is overdue, and 51 findings wait for review.

## The pipeline per spec

Every non-trivial change runs this chain as one task, with no permission stops between phases. The spec interview (15 to 25 questions, auto-answered by default) and clarify run on every track; elicit and TLA+ are skipped on spec-only work.

```
Specify → Interview → Clarify → Elicit → Plan → Tasks
  → Analyze → Implement ⇄ Converge (loops while it appends work)
  → Simplify → Tests → TLA+ → Tick, commit, push
```

Three PreToolUse guards (`spec-register`, `spec-interview`, `pipeline-state`) deny source edits until the interview, clarifications, plan and tasks exist. A register tick is refused while the project owes the template CORE work.

## Improvements by theme

Most rows came from a real project hitting a real defect (agentcrm, rocky, fundit, consultpilot, ekofak, teach). The common thread: a check that reported green while checking nothing.

| Theme | What changed | Specs |
| --- | --- | --- |
| Hooks reach the model | Advisory hooks used `systemMessage`, which only the developer sees, and guards without `hookEventName` were dropped by the CLI. Reminders now go to model context, guard tests read verdicts the way the CLI does, and deny texts name the actual cause. | 029, 032, 039, 046, 058, 059, 076 |
| The register converges | Carve budget (2 per spec, depth 2), a measured carve ratio, a freeze line the hooks read, row proposals that must show who is hurt, duplicate detection with local embeddings, checkpoint cadence counted correctly. | 001, 009, 017, 019, 027, 054, 055, 066, 068, 077 |
| One sync engine | Wizard, `/project-update` and autosync share one engine. It refuses to write outside a declared sandbox, never overwrites a locally edited file, pins spec-kit, and blocks a tick while a project owes the template CORE work. | 010, 011, 014, 018, 021, 022, 040, 045, 073, 078 |
| Checks that cannot lie | `Passed!` over an aborted test run, a scan that found zero ids, a walk that raced test output: each now refuses instead of reporting a number. The scenario traceability gate reads the naming convention the rules prescribe, including chained ids. | 007, 012, 031, 044, 048, 057, 060, 061, 062, 064, 067, 079 |
| Testing and mutation | Per-module Stryker gate from this run's reports, dead mutate patterns reported, stale `.stryker-tmp` removed, a nightly cron line that actually finds dotnet, nested JS suites counted, a correct .NET visual-regression example. | 004, 035, 043, 047, 051, 052, 053, 063, 065, 071 |
| Security | Signing keys that trufflehog misses are found, a scan error is no longer called a verified secret, every manifest type is named as audited or not, production secrets move to Swarm secret files. | 023, 034, 038, 070, 072 |
| Cross-platform | zsh word-splitting, BSD vs GNU `sed -i`, a `pkill -f` that killed its own shell, a TLC cleanup that killed live runs. | 018, 037, 056, 069, 073 |

Two rows are the ones people will notice day to day. 046 means reminders now change what Claude does instead of scrolling past the developer. 073 means a project opened on any machine pulls the current harness on its own.

## Sync and rollout

A project updates itself when a Claude session starts in it. The sync fast-forwards the local template clone (or downloads the tarball), copies scripts, rules, docs, agents and hook wiring, commits only its own paths and pushes. A file someone edited locally is skipped and named. CLAUDE.md prose and project-specific settings are never touched; that is what `/project-update` is for.

The sync does not run the project's tests. It writes `.git/template-sync-unverified`, and `scripts/template-sync-verify.sh` clears it once the project's suite passes. In fundit the first verify failed on a leftover `.stryker-tmp` folder that had nothing to do with the sync; it passed (6079 tests) once that folder was gone.

State of the 45 synced projects on 2026-09-30, before the rollout: none was on the current template (`9faf211`), most were 60 to 82 commits behind. That is the cost of sync-on-open: a project nobody opens never updates.

| Group | Projects | Action |
| --- | --- | --- |
| Clean, default branch | 11 | Synced and pushed 2026-09-30 |
| fundit | 1 | Synced, verified, finding F246 recorded |
| Dirty tree, default branch, no live session | 23 | Rollout running; uncommitted work checked unchanged per repo |
| Live session in the last hour | 3 (agentcrm, cv, hireflow) | Skipped; they sync on next open |
| Uncommitted edits to CORE scripts | 1 (ighweld-web-license) | Skipped; the sync would overwrite them |
| Feature branch checked out | 5 | Skipped; the sync would push to the branch |
| Behind origin with a dirty tree | 1 (rocky) | Skipped |

David's projects follow the same path on his machine. His clone fast-forwards on its own unless it has uncommitted or diverged work.

## Known gaps and debt

The template's own checks are behind the pace of the work. None of this breaks a project today, but none of it has been proven either.

- [ ] H2 integration checkpoint: 33 feature specs ticked since H1, the rule says one every 5. Full regression, security sweep, scenario reconciliation, mutation spot-check.
- [ ] Findings review: 51 open findings, due since 5 ticks ago.
- [ ] Full test suite: last run 28 ticks ago.
- [ ] Stryker on the template: never run here.
- [ ] Row 079 was added and ticked during the freeze without an approved proposal. Approve or cut.
- [ ] 075 (local vs cloud placement) is held until five ordinary specs have run under the 074 ledger.
- [ ] 020 (15 local-LLM quality hooks left unwired for latency) is held for a re-measure against the nightly run.
- [ ] Rollout leftovers: 10 projects skipped (see above), and the synced ones still need `template-sync-verify.sh` where the rollout could not clear it.

## Numbers

Measured from the template repo on 2026-09-30; the register opened 2026-09-03.

| Measure | Value |
| --- | --- |
| Register rows | 77 (75 ticked, 2 held) |
| Integration checkpoints done | 1 (H1) |
| Commits since the register opened | 129 |
| Shell scripts in `scripts/` | 195, of which 67 are self-tests |
| Projects on autosync | 45 |
| Open findings | 51 |
