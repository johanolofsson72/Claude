# Spec interview — 046-hook-output-channels

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with the recommended option; the two that changed
the shape of the work were escalated and are marked).

## Q1 — Scope boundary
**Q:** Does this spec fix the channel for all hooks, or only the ones visible in the reported screenshots?
**A (auto):** All of them. The screenshots showed four hooks; the defect is one decision made 50 times, and fixing four leaves the other 46 to be rediscovered.

## Q2 — Scope boundary
**Q:** Do the 38 unwired local-LLM hooks get their payloads corrected?
**A (auto):** Yes, corrected; still unwired. Register row 020 owns whether they get wired. A dead payload in a dormant hook is a trap set for whoever wires it.

## Q3 — Primary actor
**Q:** Who is the reader this spec is optimising for?
**A (auto):** Both, separately — that is the whole point. The developer gets what they must act on; Claude gets the instructions. Today they get each other's mail.

## Q4 — Happy path
**Q:** What does a clean session start look like afterwards?
**A (auto):** No red warnings at all unless a hook changed files on disk or a gate is known-broken. The register brief still reaches Claude, in full.

## Q5 — Data model
**Q:** What identifies "the same reminder" for de-duplication?
**A (auto):** Hook name + the file it is about (+ the condition, where a hook has several). Keyed under the session id, so it dies with the session.

## Q6 — Validation
**Q:** Should `notice_user` reject a multi-line message or collapse it?
**A (auto):** Collapse to " · ". A hook with something urgent to say must not lose it to a formatting rule; rejecting would trade one silent failure for another.

## Q7 — The four observable states
**Q:** What happens when the state directory cannot be written?
**A (auto):** The reminder fires. No state means "first time", so the failure mode is a repeat, never a silence.

## Q8 — Error semantics
**Q:** What does the GC do when it meets a `states/` directory it does not recognise?
**A (auto):** Keeps it and says so by name. Deleting on a name match would have destroyed a React component directory and a hand-written TLA+ model, both of which exist on this machine right now.

## Q9 — Authorization  (escalated — the answer changed the design)
**Q:** Is a PreToolUse deny without `hookEventName` actually honoured?
**A:** No. Verified live by A/B on one file: allowed without the field, denied with it. Every PreToolUse guard in the template — including the `~/.ssh` / `.env` read-block — had never blocked anything. This moved from "tidy the channel" to "the gates do not exist".

## Q10 — Concurrency / ordering
**Q:** Two sessions in one project writing the same dedupe state?
**A (auto):** Cannot collide — the path is keyed by session id. Sessions are independent by construction.

## Q11 — Integration points
**Q:** What else depends on the old channel?
**A (auto):** `test-pipeline-hooks.sh` asserts on `.systemMessage` in two places, and the autosync fixtures copy a script subset. Both updated; the suite is the proof.

## Q12 — Edge cases
**Q:** A machine without `jq`?
**A (auto):** Covered. `hook-notice.sh` carries the sed-based escaping that `template-sync-verify-hook.sh` already hand-rolled for exactly this case.

## Q13 — Non-functional limits
**Q:** What is the budget for a hook that runs at every session boundary?
**A (auto):** Close to free. The first GC draft used `-not -path '*/node_modules/*'`, which still descends; measured in minutes across the repo set. `-prune` brings it to ~1.2 s on the largest repo. A slow session-start hook is an unwired session-start hook.

## Q14 — Acceptance criteria
**Q:** What proves this is done?
**A (auto):** `test-hook-channels.sh` green (15), `test-pipeline-hooks.sh` green (165), and a live deny observed — not asserted.

## Q15 — Non-goals
**Q:** Does this spec change what any reminder SAYS?
**A (auto):** Only where the text was false. "BLOCKED" is removed from three PostToolUse messages that never blocked, and the `after_specify` "create a feature branch first" nag is removed because it contradicts the solo/direct-push rule it fires under. Everything else keeps its wording.

## Q16 — Reversibility
**Q:** How is this undone if it goes wrong?
**A (auto):** One commit, and `hook-notice.sh` is the only new dependency. Reverting restores the noise, not a broken state.

## Q17 — Scope boundary  (escalated — the user asked for it mid-spec)
**Q:** Does on-disk litter belong in this spec or a separate row?
**A:** In this one. The developer raised it while this was in flight, and it is the same shape: a cleanup reachable only through the event that created the mess, so an idle project never runs it.

## Q18 — Edge cases
**Q:** Why did `.claude/state/attempts/` grow despite having a TTL prune?
**A (auto):** The prune sits below `repeat-failure-guard-hook.sh`'s "only track verification runs" gate. The files are created by `dotnet test` and deleted by `dotnet test`; a project that stops running tests keeps every one it ever wrote.

## Q19 — Integration points
**Q:** Do the new scripts need to reach the projects?
**A (auto):** Yes — `hook-notice.sh` is sourced by synced hooks, so a project without it gets "notice_both: command not found". All three go into CORE_SCRIPTS and into the test fixtures; `--unlisted` confirms nothing is stranded.

## Q20 — Acceptance criteria
**Q:** Are the startup permission warnings in scope?
**A (auto):** Yes. They are the same complaint — noise at session start that nobody can act on. `Write(//**)` is not a rule Claude Code evaluates, and three `cp` rules point at a directory deleted months ago.
