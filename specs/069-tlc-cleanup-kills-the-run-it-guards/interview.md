# Spec interview — 069-tlc-cleanup-kills-the-run-it-guards

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (one CORE script, one harness, one skill paragraph; no entity, no surface), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: which processes `tlc-cleanup.sh` kills, its flags and exit codes, a harness with sabotage arms, and the `/tla` cleanup paragraph. Out: the hook wiring in settings.json, a pidfile protocol, the local-llm TLC translate hook.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A session running `/tla`, directly or in a subagent. Its TLC command dies with 144 before it starts, or a live run dies when another agent stops (ekofak 005, hireflow 017).

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** A `/tla` run finishes while other agents stop around it, the hooks exit 0, and a TLC process that outlived its 300 s bound is still killed at the next hook.

## Q4 — What is a TLC process
**Q:** How is a TLC process recognised?
**A (auto):** argv[0] basename is `java` (or `java.exe`) and the arguments contain `tla2tools` or `tlc2.TLC`. Matching the whole command line is the defect.

## Q5 — What makes one killable
**Q:** Which TLC processes may a hook kill?
**A (auto):** Only those older than the bound, 320 s by default. Younger ones are live runs under a `timeout` that will end them.

## Q6 — Why 320
**Q:** Where does the default come from?
**A (auto):** The skill's `timeout -k 10 300`: 300 s plus 10 s kill grace, plus 10 s slack for `ps` granularity and JVM exit.

## Q7 — Manual full kill
**Q:** Can a developer still kill everything?
**A (auto):** Yes, `--all`. It is never passed by a hook.

## Q8 — Test scoping
**Q:** How does a test avoid killing a real run on the machine?
**A (auto):** `--only <text>` narrows the match to processes whose arguments also contain the text. Every harness case that kills passes a unique token.

## Q9 — Four observable states
**Q:** Success, error, empty, loading?
**A (auto):** Success: one line per kill. Error: exit 1 naming the survivor, exit 3 with a stderr reason when `ps -o` is unavailable. Empty: silent exit 0. Loading: n/a, it finishes in at most about a second.

## Q10 — Error semantics
**Q:** What if `ps` cannot list processes (Git Bash)?
**A (auto):** Exit 3 with the reason on stderr. The hooks swallow it (`; true`), and a manual run says it did nothing.

## Q11 — Signal escalation
**Q:** TERM then KILL, how long between?
**A (auto):** One second, as before, but only when something was signalled. The old script slept on every Stop, even with nothing to kill.

## Q12 — Concurrency
**Q:** Two hooks run the cleanup at once?
**A (auto):** Harmless. A PID already gone makes `kill` fail quietly; the survivor check re-lists processes before it reports.

## Q13 — PID reuse
**Q:** Can the SIGKILL hit a reused PID?
**A (auto):** The survivor check re-applies the same filter (java, pattern, age) before the SIGKILL, so a reused PID of a different program is not hit.

## Q14 — Fleet delivery
**Q:** How does the fix reach projects?
**A (auto):** `tlc-cleanup.sh` is in CORE_SCRIPTS, so template autosync updates it. The settings.json wiring is left alone (FR-07).

## Q15 — Acceptance criteria
**Q:** What proves it?
**A (auto):** AC1–AC10 in the spec, with the real PostToolUse hook command read from settings.json as the integration case, and two sabotage arms that must each turn a case red.

## Q16 — Non-goals
**Q:** What does this not attempt?
**A (auto):** Catching a renamed jar run with `-jar`, and killing orphans by parent PID (not portable on Linux subreapers).

## Q17 — Reversibility
**Q:** Rollback?
**A (auto):** Revert the one script. No state or migration.
