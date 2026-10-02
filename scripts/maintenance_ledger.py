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
  python3 scripts/maintenance_ledger.py run JOB --skip-rc N -- CMD  # same, but exit N means "never started": no line
  python3 scripts/maintenance_ledger.py record JOB SECONDS RC               # a span timed by the caller (the whole pass)
  python3 scripts/maintenance_ledger.py report [--all] [--ledger PATH]
  python3 scripts/maintenance_ledger.py estimate JOB [JOB...]       # "JOB<TAB>median s<TAB>runs" here, or "JOB<TAB>unknown<TAB>0"

`run` is transparent: the child inherits stdout/stderr and its exit code is ours. A ledger that
cannot be written warns on stderr and changes nothing else -- a measurement must never turn a green
pass red.

Ledger: <repo>/.claude/state/maintenance-runs.tsv (machine-local, gitignored), one line per run:
  ts  place  job  seconds  rc  peak_rss_mb  cores  load1  done

peak_rss_mb is the larger of (a) the process tree's summed RSS, sampled once a second with `ps`, and
(b) the largest single reaped descendant (getrusage). Docker containers are not in the tree.
"""
import datetime
import os
import re
import stat
import statistics
import subprocess
import sys
import threading
import time

try:
    import resource  # absent on native Windows
except ImportError:  # pragma: no cover
    resource = None

LEDGER_REL = os.path.join(".claude", "state", "maintenance-runs.tsv")
FIELDS = ["ts", "place", "job", "seconds", "rc", "peak_rss_mb", "cores", "load1", "done"]
CLOUD_RAM_FIT_MB = 12 * 1024  # 16 GB VM minus 4 GB for the OS and the agent itself
SPECS_NEEDED = 5
# The jobs 075 places (local or cloud). A span of ticked specs with none of them in it measured the
# cheap jobs only, and readiness is a claim about the heavy ones (F058).
HEAVY_JOBS = ("mutation", "suite")


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


def largest_child_mb():
    """Peak of the single largest reaped descendant. A floor, not the footprint."""
    if resource is None:
        return None
    kb_or_bytes = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    # macOS reports bytes, Linux kilobytes.
    return kb_or_bytes / (1024 * 1024) if sys.platform == "darwin" else kb_or_bytes / 1024


def tree_rss_kb(root_pid):
    """Summed RSS (KB) of root_pid and every descendant, from one `ps` snapshot; None if ps fails.

    WHY A TREE. `dotnet test` runs a testhost and build servers beside the runner, and Stryker runs
    test workers in parallel. getrusage reports only the largest single process, so it under-reports
    exactly the jobs whose memory decides whether they fit the 16 GB cloud VM. Containers started
    through Docker are outside this tree and are NOT counted; the report says so."""
    try:
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,rss="], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    kids, rss = {}, {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) != 3 or not all(p.isdigit() for p in parts):
            continue
        pid, ppid, kb = (int(p) for p in parts)
        kids.setdefault(ppid, []).append(pid)
        rss[pid] = kb
    if root_pid not in rss:
        return None
    total, stack, seen = 0, [root_pid], set()
    while stack:
        pid = stack.pop()
        if pid in seen:
            continue
        seen.add(pid)
        total += rss.get(pid, 0)
        stack.extend(kids.get(pid, []))
    return total


def cmd_run(argv):
    # --skip-rc N: the child's own "never started" code (register-similarity.sh exits 2 when Ollama is
    # off). Such a run is not a measurement: a 0.0 s line would read as a job that is free (F074).
    skip_rc = None
    if len(argv) >= 3 and argv[1] == "--skip-rc":
        skip_rc = num(argv[2])
        if skip_rc is None:
            argv = []  # a non-numeric code is a usage error, not "skip nothing"
        else:
            argv = [argv[0]] + argv[3:]
    if len(argv) < 3 or argv[1] != "--":
        print("maintenance_ledger.py: usage: run JOB [--skip-rc N] -- CMD [ARGS...]", file=sys.stderr)
        return 2
    job, cmd = argv[0], argv[2:]
    root = repo_root()
    try:
        load1 = "%.2f" % os.getloadavg()[0]
    except (OSError, AttributeError):
        load1 = ""
    start = time.monotonic()
    peak_kb = [0]
    try:
        child = subprocess.Popen(cmd)
    except OSError as e:
        print("maintenance_ledger.py: could not start %s: %s" % (cmd[0], e), file=sys.stderr)
        append(root, job, time.monotonic() - start, 127, "", load1)
        return 127
    done = threading.Event()

    def sample():
        while not done.wait(1.0):
            kb = tree_rss_kb(child.pid)
            if kb is not None and kb > peak_kb[0]:
                peak_kb[0] = kb
    sampler = threading.Thread(target=sample, daemon=True)
    sampler.start()
    try:
        rc = child.wait()
    except KeyboardInterrupt:
        child.terminate()
        rc = child.wait()
    done.set()
    sampler.join(timeout=5)
    candidates = [m for m in (largest_child_mb(), peak_kb[0] / 1024 if peak_kb[0] else None) if m is not None]
    rss = str(int(round(max(candidates)))) if candidates else ""
    if skip_rc is not None and rc == int(skip_rc):
        return rc
    append(root, job, time.monotonic() - start, rc, rss, load1)
    return rc


def append(root, job, seconds, rc, rss, load1):
    row = [
        datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        place(), job, "%.1f" % seconds, str(rc), rss,
        str(os.cpu_count() or ""), load1, str(ticked_specs(root)),
    ]
    path = os.path.join(root, LEDGER_REL)
    try:
        # Spec 082 (F065): the ledger path is repository content, so a committed symlink at
        # .claude/state or at the file itself would turn this append into a write anywhere the
        # developer can write. The directory must resolve inside the repository, and the file is
        # opened without following a final symlink. The check runs BEFORE makedirs as well as after
        # (review finding 13): makedirs through a symlinked .claude/state would otherwise create
        # directories outside the repository before the check refused the write.
        ledger_dir = os.path.dirname(path)
        existing = ledger_dir
        while not os.path.lexists(existing) and os.path.dirname(existing) != existing:
            existing = os.path.dirname(existing)
        inside_repo(root, existing)
        os.makedirs(ledger_dir, exist_ok=True)
        inside_repo(root, ledger_dir)
        # One write of one short line in append mode: two passes at once never interleave.
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o644)
        try:
            os.write(fd, ("\t".join(row) + "\n").encode())
        finally:
            os.close(fd)
    except OSError as e:
        print("maintenance_ledger.py: not recorded (%s) — the job's result is unaffected" % e, file=sys.stderr)


def inside_repo(root, path):
    """Raise OSError unless `path` resolves inside `root`. commonpath raises ValueError across
    Windows drives, which would crash after the child finished and lose its exit code."""
    real_root, real = os.path.realpath(root), os.path.realpath(path)
    try:
        ok = os.path.commonpath([real_root, real]) == real_root
    except ValueError:
        ok = False
    if not ok:
        raise OSError("ledger directory resolves outside the repository: %s" % real)


_CONTROL = re.compile("[\x00-\x1f\x7f-\x9f\u200b-\u200f\u2028-\u202e\u2060-\u2069\ufeff]")


def clean(text):
    """A field from a ledger or a directory name, fit to print (spec 082, review finding 13).
    `report --all` reads sibling repositories' ledgers, so their fields are not ours: a terminal
    escape in a job name would otherwise reach the terminal, or the model reading the output."""
    return _CONTROL.sub("?", str(text))


def cmd_record(argv):
    # RSS is left blank: the caller timed a span this process did not parent, so any number here
    # would be this process's own, and an invented measurement is worse than a missing one.
    if len(argv) != 3 or num(argv[1]) is None or num(argv[2]) is None:
        print("maintenance_ledger.py: usage: record JOB SECONDS RC", file=sys.stderr)
        return 2
    append(repo_root(), argv[0], num(argv[1]), int(num(argv[2])), "", "")
    return 0


LEDGER_READ_LIMIT = 16 * 1024 * 1024   # bytes of one ledger read by report; years of nightly lines fit


def read_ledger(path):
    # Spec 082 (review finding 13): `report --all` reads other repositories' ledgers, so the path may
    # be a symlink to /dev/zero or a FIFO. Regular files only, never through a final symlink, never
    # blocking on open, and at most LEDGER_READ_LIMIT bytes.
    rows = []
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        fd = os.open(path, flags)
    except OSError:
        return rows
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return rows
        data = os.read(fd, LEDGER_READ_LIMIT)
    except OSError:
        return rows
    finally:
        os.close(fd)
    for line in data.decode("utf-8", errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) == len(FIELDS):
            rows.append(dict(zip(FIELDS, (clean(x) for x in parts))))
    return rows


def num(s):
    # `nan` and `inf` parse as floats and then crash int() and max(); report --all reads other
    # repositories' ledgers, so one such row must not take the whole report down (085 review).
    try:
        v = float(s)
    except ValueError:
        return None
    return v if v == v and v not in (float("inf"), float("-inf")) else None


def report_one(label, root, rows):
    print("== %s" % clean(label))
    if not rows:
        print("   no runs recorded — nothing measured yet, which is not the same as nothing heavy")
        return
    done = [int(n) for n in (num(r["done"]) for r in rows) if n is not None]
    span = (max(done) - min(done)) if done else 0
    unmeasured = [j for j in HEAVY_JOBS if not any(r["job"] == j for r in rows)]
    if span < SPECS_NEEDED:
        ready = "keep measuring"
    elif unmeasured:
        ready = "keep measuring — no run of: %s" % ", ".join(unmeasured)
    else:
        ready = "ready for 075"
    print("   spans %d of %d ticked specs needed (%s), %d runs, %s .. %s"
          % (span, SPECS_NEEDED, ready, len(rows), rows[0]["ts"][:10], rows[-1]["ts"][:10]))
    print("   (max RSS = whole process tree, sampled once a second; Docker containers are not counted)")
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
    # Spec 082 (F065): THIS repository's own script, pointed at the other repo with --dir. Running
    # root/scripts/register-convergence.sh meant `report --all` executed whatever any sibling
    # directory shipped under that name -- a planted clone got code execution.
    conv = os.path.join(os.path.dirname(os.path.abspath(__file__)), "register-convergence.sh")
    if os.path.isfile(conv):
        out = subprocess.run(["bash", conv, "--dir", root, "--quiet"], cwd=os.path.dirname(conv),
                             capture_output=True, text=True).stdout.strip()
        print("   carving: %s" % (clean(out.splitlines()[0]) if out else "register-convergence.sh printed nothing"))


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


def cmd_estimate(argv):
    """Spec 093 (F110): how long a job takes on THIS machine, for the due banner and the nightly installer.
    The median over every run at this place, red ones included: a red suite took that long too, and the
    question is wall time. Cloud runs are not this machine's cost. Never fails a caller: exit 0 always."""
    if not argv:
        print("maintenance_ledger.py: estimate needs at least one job", file=sys.stderr)
        return 2
    here = place()
    rows = read_ledger(os.path.join(repo_root(), LEDGER_REL))
    for job in argv:
        secs = [s for s in (num(r["seconds"]) for r in rows if r["job"] == job and r["place"] == here)
                if s is not None and s >= 0]
        if secs:
            print("%s\t%d\t%d" % (clean(job), round(statistics.median(secs)), len(secs)))
        else:
            print("%s\tunknown\t0" % clean(job))
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
    if argv[0] == "estimate":
        return cmd_estimate(argv[1:])
    print("maintenance_ledger.py: unknown command '%s' (run | record | report | estimate)" % argv[0], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
