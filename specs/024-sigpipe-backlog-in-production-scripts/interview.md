# Spec interview — 024-sigpipe-backlog-in-production-scripts

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no hardened trigger fires (no auth/PII/upload/new surface, no state machine).

## Q1 — Scope boundary
**Q:** Production scripts only, as the row says, or the self-tests too?
**A (auto):** Both. `test-register-bytes.sh` makes the default gate red, and it is the same idiom.

## Q2 — Which lines
**Q:** Only assertions (status read), or diagnostics as well?
**A (auto):** All of them. Under an inherited SIG_IGN a diagnostic writes the same stderr line.

## Q3 — Primary actor
**Q:** Who is hurt?
**A (auto):** Any project whose tests run a template script from .NET (msroute F008), and anyone reading `--all` output as a to-do list that never shrinks.

## Q4 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** Default gate exit 0, `--all --strict` exit 0 in the template, all touched self-tests green.

## Q5 — Replacement for `grep -q` on a variable
**Q:** Here-string or `case`?
**A (auto):** Here-string, as the gate recommends. Keep grep's flags unchanged so matching semantics stay identical.

## Q6 — Replacement for `head -N` in a substitution
**Q:** Which reader?
**A (auto):** `sed -n 1,Np`, which reads all its input and prints the same lines.

## Q7 — Variable N that can be 0
**Q:** `head -n "$NAME_LIMIT"` with `NAME_LIMIT=0`?
**A (auto):** `awk -v n="$NAME_LIMIT" 'NR<=n'`. `sed -n 1,0p` prints one line.

## Q8 — Byte cap (`head -c`)
**Q:** How to keep a byte-exact cap without a pipe to an early-exit reader?
**A (auto):** `{ head -c N; cat >/dev/null; }`, so the writer is always drained.

## Q9 — Empty-input equivalence
**Q:** `printf '%s' "$X" | grep` vs `grep <<< "$X"` differ when X is empty (zero lines vs one empty line). Does it matter?
**A (auto):** Only when the pattern matches the empty string. Each such pattern is checked against `""`; any that matches gets a `[ -n "$X" ] &&` guard.

## Q10 — `echo "$X"` vs here-string
**Q:** Is swapping `echo` behaviour-changing?
**A (auto):** Only for X = `-n`/`-e`/`-E`, where echo was wrong. Accepted as a fix.

## Q11 — Error semantics
**Q:** Any new messages?
**A (auto):** None. The gate's backlog message changes wording (FR-05) and the text says why.

## Q12 — Concurrency / ordering
**Q:** Any?
**A (auto):** N/A: no shared state is touched.

## Q13 — Integration points
**Q:** What consumes these scripts?
**A (auto):** Hooks (Claude Code), the sync (every project), .NET test suites downstream. The sync carries the fixes to projects.

## Q14 — Regression proof for F008
**Q:** How is the msroute failure pinned?
**A (auto):** A deterministic arm with a fixture past the pipe buffer under SIG_IGN (piped form leaks, here-string does not). The real `is_core` leaks only under load (0/40 at idle), so it cannot be the red case.

## Q15 — Regression proof for the backlog
**Q:** What keeps the backlog at zero?
**A (auto):** An arm in `test-no-sigpipe-assertions.sh` running `--all --strict` on the template tree.

## Q16 — Downstream behaviour of that arm
**Q:** A project's own scripts may carry the idiom. Does the arm fail there?
**A (auto):** It runs only in template mode; downstream it prints that it was skipped and why.

## Q17 — Make `--all` default?
**Q:** Change the gate's default population?
**A (auto):** No. It was tried and reverted (header). Out of scope.

## Q18 — Non-goals
**Q:** What is out?
**A (auto):** Fixing `is_core`'s regex matching (`grep -x` with dots); `-F` would be a behaviour change. It gets recorded as a finding only if it is shown to bite.

## Q19 — Reversibility
**Q:** Rollback story?
**A (auto):** Revert the commit. There is no data or migration.

## Q20 — Acceptance for "one at a time"
**Q:** How is M2's lesson honoured, checkably?
**A (auto):** Each file's edit is followed by `bash -n` and that file's self-test, and the run-log records the per-file results.
