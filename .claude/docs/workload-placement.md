# Workload placement: local machine or Claude cloud

Status: decided 2026-10-01 (row 075). Every job stays local for now, and the reason is a measured
one: the only heavy job that needs nothing local, Stryker, does not fit the cloud VM at the
concurrency it runs with today. The machinery to run the cloud half is in place and tested. One line
in `scripts/workload-placement.tsv` moves a job.

## The decision (2026-10-01)

The rule: a job goes to the cloud only when all three hold. It needs nothing local. Its measured
max RSS is under 12 GB. Its median local run is at least 5 minutes, because below that a cloud
session's start-up and clone cost more than they save. A job with no measurement stays local.

| job | measured | place | why |
|---|---|---|---|
| mutation | agentcrm 2026-10-01: still running after ~1 h 45 min, 4 parallel testhosts at ~4.4 GB each (~17 GB) | local | over the 12 GB ceiling at this concurrency |
| suite | not measured on 2026-10-01; agentcrm peaked 11.5 GB (2026-09-01) | local | E2E and visual-regression baselines are rendered locally |
| secrets | 6-51 s, 1.3 GB | local | too short to be worth a session |
| similarity | 16 s, needs Ollama | local | needs a local model |
| traceability, portability | under 2 s | local | too short |

What moves Stryker: one cloud run with its concurrency at 2. The VM has 4 vCPU, so two testhosts
(about 9 GB) is the natural setting there. That is an inference from the 2026-10-01 numbers, not a
measurement, and the rule does not place on inference. Run it once by hand in a cloud session. If
the ledger line it brings back is under 12 GB, change the `mutation` line to `cloud`.

The measurement batch over agentcrm, ighweld-2026, iskvalp and rocky was stopped at its two-hour
limit while agentcrm's Stryker was still running, so no ledger line was written for it. The
observation above was read from the process table during the run. A stale `stryker_guard.py` from
another session was holding one core throughout, so the time is slightly high.

## The principle (developer, 2026-09-29)

A job runs locally when it needs the local setup: a browser for visual checks, `docker compose up`
against local config, secrets that only exist on the machine, or anything interactive. A heavy job
that needs none of that should go to Claude cloud, so it stops competing with the work on the Mac
and on David's Linux machine. Stryker is the obvious candidate. So is a full suite that does not
depend on local services.

GitHub Actions is still off the table (`.claude/rules/github-actions.md`). Cloud sessions and
routines use plan usage, not Actions minutes.

## What the cloud gives you

Source: code.claude.com/docs/en/cloud-environments, /routines, /claude-code-on-the-web, checked
2026-09-29. Re-check before 075 relies on any of it.

- The VM is Ubuntu 24.04 on x86_64: 4 vCPU, 16 GB RAM, 30 GB disk.
- Python, Node, Java, Go, Rust, Docker and PostgreSQL come preinstalled. The .NET SDK does not, so
  a setup script has to install it. The script's result is cached between sessions.
- `CLAUDE_CODE_REMOTE=true` is set inside the VM. A hook can use it to tell the cloud from a laptop.
- Routines (`/schedule`) run on a cron with a one-hour minimum, or on an API call or a GitHub event.
  Each run is its own session on claude.ai/code. Accounts have a daily run cap.
- Runs count against the plan's usage limits. The VM itself costs nothing extra.
- The docs do not say how long one command may run. A 30-90 minute Stryker pass has to be proven
  there before anyone depends on it.

The 4 vCPU matter. A laptop with more cores finishes Stryker sooner, so the cloud buys a free
laptop, not a faster run. The 16 GB matter more: agentcrm's integration suite peaked at 11.5 GB on
2026-09-01, which leaves very little headroom.

## What gets measured

`project-maintenance.sh` runs each costly job through `scripts/maintenance_ledger.py`. The measured
jobs are secrets, traceability, similarity, mutation, suite and portability, plus the whole pass.
Each run appends one line to `.claude/state/maintenance-runs.tsv`, which is gitignored and local to
the machine:

```
ts  place  job  seconds  rc  peak_rss_mb  cores  load1  done
```

`place` is `cloud` or `local-<os>`. `done` is the ticked-spec count at the time of the run, which is
how the report knows how many specs the measurement covers.

Carving is already measured by `scripts/register-convergence.sh`. The report prints its line rather
than keeping a second count.

## Reading it

```bash
python3 scripts/maintenance_ledger.py report          # this repo
python3 scripts/maintenance_ledger.py report --all    # every sibling repo with a ledger
```

For each job and place it prints runs, median and max seconds, max RSS, failures, and whether the
job fits the cloud VM (max RSS under 12 GB, keeping 4 GB for the OS and the agent). Max RSS is the whole process tree, sampled once a second, so a testhost or Stryker workers count. Docker containers do not, which matters for suites that use Testcontainers. The header says
"N of 5 ticked specs", and 075 starts at 5. An empty ledger prints "no runs recorded", because a
job nobody has measured is not a cheap job.

The template itself has no .NET suite and no Stryker config. The numbers that decide placement come
from the product projects, which pick the ledger up through autosync. So 075 reads `--all`.

## Running the cloud half (row 075)

Everything below is in CORE and reaches every project through autosync.

- `scripts/workload-placement.tsv` holds the template's decision, one line per job
  (`job<TAB>place<TAB>reason`). A project overrides a line in `.claude/workload-placement.tsv`.
  `bash scripts/workload-placement.sh --list` prints the table as it applies to this checkout.
- `bash scripts/project-maintenance.sh --full --suite --placed` runs only the jobs placed where it
  runs. A job placed elsewhere gets one line saying where it runs, and is neither run nor stamped.
  Without `--placed` nothing changes.
- `maintenance-due.sh` marks a due cloud job "(Claude cloud)" and names both halves.
- `bash scripts/cloud-maintenance.sh` is what a cloud session runs. It installs the .NET SDK through
  `scripts/cloud-setup.sh` when the project has a solution and the VM has no `dotnet`, runs the pass
  with `--placed`, and publishes one results file to `claude/maintenance-results`. That branch is the
  only thing it writes. Routines cannot push anywhere but `claude/*`, and the script never tries.
- `bash scripts/cloud-maintenance.sh --pull` on the laptop fetches the branch and imports what it
  has not seen: ledger lines into `.claude/state/maintenance-runs.tsv`, and stamps through
  `maintenance-due.sh --stamp-as`. A stamp keeps the cloud run's own date and counts, and never moves
  backwards. A results file is data. Nothing in it is executed, every field is checked, and a file
  over 64 KB, a symlink, or an unexpected name is skipped with a message.
- A pulled stamp counts only for a job this machine places in the cloud (spec 091, F095). A stamp
  for a local job is skipped and named; ledger lines still import, because they are history. Anyone
  who can push a `claude/*` branch can write that file, so the placement is what limits a forged
  stamp. `secrets` is always local, whatever either table says, and the agent's tools cannot edit
  `.claude/workload-placement.tsv`: the developer changes it by hand or with `!`.

To set up the routine (once per repository, by the developer, at claude.ai/code/routines or
`/schedule`): repository = the project, environment with network access to nuget.org and dot.net,
prompt `Run bash scripts/cloud-maintenance.sh and report its last line.`, schedule daily at most.
Optionally paste `bash scripts/cloud-setup.sh` as the environment's setup script so the SDK install
is cached between runs. Whether that script runs inside the clone is not documented (2026-10-01);
`cloud-maintenance.sh` calls it anyway, so the run works either way.

Not yet proven: how long one cloud command may run. The docs say nothing (2026-10-01). The first
cloud Stryker run is the measurement.
