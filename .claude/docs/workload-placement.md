# Workload placement: local machine or Claude cloud

Status: measuring. Row 074 records the numbers, and row 075 turns them into a placement once five
ordinary specs have ticked under the ledger. Until 075 lands, nothing moves and no rule changes.

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
job fits the cloud VM (max RSS under 12 GB, keeping 4 GB for the OS and the agent). The header says
"N of 5 ticked specs", and 075 starts at 5. An empty ledger prints "no runs recorded", because a
job nobody has measured is not a cheap job.

The template itself has no .NET suite and no Stryker config. The numbers that decide placement come
from the product projects, which pick the ledger up through autosync. So 075 reads `--all`.

## What 075 decides

For each job: local, a cloud session started by hand, or a cloud routine. That comes with a setup
script for the .NET SDK and a way to get cloud results back, since the VM's `.claude/state/` does
not survive the session. It also covers changing `spec-hardening.md`'s "Local only" to "local or
Claude cloud, never GitHub Actions" and `maintenance-due.sh`'s "Run now" line to name the place.
