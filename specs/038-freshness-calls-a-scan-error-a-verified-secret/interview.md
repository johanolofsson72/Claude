# Spec interview — 038-freshness-calls-a-scan-error-a-verified-secret

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no hardened trigger fires (no auth/PII/upload/new surface, no state machine, no new entity, 2 source files).

## Q1 — Scope boundary
**Q:** Does the spec touch anything besides section 1 of `project-freshness.sh`?
**A (auto):** Only its self-test. The maintenance pass reading NOT SCANNED as clean is a separate gap and goes to a finding.

## Q2 — Primary actor
**Q:** Who is hurt?
**A (auto):** A developer running the freshness or maintenance pass on a repo trufflehog cannot scan: before the first commit, or on a trufflehog error. They are told to rotate credentials that were never exposed.

## Q3 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** Clean and found-secret runs behave exactly as today. A run trufflehog could not complete says so, shows why, and is neither clean nor a finding.

## Q4 — Which exit means findings
**Q:** How is "results found" recognised?
**A (auto):** Exit 183, the code `--fail` documents. Measured on 3.95.5.

## Q5 — Unknown exit codes
**Q:** An exit code that is neither 0 nor 183?
**A (auto):** The third state. An unrecognised code is never read as clean and never as a finding.

## Q6 — Label
**Q:** Which tag for the could-not-scan line?
**A (auto):** `[WARN]`, the tag the key-shape pass uses for an incomplete scan (spec 023). `[FINDING]` would count it; `[SKIP]` implies a choice not to run.

## Q7 — SUMMARY wording
**Q:** What does `Secrets:` say?
**A (auto):** `scan failed (exit N) — <reason>`. The reason is trufflehog's first error line, cut to one line.

## Q8 — RESULT line
**Q:** What does RESULT say when only the scan failed?
**A (auto):** `no findings, but NOT SCANNED: trufflehog`. The NOT_SCANNED mechanism already exists; reuse it.

## Q9 — Script exit code
**Q:** Does a failed scan make the script exit non-zero?
**A (auto):** No. 1 means findings; NOT SCANNED exits 0 today (spec 023). Changing that changes what project-maintenance.sh reads, which is out of scope.

## Q10 — --fail-on-scan-errors
**Q:** Add the flag?
**A (auto):** Yes. Measured: without it, a scan that errors exits 0 and reads clean. That is the reverse conflation the diagnosis names.

## Q11 — Old trufflehog without the flag
**Q:** What if an older trufflehog rejects `--fail-on-scan-errors`?
**A (auto):** It exits non-zero with "unknown flag" on stderr, which lands in the third state with that reason shown. Visible, and `brew upgrade` fixes it. No version probe.

## Q12 — stderr
**Q:** Is trufflehog's stderr still shown?
**A (auto):** Yes, on every path. It is captured to a temp file so the reason can be quoted, then replayed.

## Q13 — Empty repo
**Q:** Scan the working tree instead when the repo has no commits?
**A (auto):** No. The warn line adds a hint that there is nothing in history yet; the scan runs properly after the first commit. A fallback changes what is scanned (node_modules etc.) and is not what the row asks for.

## Q14 — Both call sites
**Q:** Is the `filesystem` call site fixed too?
**A (auto):** Yes, through one helper. The diagnosis names both.

## Q15 — Tests
**Q:** How is it tested without a real secret?
**A (auto):** Stub trufflehog binaries with chosen exit codes and stderr, through the existing `FRESHNESS_TRUFFLEHOG` seam. One case runs the real trufflehog on an empty repo when it is installed.

## Q16 — Red on HEAD
**Q:** Which cases must fail on HEAD?
**A (auto):** The exit-1 cases (git and filesystem) and the flag check. The 0 and 183 cases pin today's behaviour.

## Q17 — Portability
**Q:** Cross-platform constraints?
**A (auto):** bash 3.2, Git Bash. `mktemp` with a fallback, no process substitution, no `mapfile`. `validate-portability.sh` on the changed script.

## Q18 — Non-goals
**Q:** Anything explicitly not done?
**A (auto):** No change to the key-shape, npm, OSV or .NET passes. No change to project-maintenance.sh.
