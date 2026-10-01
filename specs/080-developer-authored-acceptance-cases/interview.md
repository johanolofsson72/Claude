# Spec interview — 080-developer-authored-acceptance-cases

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Hardened (register tag), so the overflow questions go to the developer.

## Q1 — Scope boundary
**Q:** Does 080 prove a test was red before the code that makes it green?
**A (auto):** No. A hook sees edits, not test runs. "Written first" is enforced as ordering: a test
naming each case must exist before production source unlocks. Red-first proof is a non-goal.

## Q2 — Scope boundary
**Q:** Which tracks owe acceptance cases?
**A (auto):** Full, and any row tagged `[hardened]`. That is what F075 asked for, and light/spec-only
specs are where the ceremony would cost more than the drift it catches.

## Q3 — Primary actor
**Q:** Who writes the cases, and who confirms them?
**A (auto):** Escalated to the developer, see O1: Claude drafts, the developer confirms.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** After the interview Claude drafts 3-5 cases, the developer confirms them in one
`AskUserQuestion`, Claude writes the confirmation line, writes one test per case, and only then
touches production source.

## Q5 — Data model
**Q:** Where do the cases live?
**A (auto):** `<spec-dir>/acceptance.md`, a separate file. Putting them in `interview.md` would mix a
second grammar into the file the answer counter reads, and the coverage scan wants a small file.

## Q6 — Data model (ids)
**Q:** How does a test name a case?
**A (auto):** `<spec-id>-AC-<n>`, e.g. `080-AC-2`. A bare `AC-2` collides across specs.

## Q7 — Validation
**Q:** What makes a case well-formed?
**A (auto):** A `## AC-<n> — <title>` heading and non-empty `**Given**`, `**When**`, `**Then**`
lines; numbering 1..N with no gaps or repeats. Anything else is named by line, never skipped.

## Q8 — Validation (count)
**Q:** Is 3-5 a hard band?
**A (auto):** Escalated to the developer, see O2: hard both ways.

## Q9 — Observable states
**Q:** What does the guard say in each state?
**A (auto):** No file: deny, with the format and the instruction to ask the developer. Malformed:
deny, naming each problem. Unconfirmed or digest mismatch: deny, naming which. Confirmed but
untested cases: test files allowed, production denied, naming the untested ids. All tested: silent
allow.

## Q10 — Error semantics
**Q:** What if the parser itself fails (python missing, unreadable file)?
**A (auto):** The interview guard's existing rule: a gate that cannot establish what it guards
denies (rc 98 path), an unexpected internal error fails open. The acceptance step reuses that
split; an unreadable `acceptance.md` is a deny, a crash in the coverage scan is fail-open.

## Q11 — Authorization
**Q:** Can Claude write the confirmation line?
**A (auto):** Claude writes it, through the helper, only after the developer's `AskUserQuestion`
answer, and quotes that answer. The rule says so; the guard cannot tell who typed it.

## Q12 — Concurrency
**Q:** Two sessions on the same spec?
**A (auto):** N/A beyond what the interview guard has: one active row, files read fresh per edit.

## Q13 — Integration
**Q:** New hook or the existing one?
**A (auto):** The existing `spec-interview-guard-hook.sh`. `settings.json` is project-owned and not
synced (H7bk), so a new hook would never be wired in the projects that need it.

## Q14 — Integration (resolver)
**Q:** How does the guard know a row is hardened?
**A (auto):** `spec_active.resolve()` adds a `hardened` boolean read from the track field. Additive,
so every existing caller is unaffected.

## Q15 — Edge case (test-file detection)
**Q:** What counts as a test file?
**A (auto):** By path, the conventions of the stacks this template serves (.NET, JS/TS, Python, Go,
Dart, Ruby). A miss means a test edit is denied during step 2, which is loud, not silent.

## Q16 — Edge case (references in production code)
**Q:** Does `080-AC-1` in a production comment count as covered?
**A (auto):** No. Only test files count, or the gate is satisfied by a comment.

## Q17 — Non-functional
**Q:** What does the coverage scan cost per edit?
**A (auto):** One `git grep -F` over tracked and untracked files, only while a full/hardened spec is
in step 2. Measured in the tests; must stay under 200 ms on this repo.

## Q18 — Acceptance criteria
**Q:** How is 080 itself accepted?
**A (auto):** By its own `acceptance.md`, confirmed by the developer, with each case named by a test
in `test-acceptance-cases.sh` before the helper and guard code is written.

## Q19 — Non-goals
**Q:** Does the gate check that a test asserts what its case says?
**A (auto):** No. It checks that a test names the case. Whether it asserts it is review work.

## Q20 — Reversibility
**Q:** How does a project back out?
**A (auto):** `SPEC_ACCEPTANCE=off`. Removing the check is one env line, and the files stay.

## O1 — Authoring (overflow, developer)
**Q:** Who writes the 3-5 cases?
**A:** Claude drafts, the developer confirms (or edits) in one `AskUserQuestion`; their words are quoted on the Confirmed line.

## O2 — Count (overflow, developer)
**Q:** Is 3-5 a hard band?
**A:** Hard both ways. Under 3 or over 5 is denied; over 5 means the spec should be split.

## O3 — Tampering after confirmation (overflow, developer, threat surface)
**Q:** What happens if the cases are edited after confirmation?
**A:** Digest pin. The Confirmed line carries a digest of the cases; any later edit denies code until the developer confirms again.

## O4 — Test-first strength (overflow, developer)
**Q:** How hard does "a test per case first" bite?
**A:** Block production code. After confirmation only test files are editable until a test names each `<spec>-AC-<n>`.

## O5 — Rollout (overflow, developer)
**Q:** What happens to a project that syncs this mid-spec?
**A:** Grandfather started specs: a `tasks.md` with a ticked task and no `acceptance.md` is not blocked.

## O6 — Resource exhaustion (overflow, developer, threat surface)
**Q:** Cap the per-edit coverage scan?
**A:** Cache once all cases are named, keyed by the digest, so later edits skip the scan; a scan timeout fails open.
