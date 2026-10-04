# Spec interview — 098-guard-hole-sweep-2

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO with human overflow. The row is `[hardened]` (security domain, the trust stores, the
acceptance gate's shortcut), so the four decisions that change what a guard lets through went to the
developer (O1–O4). They cover tampering (O1), fail-open versus fail-closed on a missing oracle (O2,
O3) and a forged suppression of a notice (O4). The base questions had defensible recommendations.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F139, F140, F141, F142, F143, F144, F155, F159 as R1–R10. Out: a script the agent
writes and runs (the 088 bound), deliberate filesystem writes by mutant code (R5 bound), the other
`notice_once` reminders, F151 (row 100).

## Q2 — Primary actor and trigger
**Q:** Who triggers the code this changes?
**A (auto):** The agent, through a PreToolUse call (Edit/Write, Bash, `mcp__*`), for R1–R4, R6 and R7.
The developer, by running `run-mutation-gate.sh` (R5) and the maintenance pass that runs
`validate-hooks.sh` (R8).

## Q3 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** Each bypass in the Problem table is denied, or announced where a guard keeps fail-open,
with a reason that names the cause and the developer's route. F155's command is allowed with no
output. A normal project pays no new process on any guard's common path.

## Q4 — Data model
**Q:** What new state exists?
**A (auto):** One directory: `<git dir>/claude-hook-notices/<sid>/` holding empty stamp files (R6).
Nothing else persisted. R2 removes a code path. R5 adds two `pushInsteadOf` entries to the sandbox's
own `.gitconfig`, which the run deletes with the copy.

## Q5 — Validation: what counts as "runs through a symlink" (R1)
**Q:** Which components are tested, and where does the walk stop?
**A (auto):** Every component from the file up to `CLAUDE_PROJECT_DIR` when the path is inside it,
else every component (guard_precheck_link's existing rule). Above the project a link is ordinary
(`/tmp` on macOS).

## Q6 — Validation: what is "visibly synced" (R3)
**Q:** Which evidence makes a missing sync script a deny rather than "not our project"?
**A (auto):** `.claude/.template-sync` at the sync root, or `specs/INDEX.md` there. Both are files the
template writes into a project. A repository with a `.claude/` directory and neither is someone else's
setup and stays silent.

## Q7 — The four states
**Q:** What are success, error, empty and loading here?
**A (auto):** Success: allow, no output. Error: a deny whose reason names the cause and a route.
Empty: a call with nothing to judge exits 0 before any parser. Loading: a guard that cannot decide
denies (pipeline guards, trust-anchor, the acceptance gate) or announces (the CORE guards, O3).

## Q8 — Error semantics for git in the root walk (R4)
**Q:** Which git outcomes are "cannot answer" and which are answers?
**A (auto):** Cannot answer: git not on PATH, a timeout, no timeout mechanism at all. Answers: any
exit code git itself returns, 128 ("not a git repository") included. Only the first set sets
`GUARD_GIT_UNSURE`.

## Q9 — Authorization
**Q:** Who may do what after this spec?
**A (auto):** The agent may not write the git dir (unchanged), may not edit CORE files or tick a
register in a synced project whose sync script is gone (R3), and may not unlock production code with
a Confirmed line the local answer store does not back (R2). The developer's routes are unchanged:
`!` commands, answering AskUserQuestion, `git checkout` of a lost file.

## Q10 — Concurrency and ordering
**Q:** Can two sessions race on the stamp directory (R6)?
**A (auto):** Yes, and harmlessly: stamps are per session id, creation is `: >`, and a lost race
announces twice. The sweep removes only directories older than two days.

## Q11 — Integration points
**Q:** What does this touch?
**A (auto):** `trust-anchor-guard-hook.sh`, `guard-precheck.sh` (reused), `acceptance_cases.py`,
`core-machinery-guard-hook.sh`, `core-owed-tick-guard-hook.sh`, `guard-lib.sh`, the three pipeline
guards (they read `GUARD_GIT_UNSURE`), `run-mutation-gate.sh`, `hook-notice.sh` callers,
`harness-state-gc.sh`, `settings_guard.py`, `hook_audit.py`. All CORE except the mutation runner.

## Q12 — Edge case: the template repository itself (R3)
**Q:** The template has a register and no `.template-sync`. Does R3 deny there?
**A (auto):** No. The template-identity check runs before the sync-script check and exits 0, as it does
today. R3 is reached only in a project.

## Q13 — Edge case: a stand-in repo with git broken (R4)
**Q:** A normal checkout (`.git` a directory, nothing above it) never runs git in the walk. Does R4
change that?
**A (auto):** No. `_guard_anchor_git_counts` returns before git when no `.git` is above the anchor,
and `_guard_linked_worktree` returns before git when `.git` is not a file. Those paths stay git-free.

## Q14 — Edge case: second clone after O1
**Q:** What happens when another clone checks out a spec whose Confirmed line came from the first?
**A (auto):** Production edits are denied until the developer answers the confirm question in that
clone. `--confirm` records the answer and rewrites the line with the same digest. The deny text says
so. This cost was accepted with O1.

## Q15 — Edge case: F155 lookalikes (R7)
**Q:** Which lines must still be denied?
**A (auto):** `cat <settings> | sh`, `echo <settings> | xargs rm`, `cat <settings> > f; sh f`,
`cat <settings> | tee f; bash f`, and `ls <settings> > l; xargs rm < l`. In each, the name reaches a
runner through a pipe or a file.

## Q16 — Non-functional limits
**Q:** Timeouts and cost?
**A (auto):** `GUARD_GIT_TIMEOUT` defaults to 5 s, the same as the core-machinery `--is-core` bound.
R1 adds a builtin-only walk (no fork) to trust-anchor's pre-check. R6 adds one `[ -d ]`. R7 adds one
list per command. SC-2 is measured with `bench-hooks.sh`.

## Q17 — Mutation sandbox allowlist (R5)
**Q:** Why an allowlist and not a longer denylist?
**A (auto):** A denylist misses whatever the next tool adds (`GIT_SSH_COMMAND`, cloud tokens, F143).
The tests are this template's own bash self-tests: they need PATH, TMPDIR, a locale and HOME, and
`self-test-env.sh` already scrubs the rest itself.

## Q18 — Mutation kill semantics (R5)
**Q:** What happens to rc 137 under the limit?
**A (auto):** It is infrastructure: no verdict is written, and the report refuses to score the run
(exit 2). An OOM kill or an external `kill -9` says nothing about the mutant. Over the limit it stays a
timeout (the `-k 5` path).

## Q19 — Acceptance criteria
**Q:** What is the measurable definition of done?
**A (auto):** SC-1 to SC-4 in spec.md, the acceptance cases, the full template suite green, the
mutation gate at the hardened bar on the changed Python modules.

## Q20 — Non-goals and assumptions
**Q:** What is assumed?
**A (auto):** The agent runs as the developer's OS user. The developer's git and origin are trusted.
`perl` exists wherever git does (Git for Windows bundles it), so R4 always has a timeout; if none
exists, that is itself "cannot answer".

## Q21 — Reversibility
**Q:** How is this rolled back?
**A (auto):** Every change is a code change in CORE scripts, reverted by a commit and carried by the
sync. The stamp directory is disposable. Projects whose CORE guards now deny (R3) recover by restoring
`scripts/template-autosync.sh`.

## O1 — The acceptance gate's upstream shortcut (overflow — F140, tampering)
**Q:** A plain `git push` moves the remote-tracking ref the shortcut trusts. Drop the shortcut, keep it
only for commits that arrived by fetch (reflog), or keep it as a bound?
**A:** Drop it. Every Confirmed line must be backed by this clone's answer store. A fresh clone or the
other lane re-asks the developer once.

## O2 — CORE guards with the sync script gone (overflow — F141, fail-open)
**Q:** When the project is visibly synced and `scripts/template-autosync.sh` is missing: deny, or
announce and allow?
**A:** Deny. CORE-path edits and register ticks are refused with the route. No stamp and no register
stays silent.

## O3 — Root walk when git cannot answer (overflow — F142, resource exhaustion)
**Q:** Split by guard, all announce, or all deny?
**A:** Split by guard. The three pipeline guards deny, naming the cause. The two CORE guards announce
and allow.

## O4 — Where the announce stamp lives (overflow — F144, repudiation)
**Q:** In the git dir, or no dedupe at all?
**A:** In the git dir, `$CLAUDE_PROJECT_DIR/.git/claude-hook-notices/<sid>/`. No git dir: say it every
time.
