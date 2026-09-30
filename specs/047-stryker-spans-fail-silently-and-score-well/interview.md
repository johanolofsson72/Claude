# Spec interview — 047-stryker-spans-fail-silently-and-score-well

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Hardened (size trigger and a new PreToolUse deny on Bash), so the overflow asks the
developer about the deny surface.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: a pattern check and a live-process check in one helper; section 5 of
project-maintenance.sh; a PreToolUse Bash guard; testing.md. Out: StrykerJS patterns, rewriting
project runners, rows 053/041/043.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer or a Claude session that scopes a Stryker run with a span or a mistyped glob,
or runs `dotnet test` beside it, and reads a clean score that measured nothing.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** The ighweld pattern `'**/X.cs{845-1080}'` produces a finding in maintenance and a deny in
the hook; `dotnet test` beside a live Stryker is denied with a sentence that names the process.

## Q4 — Which patterns count as wrong
**Q:** Which verdicts exist?
**A (auto):** `badspan` (brace group not `{N..M}`, N ≤ M), `nomatch` (include glob matching no `.cs`),
`span` (well-formed span). An exclude matching nothing is fine.

## Q5 — Pattern sources
**Q:** Where are patterns read from?
**A (auto):** Every committed `stryker-config*.json` (`mutate` under `stryker-config` or top level) and
literal `-m`/`--mutate` tokens in `scripts/run-mutation-gate.sh`; in the hook, the command itself.

## Q6 — Glob matching base
**Q:** Relative to what does a glob match?
**A (auto):** Lenient: the file's path relative to the root, or any trailing run of its segments. The
check claims "matches nothing" only when nothing could match.

## Q7 — Glob dialect
**Q:** Which glob features?
**A (auto):** `**` (any depth, including zero), `*` and `?` (within a segment), `[...]` classes. That is
what Stryker.NET's DotNet.Glob parses in practice; braces after the glob are spans.

## Q8 — Four observable states (maintenance)
**Q:** What does each state look like in section 5?
**A (auto):** Success: no finding. Error: one `[MUTATION]` finding per bad pattern, naming config,
pattern and consequence. Empty: no config with `mutate` → nothing. Unmeasured: python3/helper missing →
a finding saying unchecked.

## Q9 — Four observable states (hook)
**Q:** And in the hook?
**A (auto):** Allow is silence; deny is a well-formed PreToolUse deny with a reason naming the rule and
the override; unreadable input is allow (fail open); no loading state (synchronous).

## Q10 — Live detection
**Q:** How is "live in this project" decided?
**A (auto):** `ps -Ao pid=,args=`, args matched for Stryker or a `dotnet` build verb, then the PID's cwd
(`/proc/PID/cwd`, else `lsof -a -p PID -d cwd -Fn`) inside the root.

## Q11 — Daemons
**Q:** MSBuild node-reuse workers and VBCSCompiler?
**A (auto):** Not matched. They outlive every build.

## Q12 — Which commands the hook treats as Stryker
**Q:** Which command shapes start Stryker?
**A (auto):** `dotnet stryker`, `dotnet-stryker`, `run-mutation-gate.sh`. `project-maintenance.sh --full`
checks for itself.

## Q13 — Overrides
**Q:** What are the escape hatches?
**A (auto):** `STRYKER_GUARD=off` (command or environment) disables the hook; `STRYKER_SPANS_ARE_CHARACTERS=1`
accepts a well-formed span. Both are named in the deny text.

## Q14 — Fail-open inventory
**Q:** Where does the hook fail open?
**A (auto):** No python3, no jq, unparseable JSON, empty command, no `ps`, a cwd it cannot read.

## Q15 — Stamping
**Q:** Does a refused `--full` run stamp the mutation job?
**A (auto):** No. Nothing was measured, so the job stays due (F044 shape).

## Q16 — Runtime-assembled patterns
**Q:** A `-m "$PATTERN"` in a runner?
**A (auto):** Skipped. Guessing what `$PATTERN` expands to would invent a finding.

## Q17 — Non-functional limits
**Q:** Cost?
**A (auto):** The hook exits in bash before python unless the command mentions `dotnet`, `stryker` or
`run-mutation-gate`. The file walk prunes `bin`, `obj`, `node_modules`, `.git`, `StrykerOutput`. `lsof`
runs only for PIDs whose args already matched.

## Q18 — Reversibility
**Q:** Rollback?
**A (auto):** Unwire the hook from settings.json; section 5's check is additive findings. No data.

## Q19 — Acceptance
**Q:** Measurable done?
**A (auto):** FR-01..14 each have an arm; hand mutants on the helper, hook and section 5 are killed
at ≥80%; the maintenance suite is still green.

## Q20 — Overflow: deny or warn
**Q:** Should the hook DENY a `dotnet test` while Stryker runs in the project, or only warn?
**A:** Deny (developer, 2026-09-30).

## Q21 — Overflow: valid spans
**Q:** Should a well-formed `{N..M}` span be denied/reported, or only malformed ones?
**A:** Report and deny, with STRYKER_SPANS_ARE_CHARACTERS=1 as the override (developer, 2026-09-30).
