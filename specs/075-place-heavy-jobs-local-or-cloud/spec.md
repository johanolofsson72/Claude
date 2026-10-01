# 075 — place heavy jobs local or cloud

Track: light, hardened (size trigger: one new tracked config, two new scripts, edits to
project-maintenance.sh, maintenance-due.sh, maintenance_ledger.py, a rule and a doc; the cloud
routine is also a new surface that writes to the repository). Requested by the developer
2026-09-29; started 2026-10-01 on the developer's instruction to have it in place by morning.

## Problem

074 measures how long each maintenance job takes, how much memory it peaks at, and where it ran.
Nothing uses the numbers. Every job still runs on the Mac (and David's Linux machine) when
`maintenance-due.sh` says "Run now: bash scripts/project-maintenance.sh --full", including Stryker,
which is the job the developer wants off the laptop.

Moving a job needs three things that do not exist:

1. A decision per job, written down where the scripts can read it.
2. A way to run the cloud-placed jobs in a Claude cloud session: the .NET SDK is not on the VM.
3. A way to get the results back. A cloud VM's `.claude/state/` dies with the session, and a routine
   may push only to `claude/*` branches (code.claude.com/docs/en/routines, checked 2026-10-01).
   Without a return path, `maintenance-due.sh` on the Mac keeps saying mutation is due forever, and
   the developer runs it locally again.

## Requirements

- R1 **Placement table.** The template's decision ships as `scripts/workload-placement.tsv` (CORE:
  autosync ships `scripts/` and `.claude/rules/` only). One line per job: `job<TAB>place<TAB>reason`;
  `place` is `local` or `cloud`; `#` starts a comment. A project overrides it line by line in
  `.claude/workload-placement.tsv` (project-owned, never overwritten by sync). A job with no line is
  `local`. An unknown place is an error the scripts name, never a silent `local`.
- R2 **The decision rule** (recorded in `workload-placement.md`, applied to the ledger numbers):
  a job is `cloud` only when all hold — (a) it needs nothing local (browser baselines, `docker
  compose` with local config, local-only secrets, Ollama models, a human decision); (b) its measured
  max RSS is under 12 GB; (c) its median local run is at least 5 minutes, so a cloud session is
  worth its start-up cost. Everything else is `local`. A job without measurements stays `local`.
- R3 **`project-maintenance.sh --placed`** runs only the placed jobs whose place matches where it
  runs (`cloud` when `CLAUDE_CODE_REMOTE=true`, else `local`). A job placed elsewhere prints one
  line naming where it runs instead and is neither run nor stamped. Without `--placed`, nothing
  changes: an explicit full run still runs everything.
- R4 **`maintenance-due.sh` names the place.** A due job placed in the cloud is listed with
  "(Claude cloud)", and the "Run now" line becomes `--full --placed` plus one line on how to start
  the cloud half. With no cloud-placed due job the output is unchanged.
- R5 **Cloud entry point.** `scripts/cloud-maintenance.sh` is what a routine or a manual cloud
  session runs. It refuses to run outside the cloud (unless `--force-local` for tests), installs
  the .NET SDK when a solution exists and `dotnet` is missing (`scripts/cloud-setup.sh`, idempotent,
  also usable as the environment's setup script), runs `project-maintenance.sh --full --suite
  --placed`, then publishes the results.
- R6 **Return path.** Publishing writes the run's ledger lines and stamps to a tracked results file
  `.claude/cloud-results/<UTC timestamp>.tsv` on branch `claude/maintenance-results`, commits and
  pushes that branch only. It never touches the default branch. Locally,
  `scripts/cloud-maintenance.sh --pull` fetches the branch, appends unseen ledger lines to the local
  ledger, applies stamps through `maintenance-due.sh --stamp`, and records which files it imported
  so a second pull is a no-op. SessionStart does not fetch (no network at session start); the due
  banner's cloud line names `--pull`.
- R7 **Rules follow.** `spec-hardening.md` "Local only." becomes "Local or Claude cloud, never
  GitHub Actions." `workload-placement.md` moves from "measuring" to "decided", with the table, the
  numbers it was decided from, and how to set up the routine.
- R8 New scripts and the placement table are CORE (`template-autosync.sh`).

## Non-goals

Creating the cloud routine itself (an account-level action the developer takes once, with the
command written in the doc). Moving any job to GitHub Actions. Changing due thresholds. Running
Ollama-dependent jobs in the cloud. Splitting a suite into cloud-able and local halves.

## Acceptance

- `test-workload-placement.sh` green: table parsing, override, unknown place, `--placed` filtering
  both ways, due-banner wording, publish to a branch in a fixture repo with a bare remote, pull
  idempotence, default branch untouched.
- `test-project-maintenance.sh`, `test-maintenance-due.sh`, `test-maintenance-ledger.sh` stay green.
- Sabotage set: every guard above has a mutant the suite kills.
- Threat model below; security-scanner and `/security-review` run, each flag decided.

## Clarifications

### Session 2026-10-01 (auto-picked)

- Q: Does `--placed` also filter the cheap always-on checks (portability, the register greps)? → A: Only jobs that have a line in the placement table. Unlisted jobs run as before, so a table with no lines changes nothing.
- Q: Does a cloud-placed job still run locally on a plain `--full`? → A: Yes. `--placed` is opt-in; the due banner recommends it. An explicit full run is the developer asking for everything.
- Q: Which stamp key does an imported mutation result write? → A: The same key the local pass stamps (`mutation`, `suite`), via `maintenance-due.sh --stamp`, so due-ness has one source of truth.
- Q: Is a failed cloud run (rc != 0) stamped on import? → A: No. Only the stamps the pass itself wrote are carried, and the pass stamps only on green. A failed run arrives as a ledger line with its rc.

## Threat model

Two new trust boundaries.

**B1 — the results branch → the developer's machine.** `cloud-maintenance.sh --pull` reads files on
`claude/maintenance-results`, which anyone with push access to the repository can write, including a
cloud session acting on a prompt-injected instruction.

- Spoofing: a forged file claims to be a cloud run. Mitigation: accepted. It can only claim a job ran;
  the same people can edit the local stamp file directly. Every applied stamp is printed.
- Tampering: shell payloads, extra fields, unknown jobs, odd file names. Mitigation: nothing is
  executed or sourced; each line is matched field by field (fixed job sets, numeric fields, place
  `cloud`, 9 fields) and skipped with a named warning otherwise; file names outside `[A-Za-z0-9._-]`
  are skipped. Tested by C6, C7.
- Repudiation: n/a — git history of the branch is the audit trail.
- Information disclosure: n/a on this direction.
- Denial of service: a huge results file. Mitigation: open finding from the adversarial review if
  raised; the import is line-bounded but not size-bounded.
- Elevation: a stamp moved backwards or forwards to hide a due job. Mitigation: `--stamp-as` refuses
  to move a stamp backwards; forward moves are the spoofing case above.

**B2 — the cloud session → the repository.** The routine has push rights.

- Tampering with the default branch. Mitigation: the push target is a constant
  (`refs/heads/claude/maintenance-results`); the routine platform also refuses non-`claude/*`
  branches. C2 asserts main's sha is unchanged.
- Information disclosure: job output can hold secrets. Mitigation: only ledger fields and stamps are
  written; no log text. C2 asserts the file holds nothing but `ledger`/`stamp` lines.
- Supply chain: `cloud-setup.sh` downloads Microsoft's `dotnet-install.sh` over HTTPS without a
  pinned hash (Microsoft publishes none for the script). Accepted, recorded: the same script is the
  documented install path, and it runs in a disposable VM.
