# Spec interview — 106-downstream-core-red-2

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Hardened (≥ 6 files, and R4 widens what the sync adds), so the overflow carries
threat-surface questions for the developer (Q19–Q20).

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the template-owned reds that the 2026-11-17 sandboxes (agentcrm, billing) and the
template tree reproduce, plus F196 (1)–(3), F203, F207's message, F233 and F234. Out: project-owned
reds, exit-3 semantics in the pass (row 107), and the two items recorded as findings.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer reading a project's `--full` maintenance pass. Every template-made red
teaches them to skip section 5b, and the project-owned reds that matter get skipped with it.

## Q3 — Evidence standard
**Q:** How is "red downstream" measured?
**A (auto):** Local clones of agentcrm and billing, re-synced from the template working tree
through `drive_sync --force --no-commit`, all 94 CORE gates run with stdin closed and a 300 s
bound. Rerun after the fix. Every remaining red must be project-owned or recorded.

## Q4 — A git that cannot run: refuse or fall back?
**Q:** When git cannot read the local clone, should the sync try the remote tarball instead?
**A (auto):** Refuse. The remote path asks git (`ls-remote`) too, and a project whose git cannot run
cannot commit what the sync writes. A refusal with the binary named is the actionable answer.

## Q5 — Refusal exit code
**Q:** What does the refusal exit with?
**A (auto):** The same as the dirty-clone refusal: 0 at SessionStart (a refusal, not an error), 1
under `--accept-local`, which must fail loudly when it cannot record.

## Q6 — Where the readability check sits
**Q:** Before or after the dirty test?
**A (auto):** Before. With git broken, `git status --porcelain 2>/dev/null` prints nothing and the
dirty test reads the clone as clean. That is how `local-unknown` was reached.

## Q7 — The pinned branch
**Q:** Does the pinned branch need the check too?
**A (auto):** No. It already compares `rev-parse HEAD` with the pin, and a git that cannot answer
fails that comparison and goes to the fetch path, which reports unreachable. No made-up SHA.

## Q8 — harness-gitignore --tracked
**Q:** Empty output or error when git cannot run?
**A (auto):** Exit 2 with a reason. An empty list reads as "nothing tracked", the F196 (2) lie. A
directory that is not a git repository stays an empty answer, as now.

## Q9 — The awk warning
**Q:** Silence awk's stderr, change the regex, or pass it differently?
**A (auto):** Pass it through `ENVIRON`. awk does not escape-process the environment, the regex is
unchanged, and no stderr is hidden.

## Q10 — The pass reading core-gates
**Q:** Is fixing core-gates enough for F203?
**A (auto):** No. Section 5b also reads stdout only, so the next stderr line from any cause cannot
become a test name. stderr is kept for the exit-2 message.

## Q11 — sync-prompt snapshot (F234)
**Q:** Skip `scripts/sync-prompt.md` downstream, or have projects delete it?
**A (auto):** Skip it in the validator via `self_test_subject`, the predicate 102 established. A
deletion has to be done in every project by hand and comes back with the next prose sync.

## Q12 — RULE_DOCS: derive or list?
**Q:** Derive RULE_DOCS from citations at sync time, or keep the list and test it?
**A (auto):** Keep the list and add the parity test. Deriving at sync time adds a grep over the
template to every SessionStart and makes the shipped set depend on prose wording.

## Q13 — Which files count as "always shipped"
**Q:** Which citing files does the parity test read?
**A (auto):** CORE rules, CORE scripts, RULE_DOCS, RULE_ADDS and every skill file. Non-CORE rules
and docs reach only projects that already have them, and stack rules are removed on purpose.

## Q14 — Fixture paths in tests
**Q:** Tests build `$T/.claude/rules/x.md`. Are those citations?
**A (auto):** No. As in validate-rule-citations, a path built under a variable root is a fixture.
The parity test also ignores a cited name with no file in the template, which only a fixture can be.

## Q15 — Stack rules cited from always-shipped files
**Q:** sqlite-nfs-safety-hook.sh, project-update and project-wizard cite stack rules by path. Ship
the rules, or reword?
**A (auto):** Reword them to name the rule without the path. A project that removed sqlite.md on
purpose must not get it back, and a dangling citation there is a false red.

## Q16 — design-references.md
**Q:** Why does one rule get add-if-missing?
**A (auto):** The always-shipped project-wizard skill and frontend.md cite it, and billing (which has
frontend.md) never received it. It is path-scoped to frontend files, so it loads nowhere else.

## Q17 — test-context-budget detection
**Q:** Keep the marker heuristic next to self_test_subject?
**A (auto):** Yes, both. Downstream by either signal skips the ratchet. The markers still catch a
never-synced project, and self_test_subject catches billing's subdirectory layout.

## Q18 — R7 verdict
**Q:** Should the sandbox gate stop flagging `eval "$(sed … "$SYNC")"`?
**A (auto):** No. eval runs text read out of the sync, and the gate cannot tell a sed range from a
`cat`. The fix is a clearer message pointing at the query modes, and the remedy is agentcrm's.

## Q19 — Widening the sync (overflow, threat surface)
**Q:** R4 adds every doc an always-shipped file cites, plus design-references.md, to every project
that lacks them (add-if-missing, then manifest-protected). Ship, docs only, or reword instead?
**A:** Ship them (developer, 2026-11-17).

## Q20 — Broken-git refusal (overflow, availability)
**Q:** Refuse with exit 0 at SessionStart (1 under --accept-local), or exit 1 always?
**A:** Refuse, exit 0 (developer, 2026-11-17).
