# 073 — pipeline refresh 2026-09

Track: spec-only (refactor + hardening of harness machinery; no new entities, no new state machine).
Requested by the developer 2026-09-28; scope approved as P0+P1+P2 plus rollout.

## Problem

Measured 2026-09-28:

1. `scripts/sync-prompt.md` Step 5c iterates `for s in $CORE_SCRIPTS_LIST`. zsh does not word-split
   an unquoted parameter, so under zsh the loop sees one name, copies nothing and prints `[OK]` (row 037).
2. Four implementations of "the sync" disagree: `/project-wizard`, `/project-update`, `sync-template`
   and `template-autosync.sh`. They search for the template clone in four different lists, the wizard
   re-inits spec-kit unconditionally, `/project-update` Rule 6 contradicts its own line 13, and the
   core-hook list has 12 entries in two places and 11 in `sync-prompt.md`.
3. spec-kit is installed unpinned from `main`. Projects sit on 1.0.2.dev0 and 1.0.5.dev0 snapshots;
   the latest release is v1.0.12. The STOP-prompt patch warns on stderr when its anchor text moves,
   and autosync discards stderr.
4. The autosync hook records a failed sync as `ok` and stays silent for 6 hours.
5. On GNU coreutils, `project-maintenance.sh` runs `stat -f %m` first, which succeeds with the wrong
   meaning; the portability audit recommends that order. TLC ignores the jar the wizard installs.
   Nothing installs or refreshes the global `project-wizard`/`project-update` skills.
6. `.sync-version` is written by two readers and read by Step 0, while autosync maintains
   `.template-sync` (row 022).
7. Supply chain: no cooldown on npm/pnpm/uv/Dependabot, no scanner covering NuGet or pub lockfiles,
   no guidance for npm 12's install-script block.
8. Context: ~130 KB of unconditional rules load in every session.
9. Latency: three python PreToolUse guards start their own interpreter per edit; `bash-write-detect`
   runs `find` over the repo after every Bash call.
10. Tool docs trail Stryker.NET 5, xUnit v3 4.0, Playwright 1.63, TLA+ tools 1.8; no step installs
    Playwright browsers.

## Requirements

- R1 Step 5c copies every CORE script under bash and zsh, and a test proves it under both.
- R2 Wizard, update and sync-template perform the mechanical sync by calling `template-autosync.sh`;
  one clone-discovery function, honouring `$CLAUDE_TEMPLATE_DIR` first; one core-hook list.
- R3 spec-kit version lives in `scripts/speckit-version` (one line, a tag). Every install path reads
  it; re-init happens only when the installed version differs. A failed STOP patch is reported on
  stdout and in the autosync summary.
- R4 A failed or timed-out autosync is recorded as failed and reported at the next session start.
- R5 GNU `stat` order is correct and the audit enforces the correct order; TLC finds
  `~/.local/lib/tla2tools.jar` and uses `timeout`/`gtimeout`; `scripts/install-global-skills.sh`
  installs and refreshes the global skills on macOS, Linux and Git Bash.
- R6 Step 0 reads `.template-sync`; `.sync-version` is no longer authoritative.
- R7 Wizard/update write supply-chain defaults (cooldowns, npm 12 note) and `project-freshness.sh`
  runs osv-scanner when present, saying so when absent.
- R8 Unconditional rules shrink; every BLOCKING statement stays reachable (hooks unchanged).
- R9 Per-edit and per-Bash hook cost falls, measured before and after; all hook tests stay green.
- R10 Docs match current tool versions; the wizard installs Playwright browsers for Playwright stacks.
- R11 Roll out to the 15 template-managed projects: sync, pinned spec-kit, verify, commit sync paths
  only, push.

## Non-goals

- The six unmanaged repos. `blockReadsOutsideWorkingDirectories` (breaks template-clone reads).
  Trivy. Apalache. Wiring the 15 local-LLM quality hooks (row 020).

## Acceptance

All existing harnesses green; new tests for zsh Step 5c, GNU `stat`, clone discovery and the failed-
sync verdict; a Linux container run of the sync and the portability audit; 15 projects stamped at
the new template HEAD with spec-kit at the pinned tag.

## Clarifications

### Session 2026-09-28
- Q: Do the rule long-forms become CORE (always overwritten)? → A: No. Add-if-missing, then manifest-protected like any doc — CORE would need guard, `--owed` and `--accept-local` arms for a third class, and would overwrite a project's local edit silently (review finding M1).
- Q: Does autosync bring projects to the spec-kit pin at SessionStart? → A: No. It reports the mismatch on every run; `speckit-sync.sh` does the install and init — network, tens of seconds and a rewrite of speckit skills do not belong in a SessionStart budget or an unrequested commit.
- Q: Merge the three python PreToolUse guards into one dispatcher? → A: Not in this spec. Cheap in-script early exits cut per-call cost 35–55% under load; a dispatcher is decided on idle-machine numbers from `scripts/bench-hooks.sh`.
