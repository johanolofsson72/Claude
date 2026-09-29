# Spec interview — 011-twenty-hand-written-sync-invocations

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).

Hardened at triage (size trigger), so overflow is required. Three design questions were answered by the
developer on 2026-09-01 in consultpilot H7bo for this same change: the exclusion cap, the shape of the
write-free entry, and what the helper validates about the script. They are carried as Q17, Q18 and Q21
with their original answers. Q22 and Q23 are the overflow questions this landing raised and consultpilot
did not have. The developer answered them on 2026-09-29.

## Q1 — Scope boundary
**Q:** Is the interlock inside `template-autosync.sh` part of this change?
**A (auto):** No. This row changes the callers and the gate. The interlock from spec 010 stays byte-stable. `template-autosync.sh` changes only in its CORE_SCRIPTS list.

## Q2 — Scope boundary
**Q:** Are the production callers (`template-autosync-hook.sh`, `core-owed-tick-guard-hook.sh`, `lane-catchup.sh`) converted to the helper?
**A (auto):** No. They drive the real repository on purpose and must not declare a sandbox. The helper always declares one, so they keep an argued exclusion.

## Q3 — Primary actor & trigger
**Q:** Who is the actor?
**A (auto):** The developer or agent writing the next self-test against the sync. Secondarily, the reviewer who has to contest an exclusion entry.

## Q4 — Happy-path outcome
**Q:** What does success look like for that actor?
**A (auto):** One line, `drive_sync "$P" "$TMP" --force`, replaces an env prefix whose two halves had to be remembered. The gate passes the new driver with no change to the gate's source.

## Q5 — Data model
**Q:** What shape do the helper's inputs take?
**A (auto):** Two positional arguments (project, sandbox), then argv forwarded verbatim. Optional behaviour comes through env: `DRIVE_SYNC_SCRIPT` (required), `DRIVE_SYNC_CWD`, `DRIVE_SYNC_TIMEOUT`, plus any prefix assignment for the sync's own env.

## Q6 — Validation rules
**Q:** What does the helper refuse?
**A (auto):** A project that is empty, missing or not a directory. A sandbox that is empty, relative, `/`, missing, not a directory, or contains this repository. An unset, missing or unreadable script. A cwd it cannot enter. A timeout asked for with no timeout binary.

## Q7 — The four observable states
**Q:** What are success, error, empty and loading here?
**A (auto):** Success is the sync's own exit code, passed through. Error is exit 64 with one stderr line naming the bad value. Empty (no drivers) is a gate pass that counts 0. Loading does not apply: synchronous, with no progress output.

## Q8 — Error semantics
**Q:** How does a refusal look to the test that made the call?
**A (auto):** Fatal for that assertion, and visibly so. The exit code 64 cannot be read as the sync's 0/1/2 verdicts, so a broken fixture never passes as a real "no".

## Q9 — Authorization
**Q:** Who is allowed to run without a sandbox?
**A (auto):** Only a call whose argv proves it cannot write (a query mode), through `drive_sync_readonly`. The production callers keep that authority through the argued exclusion list, not through the helper.

## Q10 — Concurrency / ordering
**Q:** Does the helper add any shared state?
**A (auto):** No. It uses a subshell and no temp files. The self-tests run sequentially.

## Q11 — Integration points
**Q:** What else is touched?
**A (auto):** CORE_SCRIPTS (so the helper ships), the six drivers, the gate and its harness. `core-owed-tick-guard-hook.sh` sees the helper as CORE once it is listed, so `--unlisted` stays quiet.

## Q12 — Edge cases
**Q:** Which call shapes must the helper cover?
**A (auto):** A fixture copy of the sync (`$_p/scripts/template-autosync.sh`), era and sabotaged copies (`$ERA`, `$SAB`, `$TWO`), a cwd different from the project (owed AC-02/03, and the shim run from `$TMP`), a timeout (tick-guard `$TO`), and extra env (`CLAUDE_TEMPLATE_DIR`, `TMPDIR`, `PATH`).

## Q13 — Non-functional limits
**Q:** What performance limit applies?
**A (auto):** No regression in the gate's wall time. The baseline and the new gate are measured interleaved, not against a single cold reading (consultpilot's lesson).

## Q14 — Acceptance criteria
**Q:** How is done measured?
**A (auto):** AC-1..AC-7 in the spec: gate clean with 4 exclusions, each falsifiable, six drivers at unchanged counts, both harnesses green with every arm red when sabotaged, F014's shapes caught, TLC clean with two controls failing.

## Q15 — Non-goals & assumptions
**Q:** What is deliberately not done?
**A (auto):** T2 (a sync copied to an unrelated name and run through a variable) is reduced, not closed. E1 (one scanner process) and A1 (a line-level pragma) stay deferred as in consultpilot.

## Q16 — Reversibility
**Q:** How is it undone?
**A (auto):** `git revert` of the commit. There is no data and no migration. Downstream projects pick the revert up on their next sync.

## Q17 — Threat surface (carried from consultpilot H7bo; developer-answered 2026-09-01)
**Q:** Should the exclusion list have a hard cap, a falsifiable reason per entry, or both?
**A:** Both, with the number as the forcing function. A cap with no reason is a quota, and a reason with no cap grows. (Template value revised by Q22.)

## Q18 — Threat surface (carried from consultpilot H7bo; developer-answered 2026-09-01)
**Q:** How does a write-free call skip the sandbox: an empty-string sentinel on `drive_sync`, or a separate entry point?
**A:** A separate entry point that reads argv for its proof, not a sentinel value. An empty sentinel would be a value any caller could pass on any call, including a writing one.

## Q19 — Information disclosure / honesty (auto)
**Q:** When a refusal happens inside a test, whose failure is it?
**A (auto):** It depends on which side is under test, and the suite must not be able to confuse them. That is why the refusal code is 64 and why the gate harness's interlock rig bypasses the helper on purpose.

## Q20 — Resource exhaustion / blast radius (auto)
**Q:** Does concentrating 19 call sites into one helper widen the blast radius?
**A (auto):** Yes, and it is an improvement. Before, a defect in one of 19 sites failed one assertion quietly. Now a defect fails everything loudly, and the helper gets sabotage arms that no call site ever had.

## Q21 — Input tampering (carried from consultpilot H7bo; developer-answered 2026-09-01)
**Q:** What does the helper validate about `DRIVE_SYNC_SCRIPT`?
**A:** That it exists and is readable, nothing about its content. "Is this really the sync" cannot be decided, and the era and sabotaged copies exist precisely because they are not the current sync.

## Q22 — Threat surface: the template's exclusion cap (overflow; developer-answered 2026-09-29)
**Q:** The template needs 4 argued exclusions (two hooks, the harness, and `lane-catchup.sh:149`, a third production driver). consultpilot capped at 3. Raise the cap, add a production entry point, or drop the preview?
**A:** Cap 4, all argued. The harness pins exactly 4, so the list cannot grow without going red.

## Q23 — Scope / register (overflow; developer-answered 2026-09-29)
**Q:** Row 026 has the same scope as this row. What happens to it when 011 ticks?
**A:** Delete 026 with a one-line Register history entry naming 011 as the row that covered it.

## Q24 — Scope boundary (auto)
**Q:** Which query modes may `drive_sync_readonly` accept in the template?
**A (auto):** All four (`--is-core`, `--list-core-scripts`, `--list-core-rules`, `--template-dir`). They share the property, and the harness asserts it for each mode separately.

## Q25 — Edge cases: finding F014 (auto)
**Q:** Must the new gate catch the false negatives that spec 010 recorded against the old one?
**A (auto):** Yes, and each one is a fixture: `/bin/bash`, `timeout`/`env`/`nohup` wrappers, `source`, `zsh`, `local`/`export` handles, a caller in a subdirectory, and a trailing `# --is-core` comment. A shape the port cannot catch goes in the gate header as a residual, not unmentioned.
