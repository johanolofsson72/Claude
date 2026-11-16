# Spec interview — 100-kill-surviving-mutants-2

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: spec-only track, no hardened trigger. The work is test fixtures and
equivalence markers on existing lines; no auth, PII, upload, new external surface, state machine,
concurrency or entity. Every question had a defensible recommendation, most of them set by 092.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the survivors named by F123, F124, F125, F129, F136, F138, F150, F151, F152 and
F160, mapped by content to the current tree, plus arming the guard suites' allow cases with rc==0
(F151). Out: fresh sampling, F171 and F195 (open, not on the row), production behaviour changes
beyond the smallest one that makes a line's intent testable.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer reading a mutation score. Every checkpoint since H4 re-reports the same
survivors, so the gate's headline hides known gaps and each checkpoint spends time re-finding them.

## Q3 — Line drift
**Q:** The findings cite line numbers from H4, H5, 090, 091 and 095. Which lines are measured?
**A (auto):** Each one mapped by content (`git show <commit>:<file> | sed -n <L>p`, then the same text
in today's tree), as 092 did. The map goes in spec.md.

## Q4 — Lines that no longer exist
**Q:** What if a survivor's line was rewritten since (F151's core-owed-tick-guard L220)?
**A (auto):** Measure the line that now carries the same role. If the role is gone, say so in the
map and drop it.

## Q5 — How allow cases are armed (F151)
**Q:** Through `hook_verdict OUT RC` or per-suite checks?
**A (auto):** Through the suite's own run helper capturing `$?` and passing it to `hook_verdict`, so
every allow (`none`, `allow`) case also asserts exit 0 without touching each call site. 092 R2 added
the second argument for exactly this.

## Q6 — Which suites
**Q:** Which suites get the rc arming?
**A (auto):** The ones whose helpers are still rc-blind and that own a module on the row:
test-core-owed-tick-guard.sh, test-core-machinery-guard.sh, test-settings-edit-guard.sh and the
direct `hook_verdict "$OUT"` calls in test-trust-anchor-guard.sh. Suites already rc-aware stay.

## Q7 — Is exit 1 on an allow path really observable?
**Q:** Is an `exit 0`→`exit 1` mutant on an allow path a real bug or equivalent?
**A (auto):** Real. Exit 1 is a non-blocking error the CLI shows on stderr every call, and on a
fail-open notice path it drops the additionalContext JSON. F151 already argued this; kill it.

## Q8 — Equivalence marker
**Q:** How is a mutant declared equivalent?
**A (auto):** `# mutant-equivalent: <reason>` on its line, read by run-mutation-gate.sh. The reason
must be a concrete argument, checked in review. Candidates named by F152: trust-anchor `cat || true`
and the `HIT -eq 0 && -f` line.

## Q9 — Confirming equivalence
**Q:** Is a marker allowed without checking?
**A (auto):** No. Per mutation-timeouts Trap 5, apply the mutant by hand, run the suite, and reason
about every input before marking. A marker that hides a killable mutant is a finding.

## Q10 — Timeouts
**Q:** What about F124's L1091 `-n`→`-z` timeout?
**A (auto):** Re-measured with the rest. A timeout is not a kill; if it persists, the case gets a
bound of its own so the mutant fails fast, as 092 R6 did for freshness.

## Q11 — Which modules lack a target row
**Q:** trust-anchor, core-owed-tick, core-machinery, bash-write-guard and cloud-maintenance are not
in the default target table. Add them?
**A (auto):** No. Measure through a `MUTATION_TARGETS` file, as H5 and H6 did. Widening the nightly
table changes its run time and is not this row's goal.

## Q12 — Contract test vs. end-to-end
**Q:** F138's private_copy `return 1`→`0` is invisible end to end. Accept?
**A (auto):** Already killed by T24's direct contract test per F138. Re-measure; if alive, test the
function's contract directly.

## Q13 — Error, empty, loading states
**Q:** What are the four states here?
**A (auto):** Success: a mutant is killed (the suite exits non-zero). Error: a red baseline makes
the run UNMEASURED (exit 2), never a score. Empty: a line with no sites is reported, not scored.
Loading: progress on stderr. None of this changes; the spec only adds cases.

## Q14 — Target score
**Q:** What is the bar?
**A (auto):** Every measured site killed or marked with a reason that holds; the re-measured
`--lines` score at least 95%, the 092 bar, with zero timeouts counted as kills.

## Q15 — Suite time
**Q:** Can new cases slow the suites?
**A (auto):** Each case runs a guard once or a script under a bound. No case may add more than a few
seconds; anything that can loop runs under the runner's timeout probe.

## Q16 — Where cases live
**Q:** New suite or existing ones?
**A (auto):** Existing suites that already own the behaviour. No new test file unless a module has
none (cloud-maintenance.sh is covered by test-maintenance-trust.sh).

## Q17 — Cross-platform
**Q:** Must the new cases run on Linux and Git Bash?
**A (auto):** Yes. Same constructs as the suites they join; no GNU-only flags, no `brew` paths.

## Q18 — Findings disposition
**Q:** What happens to F123–F160 on completion?
**A (auto):** They are already `[x]` (rowed to 100). Any new survivor or doubtful equivalence is
recorded with `finding.sh --add`, never rowed.

## Q19 — Test IDs
**Q:** How are new cases named?
**A (auto):** Each case label carries `[100]` and the line it arms, so a later reader can find why
it exists.
