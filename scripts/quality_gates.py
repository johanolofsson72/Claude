#!/usr/bin/env python3
"""quality_gates.py — measure the local-LLM quality-gate hooks, and run the good ones at night (020).

Fifteen hooks that check code (secret-scan, test-realism, test-assertion, ...) were unwired from
in-session use for latency and memory. At 02:30 neither matters, but nobody knew which of them is
right often enough to read. So:

  bench   runs each hook on its labelled corpus (scripts/fixtures/quality-gates/<hook>/, with
          expect.tsv saying which files carry a seeded defect and which word a true flag names),
          scores catches and false flags, and writes scripts/quality-gates.tsv with a verdict:
          `nightly` only when every seeded defect is caught, at most one clean file is falsely
          flagged, and the median call is within 60 s (developer, 020 O2).
  pass    feeds the files changed since the last pass to every `nightly` hook and writes
          .claude/state/quality-gates/latest.md.
  banner  prints one line for the morning banner: the count and the path, never the model's text
          (020 O3: a file can carry instructions aimed at the model, so its output stays out of
          every session's context).

A flag line is an UPPER_CASE-tagged line of the hook's output (NO_ASSERT:, UNREALISTIC:, N+1:,
LEAK: ...), bullet or not, or spec-criteria's `"phrase" → fix`; see flag_lines(). Nothing else the
model says is kept.

Python 3 stdlib only.
"""

import datetime
import ipaddress
import json
import os
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
# A flag line, after an optional list bullet: an UPPER_CASE tag and a colon (UNREALISTIC:, N+1:,
# LEAK: ...), or spec-criteria's `"<vague phrase>" → <fix>`. VERDICT: is spec-scope's summary, not a
# finding. Everything else the model says (preambles, the hooks' own header and footer) is dropped.
FLAG_RE = re.compile(r'^(?:[A-Z][A-Z0-9_+]*[A-Z0-9+]:|".+"\s*(?:→|->))')
NOT_FLAGS = ("VERDICT:", "UNCERTAIN:")  # spec-scope's summary; migration-safety's "cannot tell"
BULLET_RE = re.compile(r"^(?:[-*•]|\d{1,3}[.)])\s+")
BOLD_TAG_RE = re.compile(r"^\*\*([A-Z][A-Z0-9_+]*[A-Z0-9+]:)\*\*")


def flag_lines(text):
    """Model output is untrusted: keep flag lines only, without control characters, capped."""
    out = []
    for raw in str(text).splitlines():
        line = BOLD_TAG_RE.sub(r"\1", BULLET_RE.sub("", CONTROL_RE.sub("", raw).strip()))
        if FLAG_RE.match(line) and not line.startswith(NOT_FLAGS):
            out.append(line if len(line) <= MAX_FLAG_CHARS else line[:MAX_FLAG_CHARS] + "…")
    return out
MAX_FILES = 50
MAX_FILE_BYTES = 30000
MAX_FLAG_CHARS = 300
HOOK_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
CONTROL_RE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f\x1b]")
TABLE_HEADER = "# hook\tverdict\tcaught\tfalse\tmedian_s\tdate"


def _env_float(name, default):
    try:
        v = float(os.environ.get(name, default))
        return v if v > 0 else default
    except ValueError:
        return default


def today():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")


# ------------------------------------------------------------------------------- the model

def model_status():
    """(up, reason). Loopback only: file contents go to this host (020 threat model)."""
    if os.environ.get("LOCAL_LLM_DISABLE", "") == "1":
        return False, "local model disabled (LOCAL_LLM_DISABLE=1)"
    url = os.environ.get("OLLAMA_HOST", "") or "http://127.0.0.1:11434"
    # Review finding 11 (spec 082): whitespace or a control character anywhere is refused before
    # parsing; urlsplit strips some of them silently, which is how a value can read as one host here
    # and be another to the next client.
    if any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in url):
        return False, "model host %r contains whitespace or control characters (refused)" % url[:80]
    if "://" not in url:
        url = "http://" + url
    try:
        host = urllib.parse.urlsplit(url).hostname or ""
    except ValueError:
        return False, "model host %r does not parse" % url[:80]
    loopback = host == "localhost"
    if not loopback:
        try:
            loopback = ipaddress.ip_address(host).is_loopback
        except ValueError:
            loopback = False
    if loopback and "@" in urllib.parse.urlsplit(url).netloc:
        loopback = False   # spec 082: userinfo is refused, not parsed (same rule as local-llm-detect.sh)
    # Spec 082 (R13): LOCAL_LLM_ALLOW_REMOTE=1 is the one opt-in every local-model caller honours;
    # QUALITY_GATES_REMOTE_OK=1 predates it and keeps working.
    remote_ok = "1" in (os.environ.get("LOCAL_LLM_ALLOW_REMOTE"), os.environ.get("QUALITY_GATES_REMOTE_OK"))
    if not loopback and not remote_ok:
        return False, "model host %s is not loopback; file contents would leave this machine " \
                      "(set LOCAL_LLM_ALLOW_REMOTE=1 to allow)" % host
    try:
        with urllib.request.urlopen(url.rstrip("/") + "/api/tags", timeout=3) as resp:
            models = json.loads(resp.read(1 << 20).decode("utf-8", "replace")).get("models") or []
    except Exception as exc:
        return False, "model unreachable at %s (%s)" % (url, type(exc).__name__)
    if not models:
        return False, "model unreachable at %s (no models installed)" % url
    return True, "model up at %s" % url


# ------------------------------------------------------------------------------- running a hook

def hooks_dir():
    return os.environ.get("QUALITY_GATES_HOOKS_DIR") or HERE


def hook_script(hook):
    if not HOOK_NAME_RE.match(hook):
        raise ValueError("not a hook name: %r" % hook[:60])
    return os.path.join(hooks_dir(), "local-llm-%s-hook.sh" % hook)


def run_hook(hook, path, cwd, extra_env=None):
    """Run one hook on one file. Returns (flag_lines, seconds, timed_out, fired).

    fired: the hook reached local-llm-call.sh, which writes one trace line per call. A hook whose
    own trigger rejects the file (name, size, a content grep) exits before that, and that is not
    the same fact as the model missing a defect."""
    payload = json.dumps({"tool_name": "Write", "tool_input": {"file_path": path}})
    env = dict(os.environ)
    env.update(extra_env or {})
    trace_fd, trace = tempfile.mkstemp(prefix="qg-trace-")
    os.close(trace_fd)
    env["LOCAL_LLM_TRACE_LOG"] = trace
    try:
        flags, seconds, timed_out = _run(hook, payload, cwd, env)
        fired = os.path.getsize(trace) > 0
    finally:
        os.unlink(trace)
    return flags, seconds, timed_out, fired


def _run(hook, payload, cwd, env):
    timeout = _env_float("QUALITY_GATES_CALL_TIMEOUT", 120.0)
    start = time.monotonic()
    proc = subprocess.Popen(["bash", hook_script(hook)], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=cwd, env=env,
                            start_new_session=True)
    try:
        out, _ = proc.communicate(payload.encode(), timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)  # the hook's curl and friends go with it
        except OSError:
            pass
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            pass  # a grandchild that left the group still holds the pipe; give up on it
        return [], time.monotonic() - start, True
    seconds = time.monotonic() - start
    text = out.decode("utf-8", "replace")
    try:
        text = json.loads(text)["hookSpecificOutput"]["additionalContext"]
    except Exception:
        pass
    return flag_lines(text), seconds, False


# ------------------------------------------------------------------------------- bench

class CorpusError(Exception):
    pass


class NoCorpus(Exception):
    """A project without the template's corpus: benching is a template job."""


def load_corpus(corpus, only=None):
    """{hook: [(abs_path, 'bad'|'clean', marker)]}. Raises CorpusError naming every problem."""
    problems = []
    gates = {}
    if not os.path.isdir(corpus):
        raise NoCorpus("no corpus directory at %s" % corpus)
    for hook in sorted(os.listdir(corpus)):
        d = os.path.join(corpus, hook)
        if not os.path.isdir(d) or (only and hook not in only):
            continue
        if not HOOK_NAME_RE.match(hook):
            problems.append("%r is not a hook name" % hook)
            continue
        if not os.path.isfile(hook_script(hook)):
            problems.append("%s: no hook %s" % (hook, hook_script(hook)))
            continue
        expect = os.path.join(d, "expect.tsv")
        if not os.path.isfile(expect):
            problems.append("%s: no expect.tsv" % hook)
            continue
        rows = []
        real_d = os.path.realpath(d)
        with open(expect, "r", encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                line = line.rstrip("\n")
                if not line.strip() or line.startswith("#"):
                    continue
                parts = line.split("\t")
                name, kind = parts[0], parts[1] if len(parts) > 1 else ""
                marker = parts[2].strip() if len(parts) > 2 else ""
                path = os.path.realpath(os.path.join(d, name))
                if not path.startswith(real_d + os.sep):
                    problems.append("%s/expect.tsv:%d: %s is outside the corpus directory" % (hook, n, name))
                elif not os.path.isfile(path):
                    problems.append("%s/expect.tsv:%d: %s does not exist" % (hook, n, name))
                elif kind not in ("bad", "clean"):
                    problems.append("%s/expect.tsv:%d: expectation '%s' is not bad|clean" % (hook, n, kind))
                elif kind == "bad" and not marker:
                    problems.append("%s/expect.tsv:%d: a bad file needs the marker a true flag names" % (hook, n))
                else:
                    rows.append((path, kind, marker))
        if rows:
            gates[hook] = rows
    if problems:
        raise CorpusError("\n".join("  - " + p for p in problems))
    return gates


class Unfired(Exception):
    """A seeded-defect fixture never reached the model: the corpus is wrong, not the hook."""


def score(hook, rows):
    """Each fixture runs QUALITY_GATES_RUNS times (default 3) and counts by majority: the hooks
    call the model at temperature 0.2, and one call per file made a 2-file corpus a coin toss
    (020: async-audit missed a fixture in the bench and caught it on the next call)."""
    runs = int(_env_float("QUALITY_GATES_RUNS", 3))
    caught = bad = false = clean = 0
    times = []
    for path, kind, marker in rows:
        hits = flagged = 0
        fired = False
        for _ in range(runs):
            # A fresh cache per CALL (Q12). One cache per hook made runs 2 and 3 of a fixture
            # cache hits: three copies of one answer, and a median that timed the cache (0.4 s).
            cache = tempfile.mkdtemp(prefix="qg-cache-")
            try:
                flags, seconds, _, f = run_hook(hook, path, os.path.dirname(path),
                                                {"LOCAL_LLM_CACHE_DIR": cache})
            finally:
                shutil.rmtree(cache, ignore_errors=True)
            times.append(seconds)
            fired = fired or f
            flagged += 1 if flags else 0
            hits += 1 if any(marker.lower() in x.lower() for x in flags) else 0
        if kind == "bad":
            if not fired:
                raise Unfired("%s: %s never reached the model (the hook's own trigger rejected it)"
                              % (hook, os.path.basename(path)))
            bad += 1
            caught += 1 if hits * 2 > runs else 0
        else:
            clean += 1
            false += 1 if flagged * 2 > runs else 0
    median = statistics.median(times) if times else 0.0
    nightly = bad > 0 and caught == bad and false <= 1 \
        and median <= _env_float("QUALITY_GATES_MAX_MEDIAN", 60.0)
    return ["nightly" if nightly else "off", "%d/%d" % (caught, bad), "%d/%d" % (false, clean),
            "%.1f" % median, today()]


def read_table(path):
    rows = {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) >= 2 and HOOK_NAME_RE.match(parts[0]):
                    rows[parts[0]] = parts[1:]
    except OSError:
        pass
    return rows


def write_table(path, rows):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("# quality-gates.tsv — written by scripts/quality-gate-bench.sh (spec 020). nightly =\n")
        fh.write("# every seeded defect caught, <= 1 clean file falsely flagged, median <= 60 s.\n")
        fh.write(TABLE_HEADER + "\n")
        for hook in sorted(rows):
            fh.write("\t".join([hook] + rows[hook]) + "\n")
    os.replace(tmp, path)


def cmd_bench(args):
    corpus = args.get("--corpus") or os.path.join(HERE, "fixtures", "quality-gates")
    table = args.get("--table") or os.path.join(HERE, "quality-gates.tsv")
    only = set(filter(None, (args.get("--only") or "").split(",")))
    try:
        gates = load_corpus(corpus, only)
    except NoCorpus as exc:
        print("quality-gate-bench: %s — benching is a template job; the table arrives by sync" % exc)
        return 3
    except CorpusError as exc:
        print("quality-gate-bench: the corpus does not load:\n%s" % exc, file=sys.stderr)
        return 2
    up, reason = model_status()
    if not up:
        print("quality-gate-bench: %s — nothing scored, %s unchanged" % (reason, table))
        return 3
    rows = read_table(table)
    for hook, files in gates.items():
        try:
            rows[hook] = score(hook, files)
        except Unfired as exc:
            print("quality-gate-bench: corpus defect — %s. Fix the fixture; %s unchanged" % (exc, table),
                  file=sys.stderr)
            return 2
        print("%-18s %-7s caught %-5s false %-5s median %ss" % (hook, *rows[hook][:4]))
        sys.stdout.flush()
    write_table(table, rows)
    print("wrote %s" % table)
    return 0


# ------------------------------------------------------------------------------- nightly pass

def git(root, *a):
    return subprocess.run(["git", "-C", root] + list(a), stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL).stdout.decode("utf-8", "surrogateescape")


def changed_files(root, last):
    """(paths relative to root, note). Commits after `last`, or the last 24 h on a first run."""
    note = ""
    if last and subprocess.run(["git", "-C", root, "cat-file", "-e", last + "^{commit}"],
                               stderr=subprocess.DEVNULL).returncode == 0:
        out = git(root, "diff", "--name-only", "-z", "--diff-filter=ACMR", last, "HEAD")
    else:
        if last:
            note = "last pass marker %r is not a commit; reading the last 24 h" % last[:40]
        # -m --first-parent: a merge commit lists what it brought in, not nothing.
        out = git(root, "log", "--since=24.hours.ago", "-m", "--first-parent", "--name-only", "-z",
                  "--format=", "--diff-filter=ACMR")
    seen = []
    for p in out.split("\0"):
        p = p.strip("\n")  # git log -z still ends each commit's list with a newline
        if p and p not in seen:
            seen.append(p)
    return seen, note


def _is_text(path):
    try:
        with open(path, "rb") as fh:
            return b"\0" not in fh.read(8000)
    except OSError:
        return False


LINE_NO_RE = re.compile(r"^\s*(?:line\s*)?(\d+)")


CREDENTIAL_RE = re.compile(
    r"(?i)((?:secret|password|passwd|pwd|token|api[_-]?key|access[_-]?key|private[_-]?key)[A-Za-z0-9_]*"
    r"[\"']?\s*[=:]\s*|bearer\s+)(\"[^\"]*\"?|'[^']*'?|[^\s\"'|,;]{4,})")


def _cut(value):
    quote = value[0] if value[:1] in ("'", '"') else ""
    inner = value.strip("'\"")
    return quote + inner[:4] + "…" + quote


def redact(line):
    """Any hook may echo a credential (dockerfile-review: `RISK: ENV PAYMENT_API_SECRET=...`).
    A quoted value is cut whole, so a multi-word password does not leak past its first word."""
    return CREDENTIAL_RE.sub(lambda m: m.group(1) + _cut(m.group(2)), line)


def mask(hook, line):
    """secret-scan quotes what it found (`LEAK: <line>: <content> | <reason>`). Keep the line
    number and the reason, never the content: masking values inside free text leaks multi-word
    passwords and `Bearer <token>`."""
    if hook != "secret-scan" and not line.startswith(("SECRET", "LEAK")):
        return redact(line)
    tag, _, rest = line.partition(":")
    m = LINE_NO_RE.match(rest)
    parts = rest.split(" | ")
    reason = parts[-1].strip() if len(parts) > 1 else "(reason withheld)"
    return "%s: line %s | %s" % (tag, m.group(1) if m else "?", reason)


def cmd_pass(args):
    root = git(os.getcwd(), "rev-parse", "--show-toplevel").strip() or os.getcwd()
    table = args.get("--table") or os.path.join(root, "scripts", "quality-gates.tsv")
    state = os.path.join(root, ".claude", "state", "quality-gates")
    os.makedirs(state, exist_ok=True)
    real_state = os.path.realpath(state)
    if not real_state.startswith(os.path.realpath(root) + os.sep) or os.path.islink(state):
        print("quality-gate-pass: %s resolves outside the project; refusing to write there" % state)
        return 2

    up, reason = model_status()
    if not up:
        print("quality-gate-pass: %s — nothing run, last pass marker unchanged" % reason)
        return 3

    # An OS lock, released by the kernel when the holder exits or dies. The first version was a
    # lock directory with a pid file: reading the pid and taking over a dead holder's lock are two
    # steps, and TLC (020 PassLock.tla) found two passes both taking over the same stale lock.
    lock = os.path.join(state, "lock")
    try:
        fd = os.open(lock, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o644)
    except OSError as exc:
        print("quality-gate-pass: cannot open the lock %s (%s)" % (lock, exc))
        return 2
    try:
        if not _try_lock(fd):
            print("quality-gate-pass: another pass is already running (%s is held)" % lock)
            return 0
        return _run_pass(root, table, state)
    finally:
        os.close(fd)  # closing releases the lock


def _try_lock(fd):
    try:
        import fcntl
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except OSError:
            return False
    except ImportError:  # Windows (Git Bash's python): a byte-range lock, also released on exit
        import msvcrt
        try:
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
            return True
        except OSError:
            return False


def _write(path, text):
    """Write without following a symlink at the target: state files must stay inside .claude/state."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def _run_pass(root, table, state):
    nightly = sorted(h for h, r in read_table(table).items() if r and r[0] == "nightly")
    last_path = os.path.join(state, "last")
    try:
        with open(last_path, "r", encoding="utf-8") as fh:
            last = fh.read(200).strip()
    except OSError:
        last = ""
    head = git(root, "rev-parse", "HEAD").strip()
    files, note = changed_files(root, last)
    if note:
        print("quality-gate-pass: " + note)

    run, skipped = [], []
    real_root = os.path.realpath(root)
    for rel in files:
        # The bench corpus is defective on purpose; scanning it would flag every seeded defect.
        if rel.replace("\\", "/").startswith("scripts/fixtures/quality-gates/"):
            continue
        full = os.path.join(root, rel)
        # A committed symlink (x.test.ts -> ~/.ssh/id_rsa) would be read and sent to the model.
        if os.path.islink(full) or not os.path.realpath(full).startswith(real_root + os.sep):
            continue
        if not os.path.isfile(full) or not _is_text(full):
            continue
        size = os.path.getsize(full)
        if size > MAX_FILE_BYTES:
            skipped.append("%s — over %d bytes" % (rel, MAX_FILE_BYTES))
        elif len(run) >= MAX_FILES:
            skipped.append("%s — over the %d-file cap" % (rel, MAX_FILES))
        else:
            run.append(rel)

    by_file = {}
    answered = 0
    deadline = time.monotonic() + _env_float("QUALITY_GATES_DEADLINE", 2 * 3600.0)
    for i, rel in enumerate(run):
        if time.monotonic() > deadline:
            skipped += ["%s — the pass hit its deadline" % r for r in run[i:]]
            run = run[:i]
            break
        for hook in nightly:
            if not os.path.isfile(hook_script(hook)):
                continue
            flags, _, timed_out, _ = run_hook(hook, os.path.join(root, rel), root)
            answered += 0 if timed_out else 1
            for f in flags:
                by_file.setdefault(rel, []).append("- [%s] %s" % (hook, mask(hook, f)))
            if timed_out:
                by_file.setdefault(rel, []).append("- [%s] (timed out — no answer)" % hook)
    total = sum(1 for lines in by_file.values() for l in lines if not l.endswith("(timed out — no answer)"))

    out = ["# Quality gates — %s" % today(), "",
           "flags: %d · skipped: %d · files: %d · hooks: %s"
           % (total, len(skipped), len(run), ", ".join(nightly) or "(none nightly)"), ""]
    if not files or not run:
        out.append("No changed files since %s." % (last[:12] if last else "the last 24 h"))
        out.append("")
    for rel in sorted(by_file):
        out += ["## %s" % rel] + by_file[rel] + [""]
    if skipped:
        out += ["## Skipped"] + ["- " + s for s in skipped] + [""]
    report = os.path.join(state, "latest.md")
    if os.path.islink(report + ".tmp"):
        os.unlink(report + ".tmp")
    _write(report + ".tmp", "\n".join(out))
    os.replace(report + ".tmp", report)
    # AC-4 holds mid-run too: if the model died (every call timed out, or it is down now), the
    # files were not checked, so the marker stays where it was and tonight's files are read again.
    if run and nightly and (answered == 0 or not model_status()[0]):
        print("quality-gate-pass: the model stopped answering during the pass; last pass marker unchanged")
    elif head:
        _write(last_path, head + "\n")
    if not run:
        print("quality-gate-pass: no changed files since %s" % (last[:12] if last else "the last 24 h"))
    print("quality-gate-pass: %d flag(s) in %d file(s), %d skipped → %s"
          % (total, len(run), len(skipped), os.path.relpath(report, root)))
    return 0


# ------------------------------------------------------------------------------- banner

BANNER_HEAD_RE = re.compile(r"^# Quality gates — ([0-9]{4}-[0-9]{2}-[0-9]{2})$")
BANNER_COUNT_RE = re.compile(r"^flags: ([0-9]{1,6}) · skipped: ([0-9]{1,6}) ·")


def cmd_banner(args):
    root = args.get("--root") or os.getcwd()
    rel = os.path.join(".claude", "state", "quality-gates", "latest.md")
    try:
        with open(os.path.join(root, rel), "r", encoding="utf-8", errors="replace") as fh:
            head = [fh.readline().rstrip("\n") for _ in range(3)]
    except OSError:
        return 0
    m1, m2 = BANNER_HEAD_RE.match(head[0]), BANNER_COUNT_RE.match(head[2])
    if not (m1 and m2):
        return 0
    flags, skipped = int(m2.group(1)), int(m2.group(2))
    if flags or skipped:
        extra = ", %d file%s skipped" % (skipped, "" if skipped == 1 else "s") if skipped else ""
        print("quality gates: %d flag%s%s from %s — %s"
              % (flags, "" if flags == 1 else "s", extra, m1.group(1), rel))
    return 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("bench", "pass", "banner"):
        print("usage: quality_gates.py bench|pass|banner [--corpus D] [--table F] [--only a,b] [--root D]",
              file=sys.stderr)
        return 2
    args, it = {}, iter(argv[2:])
    for a in it:
        args[a] = next(it, "")
    return {"bench": cmd_bench, "pass": cmd_pass, "banner": cmd_banner}[argv[1]](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
