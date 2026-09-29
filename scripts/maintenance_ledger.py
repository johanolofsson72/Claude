#!/usr/bin/env python3
"""maintenance_ledger.py — how long each maintenance job took, how much memory it used, and where.

WHY THIS EXISTS. The developer's direction (2026-09-29, row 074): heavy jobs that do not need the
local setup -- Stryker, full suites -- should run in Claude cloud rather than on the Mac or David's
Linux machine, and the decision is made from five ordinary specs' worth of numbers, not a guess.
`maintenance-due.sh --stamp` knows WHEN a job last ran. Nothing knew how long it took, how much
memory it peaked at, or where it ran. That is what this records.

The cloud VM is 4 vCPU / 16 GB RAM / 30 GB disk, with no .NET SDK until a setup script installs it
(code.claude.com/docs/en/cloud-environments, 2026-09-29). Peak memory is therefore the number that
rules a job in or out: agentcrm's integration suite reached 11.5 GB on 2026-09-01.

Usage:
  python3 scripts/maintenance_ledger.py run JOB -- CMD [ARGS...]   # run CMD, record one line, exit with its rc
  python3 scripts/maintenance_ledger.py record JOB SECONDS RC               # a span timed by the caller (the whole pass)
  python3 scripts/maintenance_ledger.py report [--all] [--ledger PATH]

`run` is transparent: the child inherits stdout/stderr and its exit code is ours. A ledger that
cannot be written warns on stderr and changes nothing else -- a measurement must never turn a green
pass red.

Ledger: <repo>/.claude/state/maintenance-runs.tsv (machine-local, gitignored), one line per run:
  ts  place  job  seconds  rc  peak_rss_mb  cores  load1  done
"""
import datetime
import os
import statistics
import subprocess
import sys
import time

try:
    import resource  # absent on native Windows
except ImportError:  # pragma: no cover
    resource = None

LEDGER_REL = os.path.join(".claude", "state", "maintenance-runs.tsv")
FIELDS = ["ts", "place", "job", "seconds", "rc", "peak_rss_mb", "cores", "load1", "done"]
CLOUD_RAM_FIT_MB = 12 * 1024  # 16 GB VM minus 4 GB for the OS and the agent itself
SPECS_NEEDED = 5


def repo_root():
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except OSError:
        pass
    return os.getcwd()


def place():
    if os.environ.get("CLAUDE_CODE_REMOTE") == "true":
        return "cloud"
    return "local-" + (os.uname().sysname.lower() if hasattr(os, "uname") else sys.platform)


def ticked_specs(root):
    # Counted exactly as maintenance-due.sh counts it, so the two never disagree about "done".
    try:
        with open(os.path.join(root, "specs", "INDEX.md"), encoding="utf-8") as f:
            return sum(1 for line in f if line.startswith("- [x]"))
    except OSError:
        return 0


def peak_rss_mb():
    if resource is None:
        return ""
    kb_or_bytes = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    # macOS reports bytes, Linux kilobytes.
    mb = kb_or_bytes / (1024 * 1024) if sys.platform == "darwin" else kb_or_bytes / 1024
    return str(int(round(mb)))


def cmd_run(argv):
    if len(argv) < 3 or argv[1] != "--":
        print("maintenance_ledger.py: usage: run JOB -- CMD [ARGS...]", file=sys.stderr)
        return 2
    job, cmd = argv[0], argv[2:]
    root = repo_root()
    try:
        load1 = "%.2f" % os.getloadavg()[0]
    except (OSError, AttributeError):
        load1 = ""
    start = time.monotonic()
    try:
        rc = subprocess.call(cmd)
    except OSError as e:
        print("maintenance_ledger.py: could not start %s: %s" % (cmd[0], e), file=sys.stderr)
        rc = 127
    append(root, job, time.monotonic() - start, rc, peak_rss_mb(), load1)
    return rc


def append(root, job, seconds, rc, rss, load1):
    row = [
        datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        place(), job, "%.1f" % seconds, str(rc), rss,
        str(os.cpu_count() or ""), load1, str(ticked_specs(root)),
    ]
    path = os.path.join(root, LEDGER_REL)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        # One write of one short line in append mode: two passes at once never interleave.
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
        try:
            os.write(fd, ("\t".join(row) + "\n").encode())
        finally:
            os.close(fd)
    except OSError as e:
        print("maintenance_ledger.py: not recorded (%s) — the job's result is unaffected" % e, file=sys.stderr)


def cmd_record(argv):
    # RSS is left blank: the caller timed a span this process did not parent, so any number here
    # would be this process's own, and an invented measurement is worse than a missing one.
    if len(argv) != 3 or num(argv[1]) is None or num(argv[2]) is None:
        print("maintenance_ledger.py: usage: record JOB SECONDS RC", file=sys.stderr)
        return 2
    append(repo_root(), argv[0], num(argv[1]), int(num(argv[2])), "", "")
    return 0


def read_ledger(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == len(FIELDS):
                    rows.append(dict(zip(FIELDS, parts)))
    except OSError:
        pass
    return rows


def num(s):
    try:
        return float(s)
    except ValueError:
        return None


def report_one(label, root, rows):
    print("== %s" % label)
    if not rows:
        print("   no runs recorded — nothing measured yet, which is not the same as nothing heavy")
        return
    done = [int(n) for n in (num(r["done"]) for r in rows) if n is not None]
    span = (max(done) - min(done)) if done else 0
    ready = "ready for 075" if span >= SPECS_NEEDED else "keep measuring"
    print("   spans %d of %d ticked specs needed (%s), %d runs, %s .. %s"
          % (span, SPECS_NEEDED, ready, len(rows), rows[0]["ts"][:10], rows[-1]["ts"][:10]))
    groups = {}
    for r in rows:
        groups.setdefault((r["job"], r["place"]), []).append(r)
    print("   %-12s %-14s %5s %9s %9s %10s %6s  %s"
          % ("job", "place", "runs", "median s", "max s", "max RSS MB", "rc!=0", "cloud VM fit"))
    for (job, plc), rs in sorted(groups.items()):
        secs = [s for s in (num(r["seconds"]) for r in rs) if s is not None]
        rss = [m for m in (num(r["peak_rss_mb"]) for r in rs) if m is not None]
        fails = sum(1 for r in rs if r["rc"] != "0")
        max_rss = max(rss) if rss else None
        if max_rss is None:
            fit = "unknown (no RSS)"
        elif max_rss < CLOUD_RAM_FIT_MB:
            fit = "fits 16 GB"
        else:
            fit = "TOO BIG for 16 GB"
        print("   %-12s %-14s %5d %9.1f %9.1f %10s %6d  %s"
              % (job, plc, len(rs), statistics.median(secs) if secs else 0.0, max(secs) if secs else 0.0,
                 "%d" % max_rss if max_rss is not None else "-", fails, fit))
    conv = os.path.join(root, "scripts", "register-convergence.sh")
    if os.path.isfile(conv):
        out = subprocess.run(["bash", conv, "--quiet"], cwd=root, capture_output=True, text=True).stdout.strip()
        print("   carving: %s" % (out.splitlines()[0] if out else "register-convergence.sh printed nothing"))


def cmd_report(argv):
    root = repo_root()
    ledgers = []
    if "--ledger" in argv:
        i = argv.index("--ledger")
        if i + 1 >= len(argv):
            print("maintenance_ledger.py: --ledger needs a path", file=sys.stderr)
            return 2
        ledgers.append((argv[i + 1], root, argv[i + 1]))
    elif "--all" in argv:
        parent = os.path.dirname(root)
        for name in sorted(os.listdir(parent)):
            p = os.path.join(parent, name, LEDGER_REL)
            if os.path.isfile(p):
                ledgers.append((name, os.path.join(parent, name), p))
        if not ledgers:
            print("no runs recorded in any repo under %s" % parent)
            return 0
    else:
        ledgers.append((os.path.basename(root), root, os.path.join(root, LEDGER_REL)))
    for label, r, p in ledgers:
        report_one(label, r, read_ledger(p))
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "run":
        return cmd_run(argv[1:])
    if argv[0] == "record":
        return cmd_record(argv[1:])
    if argv[0] == "report":
        return cmd_report(argv[1:])
    print("maintenance_ledger.py: unknown command '%s' (run | record | report)" % argv[0], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
