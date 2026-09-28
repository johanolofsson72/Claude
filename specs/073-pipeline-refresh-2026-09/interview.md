# Spec interview — 073-pipeline-refresh-2026-09

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with the recommended option; the four scope questions were put to
the developer on 2026-09-28 and are recorded as human answers).

## Q1 — Scope boundary
**Q:** Which priority bands are in scope?
**A:** P0+P1+P2 — correctness/Linux, security/speed/context, tooling docs — then the rollout.

## Q2 — Scope boundary (rollout)
**Q:** How are projects with uncommitted work handled?
**A:** Sync, commit only the sync paths. A collision between a sync file and a local change skips that repo and reports it.

## Q3 — Scope boundary (unmanaged)
**Q:** Do the six repos without the template get bootstrapped?
**A:** No. All six are excluded.

## Q4 — Scope boundary (unpushed work)
**Q:** joucbox is four commits ahead; may the sync push carry them?
**A:** Yes.

## Q5 — Primary actor
**Q:** Who runs the sync paths after this spec?
**A (auto):** Autosync at SessionStart for both developers; `/project-update` and the wizard for the judgment half and first install. All three call one engine.

## Q6 — Happy path
**Q:** What does success look like on David's Linux machine?
**A (auto):** `git pull` in the template, `bash scripts/install-global-skills.sh`, and every project autosyncs at the next session start without a tarball fallback, with spec-kit at the pinned tag.

## Q7 — Data model
**Q:** Where does the pinned spec-kit version live?
**A (auto):** `scripts/speckit-version`, one tag per line, CORE, so every project carries the same pin and a bump is one commit.

## Q8 — Validation
**Q:** What happens when the installed spec-kit differs from the pin?
**A (auto):** Reinstall at the pin and re-init; the policy script runs after; a failed patch is reported, never swallowed.

## Q9 — Four states
**Q:** What does the developer see on a failed autosync?
**A (auto):** A one-line failure notice at the next session start naming the exit status and the log, repeated until a sync succeeds.

## Q10 — Error semantics
**Q:** Is a missing osv-scanner an error?
**A (auto):** No — reported as "not installed, NuGet/pub unscanned" with the install line. Fail open, but loudly.

## Q11 — Authorization
**Q:** Does anything here widen permissions?
**A (auto):** No. No new allow rules; no sudo; the global-skill installer writes only under `~/.claude/skills`.

## Q12 — Concurrency
**Q:** Two machines autosync the same repo — does the unification change the race?
**A (auto):** No. The engine already defers during rebase/merge and the second lane sets `CLAUDE_TEMPLATE_AUTOSYNC=0`; this spec keeps that contract.

## Q13 — Integration points
**Q:** Which external tools change version?
**A (auto):** spec-kit pinned to v1.0.12. Docs updated for Stryker.NET 5, xUnit v3 4.0, Playwright 1.63, TLA+ tools 1.8. No forced upgrade of project dependencies.

## Q14 — Edge cases
**Q:** Clone lives somewhere other than `~/repos/Claude`?
**A (auto):** `$CLAUDE_TEMPLATE_DIR` first, then `~/repos/Claude`, `~/repos/claude`, `~/Projects/Claude`, `~/src/Claude`, `~/code/Claude`; tarball only when none exists.

## Q15 — Non-functional
**Q:** What latency budget do the hooks get?
**A (auto):** No regression allowed; target at least 30% less wall time per Edit, measured with the same probe before and after.

## Q16 — Acceptance
**Q:** What proves the context diet did not lose a rule?
**A (auto):** Every rule keeps its BLOCKING contract in the always-loaded part; long rationale moves to `.claude/docs/`, referenced by path; hook tests unchanged and green.

## Q17 — Non-goals
**Q:** Is `blockReadsOutsideWorkingDirectories` adopted?
**A (auto):** No. The sync reads the template clone outside the project directory.

## Q18 — Reversibility
**Q:** How is a bad rollout undone?
**A (auto):** Each project gets one sync commit touching only sync paths; `git revert` of that commit restores it. The spec-kit pin is one line.
