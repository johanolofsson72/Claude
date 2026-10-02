# Spec interview — 086-maintenance-and-gate-blind-spots

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: spec-only, no hardened trigger (no auth, PII, upload, new external
surface, state machine or entity). Every question below had a defensible recommendation.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the sixteen findings as R1–R15. Out: moving Next past a blocked row, rewriting the
assignment-shaped SIGPIPE sites, editing msroute, checking what a hook does once it resolves.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer reading a maintenance pass, a gate or the SessionStart banner that says
"clean" or nothing about something it never looked at.

## Q3 — NOT SCANNED severity (F033)
**Q:** Is every NOT SCANNED a finding?
**A (auto):** Secret passes yes: an unscanned secret pass is the exact gap the pass exists for.
`deps(…)` unchecked manifests is a note, because a manifest osv-scanner cannot read stays unread and
a permanent finding teaches people to ignore the pass.

## Q4 — Missing CORE script (F032)
**Q:** Finding or note when §2c or §6b cannot find its script?
**A (auto):** `[SETUP]` finding, the shape §6c and §1 already use. A missing CORE file is a sync
defect, and the fix is one command.

## Q5 — Where the lenient reader lives (F051)
**Q:** Copy the lenient JSON reader into the bash, or call the Python?
**A (auto):** Call it: a `break <file>` mode on `stryker_guard.py`, so both read the config the same
way. Missing script or python3 echoes nothing, as today.

## Q6 — Which heredoc stripper survives (F052)
**Q:** Keep the multi-terminator form or the offset-preserving one?
**A (auto):** Both properties in one helper in `bash_write_targets.py`: every heredoc on a line, in
order, bodies blanked so offsets hold. `stryker_guard.py` imports it; blank lines are harmless to
its tokenizer.

## Q7 — When CORE self-tests run (F023)
**Q:** Every pass, `--suite`, or `--full`?
**A (auto):** `--full`. Fifty-odd self-tests take minutes, the same class of cost as the mutation
pass. Each is bounded (300 s default).

## Q8 — CORE self-tests under --unattended
**Q:** Do they need `--trust` like ratchets and the suite?
**A (auto):** No. They are CORE, delivered by the sync like every `validate-*.sh` the pass already
runs unpinned. The trust store covers project-authored commands.

## Q9 — The template itself (F023)
**Q:** Run them in the template repository too?
**A (auto):** No, a note: there they are the template's own suite, which `--suite` runs.

## Q10 — What "resolves" means (F001)
**Q:** How is a hook command judged without running it?
**A (auto):** Tokenize it, expand only the variables Claude Code sets (`CLAUDE_PROJECT_DIR`,
`CLAUDE_PLUGIN_ROOT` for plugins) plus `HOME` and `~`, never inside single quotes. Then the program
must be found (path or PATH) and an interpreter's script argument must exist. A `$` left over is
unresolved.

## Q11 — Which hooks (F001, F003)
**Q:** Which configuration files are read?
**A (auto):** Project `settings.json` and `settings.local.json`, user `~/.claude/settings.json`, and
`hooks/hooks.json` of each plugin enabled in either settings file (install paths from
`~/.claude/plugins/installed_plugins.json`). The `args` array form is read too.

## Q12 — Which hooks get the output-channel check (F003)
**Q:** All hooks or project-authored only?
**A (auto):** Project-registered hooks whose script is inside the project and is not CORE. CORE hooks
are already covered by `test-hook-channels.sh`; user and plugin hooks are not ours to fix.

## Q13 — Blocked Next row (F025)
**Q:** Skip a row whose `needs` is unmet, or flag it?
**A (auto):** Flag it. The guards resolve the active spec through `spec_active.py`; a banner that
skipped would point at a different row than the guards gate. An unmet dependency on the next row
means the register order is wrong, which is a register rewrite the developer decides.

## Q14 — Unparseable needs prose (F025)
**Q:** What about "needs 074 + five ordinary specs ticked under its ledger"?
**A (auto):** Ids in the clause are checked against ticked rows. The whole clause is quoted with
"check this before starting", because no script can check the prose half.

## Q15 — Assignment-shaped SIGPIPE sites (F027)
**Q:** Fix all ~79 sites, or make the gate see them?
**A (auto):** Make the gate see them: counted as leaks in every `--all` report, failing under the
new `--leaks`. A bulk rewrite turned msroute's suite red (M2); one finding records the sites.

## Q16 — Leak scope
**Q:** Does a pipe inside `"$(…)"` count?
**A (auto):** Yes. Quoting the substitution does not change the pipe inside it, and today the quote
tracker hides those.

## Q17 — Root syntax for file globs (F005)
**Q:** A new file, a prefix syntax, or a glob in the root?
**A (auto):** A glob in the last segment of the root (`scripts/test-*.sh`). It reads as what it
selects and needs no new file.

## Q18 — Empty glob root (F005)
**Q:** A glob that matches nothing?
**A (auto):** Refused, exactly like a missing root. A root that reads zero files reports every
claimed scenario uncovered for a trivial reason.

## Q19 — CLAUDE.md as a source (F060)
**Q:** Which CLAUDE.md mention wins?
**A (auto):** Only when exactly one distinct `dotnet test <path>` without `--filter` names an
existing, non-E2E test project. Two or more is the ambiguity the detector already declines.

## Q20 — Empty test projects (F060)
**Q:** How is "no sources" judged?
**A (auto):** No `.cs` file under the project's directory (pruned as the rest of the walk). Such a
project runs zero tests and cannot verify anything.

## Q21 — Quoting form (F069)
**Q:** `printf %q` or POSIX quotes?
**A (auto):** POSIX single quotes. `template-sync-verify.sh` runs the line with `sh -c`, and `%q` can
emit bash-only `$'…'`. Plain paths stay unquoted so existing output does not change.

## Q22 — Key derivation (F068)
**Q:** How is the per-root key made, portably?
**A (auto):** `<basename>-<cksum of the full path>`. `cksum` is POSIX and present in Git Bash. The
basename stays in the name so a person can still tell the files apart.

## Q23 — Unknown cwd (F070)
**Q:** A TLC process whose working directory cannot be read?
**A (auto):** Left alone and named. Killing what cannot be attributed is the defect; a manual
`--any-project` covers the runaway nobody owns.

## Q24 — F059 and F010 template side
**Q:** What does the template change, given both scripts that broke are project-side?
**A (auto):** Documentation the next project reads (testing.md) and a header line on
`test-stryker-guard.sh`. The msroute script gets a notice in the status summary, not an edit: it
has uncommitted work and is another repository.

## Q25 — Reversibility
**Q:** Migration or rollback?
**A (auto):** None needed beyond F068's legacy PATH file, which is removed only when no remaining
cron line uses it. Every other change is reporting.
