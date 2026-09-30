# 069 — tlc-cleanup-kills-the-run-it-guards

Track: spec-only. A fix to one CORE script, no entity, no state machine, no new external surface.
Touches `scripts/tlc-cleanup.sh`, a new harness `scripts/test-tlc-cleanup.sh`, and the cleanup
paragraph of `.claude/skills/tla/SKILL.md`. No hardening trigger.

Evidence: ekofak spec 005 (2026-09-28), hireflow spec 017 (2026-09-30). Diagnosis in
`specs/INDEX.pending.md`.

## The defect

`scripts/tlc-cleanup.sh` runs `pkill -f "tla2tools"` and `pkill -f "tlc2.TLC"`. It is wired from
four hooks: PostToolUse(Bash) when the command mentions `tlc|tla2tools`, Stop, SubagentStop and
SessionEnd. (The diagnosis says PreToolUse; the wiring in `.claude/settings.json` is PostToolUse.
The failures are the same.) `pkill -f` matches every process whose full command line contains the
text, so it hits three kinds of process it should not:

1. **The shell running it.** The hook's own `bash -c` contains `tlc|tla2tools`, and so does the Bash
   tool shell of any command that runs TLC. `pkill` kills them: exit 144, the 056 trap.
2. **A live run.** A `/tla` subagent's TLC run is killed the moment any other agent stops, or any
   other Bash command that mentions TLC finishes. hireflow lost four runs (exit 137/143/144).
3. **Anything else that mentions the jar**, such as an editor, a `grep` or a `curl` downloading it.

The workaround used in both projects was to rename the jar so the pattern no longer matches, which
also switched the cleanup off.

## Requirements

- **FR-01** A process is a TLC process only when its program (argv[0], basename, `.exe` stripped)
  is `java` and its arguments contain `tla2tools` or `tlc2.TLC`. A shell, `timeout`, an editor or
  a grep whose command line contains the text is never a TLC process.
- **FR-02** By default the script kills only TLC processes older than the run bound. The `/tla`
  skill bounds every run with `timeout -k 10 300`, so a TLC process past that has escaped the
  bound; that is the runaway the cleanup exists for. The default is 320 s (300 + 10 kill grace + 10
  slack), overridable with `--max-age N` or `TLC_MAX_SECONDS`.
- **FR-03** `--all` kills every TLC process regardless of age, for manual use when the developer
  knows no run is live. No hook passes it.
- **FR-04** `--only <text>` narrows the match to processes whose arguments also contain `<text>`
  (a spec name, a scratch dir). `--dry-run` prints what would be killed and kills nothing.
- **FR-05** SIGTERM first; SIGKILL for survivors after one second; the sleep happens only when
  something was signalled. With nothing to kill the script is silent and exits 0 immediately.
- **FR-06** Every kill is reported on stdout (`tlc-cleanup: killed pid <p> (age <s>s) <args>`).
  Exit 0 when nothing survives, 1 when a process survives SIGKILL, 2 on a bad argument, 3 when
  `ps` cannot list processes with `-o` (Git Bash). Exit 3 prints why on stderr, so the cleanup never
  looks like it ran when it did not.
- **FR-07** The hook wiring in `.claude/settings.json` does not change. The fix travels to the fleet
  through the CORE script sync; a settings change would need the merge sites.

## Acceptance

- AC1 A young TLC run (java, `tla2tools` in args, age < max) survives a default run.
- AC2 The PostToolUse(Bash) hook command from `.claude/settings.json`, fed a payload whose command
  mentions `tla2tools`, exits 0; the young run survives it; a shell that calls the script with
  `tla2tools` in its own command line keeps running (no 144).
- AC3 A TLC run older than `--max-age` is killed and reported.
- AC4 A non-java process whose arguments contain `tla2tools` and `tlc2.TLC` survives even `--all`.
- AC5 `--all` kills a young TLC run.
- AC6 `--dry-run` lists the run and leaves it alive.
- AC7 With nothing to kill: exit 0, no output, under one second.
- AC8 A TLC process that ignores SIGTERM is killed with SIGKILL.
- AC9 An unknown argument exits 2.
- AC10 Sabotage: dropping the argv[0] check or the age check turns a case red.

## Clarifications

### Session 2026-09-30

- Q: Pidfile per run, or age? → A: Age. A pidfile needs the skill to write it and every copy of
  the skill in the fleet to agree on where. A subagent killed mid-run leaves a stale pidfile whose
  PID may be reused. The age bound already exists (the skill's 300 s `timeout`), so a process past
  it is runaway by definition, and it needs no state.
- Q: Also kill orphans (ppid 1) of any age? → A: No. On Linux an orphan is re-parented to the
  nearest subreaper (systemd --user), not PID 1, so the test is not portable, and an unbounded run
  on macOS without coreutils is still caught at 320 s.
- Q: Drop the PostToolUse(Bash) trigger as the diagnosis suggests? → A: No. With FR-01 and FR-02
  it is harmless, and it catches a runaway at the next TLC command instead of at the end of the
  turn. Changing settings.json would also need the fleet merge sites (FR-07).
- Q: Does a renamed jar (`java -jar modelcheck.jar`) still escape the cleanup? → A: Yes, unless it
  is run with `-cp … tlc2.TLC` as the skill does. The workaround is no longer needed, so this is
  documented rather than matched.
