#!/usr/bin/env python3
"""acceptance_cases.py — developer-confirmed acceptance cases (spec 080).

A full or hardened spec owes <spec-dir>/acceptance.md: 3-5 cases, each

    ## AC-<n> — <title>
    **Given** ...
    **When** ...
    **Then** ...

plus one line the developer's confirmation produced:

    **Confirmed:** <YYYY-MM-DD> · <digest> — "<the developer's words>"

The digest pins the cases as the developer saw them. Edit a case after confirmation and the
digest no longer matches, so spec-interview-guard-hook.sh denies production source until the
developer confirms again. With the cases confirmed, test files are editable; production source
unlocks once some test file names every case as <spec-id>-AC-<n>.

One parser for the guard and the helper (scripts/acceptance-cases.sh). The guard imports this
module into its own interpreter rather than shelling out, the same way it imports spec_active.

Python 3 stdlib only.
"""

import datetime
import hashlib
import os
import re
import stat
import subprocess
import sys

MIN_CASES = 3
MAX_CASES = 5
MAX_BYTES = 64 * 1024
DIGEST_CHARS = 12
DEFAULT_SCAN_TIMEOUT = 5.0

# Numbers are bounded: int() on a 5000-digit string raises, and an exception here must never
# reach the hook as an unknown exit code (that path allows).
HEADING_RE = re.compile(r"^##\s+AC-(\d{1,4})\s*(?:—|–|-)\s*(.*?)\s*$")
OTHER_HEADING_RE = re.compile(r"^#{1,6}\s")
FIELD_RE = re.compile(r"^\*\*(Given|When|Then):?\*\*:?\s*(.*?)\s*$")
CONFIRMED_PREFIX = "**Confirmed:**"
CONFIRMED_RE = re.compile(
    r'^\*\*Confirmed:\*\*\s+(\d{4}-\d{2}-\d{2})\s+·\s+([0-9a-f]{%d})\s+—\s+"(.+)"\s*$' % DIGEST_CHARS
)
FIELDS = ("Given", "When", "Then")


class Unreadable(Exception):
    """acceptance.md exists but could not be read. A gate that cannot read what it guards denies."""


def _collapse(text):
    return " ".join(text.split())


def parse_text(text):
    """Parse acceptance.md text. Returns a dict: cases, problems, confirmed (or None)."""
    cases = []
    problems = []
    confirmed_lines = []
    current = None
    last_field = None

    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if line.startswith(CONFIRMED_PREFIX):
            confirmed_lines.append((lineno, line))
            current, last_field = None, None
            continue
        m = HEADING_RE.match(line)
        if m:
            current = {"number": int(m.group(1)), "title": _collapse(m.group(2)), "line": lineno,
                       "Given": None, "When": None, "Then": None, "repeated": []}
            cases.append(current)
            last_field = None
            continue
        if OTHER_HEADING_RE.match(line):
            current, last_field = None, None
            continue
        if current is None:
            continue
        m = FIELD_RE.match(line)
        if m:
            name = m.group(1)
            if current[name] is not None:
                current["repeated"].append(name)
            current[name] = _collapse(m.group(2))
            last_field = name
            continue
        if not line.strip():
            last_field = None
            continue
        if last_field is not None:
            # A wrapped line continues the field above it.
            current[last_field] = _collapse(current[last_field] + " " + line)

    for c in cases:
        n = c["number"]
        if not c["title"]:
            problems.append("AC-%d has no title (line %d)" % (n, c["line"]))
        for name in FIELDS:
            if not c[name]:
                problems.append("AC-%d has no %s line with text (line %d)" % (n, name, c["line"]))
        for name in sorted(set(c["repeated"])):
            problems.append("AC-%d has two %s lines (line %d)" % (n, name, c["line"]))

    count = len(cases)
    if count < MIN_CASES or count > MAX_CASES:
        problems.append("%d cases; the band is %d-%d" % (count, MIN_CASES, MAX_CASES))
    for expected, c in enumerate(cases, 1):
        if c["number"] != expected:
            problems.append("numbering: expected AC-%d, found AC-%d (line %d); cases run 1, 2, 3... "
                            "with no gaps or repeats" % (expected, c["number"], c["line"]))
            break

    confirmed = None
    if len(confirmed_lines) > 1:
        problems.append("%d Confirmed lines (lines %s); there is exactly one"
                        % (len(confirmed_lines), ", ".join(str(n) for n, _ in confirmed_lines)))
    elif confirmed_lines:
        lineno, line = confirmed_lines[0]
        m = CONFIRMED_RE.match(line)
        if not m:
            problems.append('Confirmed line is malformed (line %d); the shape is '
                            '**Confirmed:** YYYY-MM-DD · <12-hex digest> — "<the developer\'s words>"'
                            % lineno)
        else:
            confirmed = {"date": m.group(1), "digest": m.group(2), "quote": m.group(3), "line": lineno}

    return {"cases": cases, "problems": problems, "confirmed": confirmed}


def digest_of(cases):
    parts = []
    for c in cases:
        parts.append("AC-%d — %s" % (c["number"], c["title"] or ""))
        for name in FIELDS:
            parts.append("%s %s" % (name, c[name] or ""))
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()[:DIGEST_CHARS]


def _regular(path):
    """True when *path* is a regular file (symlinks followed). A FIFO or a device would block a
    read, and a hook that hangs is a hook the CLI times out and lets through."""
    try:
        return stat.S_ISREG(os.stat(path).st_mode)
    except OSError:
        return False


def read_file(path):
    """Return the text of acceptance.md, None when absent. Raises Unreadable."""
    if not os.path.lexists(path):
        return None
    if not _regular(path):
        raise Unreadable("%s is not a regular file" % path)
    try:
        size = os.path.getsize(path)
        if size > MAX_BYTES:
            return ("", "acceptance.md is %d bytes, over the 64 KB limit" % size)
        with open(path, "r", encoding="utf-8-sig", errors="replace") as fh:
            return fh.read(MAX_BYTES + 1)
    except OSError as exc:
        raise Unreadable(str(exc))


def load(spec_dir):
    """Parse <spec_dir>/acceptance.md. Returns None when absent, else the parse dict + digest."""
    got = read_file(os.path.join(spec_dir, "acceptance.md"))
    if got is None:
        return None
    if isinstance(got, tuple):
        return {"cases": [], "problems": [got[1]], "confirmed": None, "digest": ""}
    parsed = parse_text(got)
    parsed["digest"] = digest_of(parsed["cases"])
    return parsed


# ----------------------------------------------------------------------------- test paths

# "specs" is deliberately absent: it is where the register and acceptance.md live, and a case named
# in its own spec directory is not a test.
TEST_DIRS = {"test", "tests", "__tests__", "spec", "e2e", "integration_test"}
TEST_NAME_RES = [
    re.compile(r"\.(test|spec)\.[A-Za-z0-9]+$"),
    re.compile(r"_test\.[A-Za-z0-9]+$"),
    re.compile(r"^test_.+\.py$"),
    re.compile(r"^test-.+\.(sh|bash)$"),  # this template's own scripts/test-*.sh
    re.compile(r"Tests?\.cs$"),
    re.compile(r"_spec\.rb$"),
]
TEST_PROJECT_RE = re.compile(r"\.Tests?$")


def is_test_path(path):
    """True when *path* is a test file by the conventions of the stacks the template serves."""
    parts = [p for p in re.split(r"[\\/]+", path) if p]
    if not parts:
        return False
    name = parts[-1]
    for d in parts[:-1]:
        if d.lower() in TEST_DIRS or TEST_PROJECT_RE.search(d):
            return True
    return any(r.search(name) for r in TEST_NAME_RES)


# ------------------------------------------------------------------------------ coverage

class ScanFailed(Exception):
    """The scan could not answer (timeout, git missing). The gate fails open on this."""


def _scan_timeout():
    try:
        value = float(os.environ.get("ACCEPTANCE_SCAN_TIMEOUT", DEFAULT_SCAN_TIMEOUT))
    except ValueError:
        return DEFAULT_SCAN_TIMEOUT
    return value if value > 0 else DEFAULT_SCAN_TIMEOUT


class ScanError(Exception):
    """git answered with an error (not a repo, dubious ownership...). The gate denies on this:
    only a timeout fails open (080 O6)."""


def _name_re(spec_id):
    return re.compile(r"(?<![0-9A-Za-z.])" + re.escape(spec_id) + r"-AC-(\d{1,4})(?![0-9A-Za-z])")


def _names_in(root, rel, name_re):
    """Case numbers one test file names. Empty unless it is a regular test file inside *root*."""
    if not is_test_path(rel):
        return set()
    full = os.path.join(root, rel)
    real_root = os.path.realpath(root)
    if not os.path.realpath(full).startswith(real_root + os.sep) or not _regular(full):
        return set()
    try:
        with open(full, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read(4 * 1024 * 1024)
    except OSError:
        return set()
    return {int(m.group(1)) for m in name_re.finditer(text)}


def named_cases(root, spec_id):
    """{case number: [test files naming it]} under *root*. Raises ScanFailed (timeout) or ScanError."""
    literal = re.escape(spec_id) + "-AC-"
    try:
        proc = subprocess.run(
            ["git", "-C", root, "grep", "--untracked", "-I", "-l", "-z", "-E", "-e", literal, "--", "."],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=_scan_timeout(),
        )
    except subprocess.TimeoutExpired as exc:
        raise ScanFailed(str(exc))
    except OSError as exc:
        raise ScanError("git could not run: %s" % exc)
    if proc.returncode not in (0, 1):
        raise ScanError("git grep exited %d: %s" % (
            proc.returncode, proc.stderr.decode("utf-8", "replace").strip()[:300]))
    name_re = _name_re(spec_id)
    found = {}
    for rel in proc.stdout.decode("utf-8", "surrogateescape").split("\0"):
        if not rel:
            continue
        for n in _names_in(root, rel, name_re):
            found.setdefault(n, []).append(rel)
    return found


def _cache_path(root, spec_id):
    return os.path.join(root, ".claude", "state", "acceptance", re.sub(r"[^A-Za-z0-9._-]", "_", spec_id))


def _cached(root, spec_id, digest, numbers):
    """True when the cache names this digest AND the test files it lists still name every case.

    The cache is a list of files to re-read, not a verdict to trust. .claude/state/ is gitignored, so
    a cache that stored only "covered" could be forged with no trace in any diff; this one can only
    point at test files, and those are read again on every hit."""
    path = _cache_path(root, spec_id)
    if not _regular(path):
        return False
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.read(64 * 1024).splitlines()
    except OSError:
        return False
    if not lines or lines[0].strip() != digest:
        return False
    name_re = _name_re(spec_id)
    named = set()
    for rel in lines[1:21]:
        named |= _names_in(root, rel.strip(), name_re)
    return all(n in named for n in numbers)


def _store(root, spec_id, digest, found):
    files = sorted({f for fs in found.values() for f in fs})[:20]
    path = _cache_path(root, spec_id)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as fh:
            fh.write("\n".join([digest] + files) + "\n")
        os.replace(tmp, path)
    except OSError:
        pass


# ---------------------------------------------------------------------------------- gate

def _owes(info):
    if os.environ.get("SPEC_ACCEPTANCE", "").strip().lower() == "off":
        return False
    return info.get("track") == "full" or bool(info.get("hardened"))


# The day 080 landed. A spec counts as begun before it when its interview.md was first committed
# before this date. Without the date, ticking one setup task (spec-kit's Setup phase ticks
# "T001 Initialize package.json" before any source edit) would exempt a brand-new spec (080 O5:
# "every spec started after the sync needs cases").
GRANDFATHER_BEFORE = "2026-10-02"


def _first_committed(root, path):
    try:
        proc = subprocess.run(
            ["git", "-C", root, "log", "--diff-filter=A", "--format=%ci", "--", path],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=_scan_timeout(),
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    dates = proc.stdout.decode("utf-8", "replace").split()
    return dates[-3][:10] if len(dates) >= 3 else None


def _grandfathered(root, spec_dir):
    tasks = os.path.join(spec_dir, "tasks.md")
    if os.path.lexists(os.path.join(spec_dir, "acceptance.md")) or not _regular(tasks):
        return False
    try:
        with open(tasks, "r", encoding="utf-8", errors="replace") as fh:
            ticked = any(re.match(r"^\s*[-*]\s+\[[xX]\]", line) for line in fh)
    except OSError:
        return False
    if not ticked:
        return False
    first = _first_committed(root, os.path.join(spec_dir, "interview.md"))
    return first is not None and first < GRANDFATHER_BEFORE


HOW_TO_CONFIRM = """How to get it confirmed:
  1. Draft 3-5 cases in {path}, one per behaviour the developer must see work:

       ## AC-1 — <short title>
       **Given** <the state>
       **When** <the action>
       **Then** <the observable outcome>

  2. Show them to the developer with ONE AskUserQuestion and ask them to confirm or correct
     them. Never confirm them yourself: the point is that a requirement the developer stated
     becomes a test.
  3. Record their answer, quoted:
       bash scripts/acceptance-cases.sh --confirm {spec_dir} --quote "<their words>"
  4. Write one test per case that names it ({spec_id}-AC-<n>) before any production code.

A project that does not want this sets SPEC_ACCEPTANCE=off in .claude/settings.json env."""


def gate(root, info, file_path):
    """Decide one edit. Returns None to allow, or a deny reason string."""
    if not _owes(info) or not info.get("dir"):
        return None
    spec_id = info["id"]
    spec_dir = os.path.join(root, info["dir"])
    if _grandfathered(root, spec_dir):
        return None

    path = os.path.join(spec_dir, "acceptance.md")
    rel_dir = info["dir"]
    head = "BLOCKED — acceptance cases for active spec %s (%s%s track) " % (
        spec_id, info.get("track"), ", hardened" if info.get("hardened") else "")
    how = HOW_TO_CONFIRM.format(path=path, spec_dir=rel_dir, spec_id=spec_id)

    try:
        parsed = load(spec_dir)
    except Unreadable as exc:
        return head + "cannot be read.\n\n%s: %s\n\nA gate that cannot read what it guards denies." % (path, exc)

    if parsed is None:
        return head + "are missing: there is no acceptance.md.\n\n" \
            "A full or hardened spec carries 3-5 Given/When/Then cases the developer confirmed " \
            "before any production code (.claude/rules/spec-interview.md).\n\n" + how
    if parsed["problems"]:
        return head + "do not parse.\n\n" + "\n".join("  - " + p for p in parsed["problems"]) + \
            "\n\nFix %s, then have the developer confirm it.\n\n%s" % (path, how)
    conf = parsed["confirmed"]
    if conf is None:
        return head + "are not confirmed by the developer.\n\n%d cases are drafted in %s and no " \
            "Confirmed line records the developer's answer.\n\n%s" % (len(parsed["cases"]), path, how)
    if conf["digest"] != parsed["digest"]:
        return head + "changed after the developer confirmed them.\n\nThe Confirmed line pins " \
            "digest %s; the cases as they stand digest to %s. Show the developer what changed and " \
            "confirm again (step 2-3 below); never rewrite a case to match the code.\n\n%s" % (
                conf["digest"], parsed["digest"], how)

    # Resolved first: `ln -s ../src tests/link` must not turn tests/link/app.ts into a test file.
    real_root = os.path.realpath(root)
    real_file = os.path.realpath(file_path if os.path.isabs(file_path) else os.path.join(root, file_path))
    if real_file.startswith(real_root + os.sep) and is_test_path(os.path.relpath(real_file, real_root)):
        return None
    numbers = [c["number"] for c in parsed["cases"]]
    if _cached(root, spec_id, parsed["digest"], numbers):
        return None
    try:
        found = named_cases(root, spec_id)
    except ScanFailed:
        return None  # fail open: a scan that times out must not stop work (O6)
    except ScanError as exc:
        return head + "could not be checked against the tests.\n\n%s\n\nOnly a timeout lets an " \
            "edit through; fix git here (safe.directory, a broken .git) and try again." % exc
    missing = [n for n in numbers if n not in found]
    if not missing:
        _store(root, spec_id, parsed["digest"], found)
        return None
    ids = ", ".join("%s-AC-%d" % (spec_id, n) for n in missing)
    return head + "are confirmed, and no test names %s yet.\n\nTests come first: write a test " \
        "for each case that names it (a comment or the test name, e.g. `// %s-AC-%d`) in a test " \
        "file (tests/, test/, __tests__/, e2e/, *.Tests/, *.test.*, *_test.*, *Tests.cs ...). " \
        "Test files are editable now; production source unlocks when every case is named.\n\n" \
        "File you tried to edit: %s" % (ids, spec_id, missing[0], file_path)


# ----------------------------------------------------------------------------------- CLI

def _confirm(spec_dir, quote):
    quote = _collapse(quote or "")
    if not quote:
        print("acceptance-cases: --quote is empty; record the developer's words", file=sys.stderr)
        return 2
    path = os.path.join(spec_dir, "acceptance.md")
    parsed = load(spec_dir)
    if parsed is None:
        print("acceptance-cases: no %s" % path, file=sys.stderr)
        return 2
    problems = [p for p in parsed["problems"] if "Confirmed line" not in p]
    if problems:
        print("acceptance-cases: cannot confirm, the cases do not parse:\n" +
              "\n".join("  - " + p for p in problems), file=sys.stderr)
        return 1
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    line = '%s %s · %s — "%s"' % (CONFIRMED_PREFIX, today, parsed["digest"], quote)
    try:
        with open(path, "r", encoding="utf-8-sig", newline="") as fh:
            raw = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        print("acceptance-cases: cannot rewrite %s: %s" % (path, exc), file=sys.stderr)
        return 2
    eol = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.splitlines()
    out = []
    for i, l in enumerate(lines):
        if l.startswith(CONFIRMED_PREFIX):
            # Drop the old line, and the blank line that separated it, so re-confirming is stable.
            if out and not out[-1].strip() and i + 1 < len(lines) and not lines[i + 1].strip():
                out.pop()
            continue
        out.append(l)
    at = next((i + 1 for i, l in enumerate(out) if l.startswith("# ")), 0)
    block = [line]
    if at:
        block.insert(0, "")
    if at < len(out) and out[at].strip():
        block.append("")
    out[at:at] = block
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        fh.write(eol.join(out) + eol)
    os.replace(tmp, path)
    print(line)
    return 0


def main(argv):
    if len(argv) < 2:
        print("usage: acceptance_cases.py check|digest|confirm|coverage|is-test ...", file=sys.stderr)
        return 2
    cmd = argv[1]
    try:
        if cmd == "is-test":
            return 0 if is_test_path(argv[2]) else 1
        spec_dir = argv[2]
        if cmd == "confirm":
            return _confirm(spec_dir, argv[3] if len(argv) > 3 else "")
        parsed = load(spec_dir)
        if parsed is None:
            print("acceptance-cases: no %s" % os.path.join(spec_dir, "acceptance.md"), file=sys.stderr)
            return 2
        if cmd == "digest":
            print(parsed["digest"])
            return 0
        if cmd == "check":
            for p in parsed["problems"]:
                print("  - " + p)
            if parsed["problems"]:
                return 1
            conf = parsed["confirmed"]
            state = "unconfirmed" if conf is None else (
                "confirmed %s" % conf["date"] if conf["digest"] == parsed["digest"]
                else "digest mismatch (confirmed %s, now %s)" % (conf["digest"], parsed["digest"]))
            print("%d cases, %s" % (len(parsed["cases"]), state))
            return 0 if conf is not None and conf["digest"] == parsed["digest"] else 3
        if cmd == "coverage":
            root, spec_id = argv[3], argv[4]
            named = named_cases(root, spec_id)
            missing = 0
            for c in parsed["cases"]:
                hit = c["number"] in named
                missing += 0 if hit else 1
                print("%s-AC-%d  %s  %s" % (spec_id, c["number"], "named" if hit else "NO TEST", c["title"]))
            return 0 if missing == 0 else 1
    except Unreadable as exc:
        print("acceptance-cases: cannot read: %s" % exc, file=sys.stderr)
        return 2
    except (ScanFailed, ScanError) as exc:
        print("acceptance-cases: scan failed: %s" % exc, file=sys.stderr)
        return 2
    except IndexError:
        print("acceptance-cases: missing argument for %s" % cmd, file=sys.stderr)
        return 2
    print("acceptance-cases: unknown command %s" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
