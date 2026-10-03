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
import glob
import hashlib
import json
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
    """The scan could not answer (a timeout). The coverage scan fails open on this and announces it
    (080 O6); the Confirmed-line backing check denies (095 O2)."""


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
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=_scan_timeout(), env=_git_env(),
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


# Which specs were begun before 080 reached this repository (spec 088 R6, F093). It used to be "the
# interview was first committed before 2026-10-02" by %ci, and GIT_COMMITTER_DATE sets %ci to anything.
# Now it is ancestry, which no date variable moves: the commit that first added the interview is a
# strict ancestor of the commit that first added scripts/acceptance_cases.py here (the template's 080
# commit, or a project's sync commit). Without the date, ticking one setup task would still exempt a
# brand-new spec (080 O5), so the ancestry condition replaces the date rather than dropping it.
# Anything git cannot answer is "not grandfathered": the spec owes cases, and writing them is cheap.
ARRIVAL_PATH = "scripts/acceptance_cases.py"


def _git_env():
    """The environment for every git call here. Spec 095 R5 (F118): every GIT_ variable is dropped, so
    GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE or GIT_CONFIG_* in the hook's environment cannot point the
    gate at another repository or configuration. Replace refs and a grafts file rewrite ancestry
    locally, without any push, so every call ignores both (088 adversarial #7)."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_NO_REPLACE_OBJECTS="1", GIT_GRAFT_FILE=os.devnull, GIT_OPTIONAL_LOCKS="0")
    return env


# Spec 095 R5 (developer O2): a fail-open the hook must say aloud. gate() appends the cause; the
# spec-interview hook passes it to guard_announce.
ANNOUNCE = []


def _git(where, *args):
    """One git call for the 088 checks: (returncode, stdout, stderr). Raises subprocess.TimeoutExpired
    and OSError for the caller to map."""
    env = _git_env()
    proc = subprocess.run(["git", "-C", where] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=_scan_timeout(), env=env)
    return proc.returncode, proc.stdout.decode("utf-8", "replace"), proc.stderr.decode("utf-8", "replace")


def _git_out(where, *args):
    """stdout of a git call that succeeded, else None (timeouts and errors included)."""
    try:
        rc, out, _ = _git(where, *args)
    except (subprocess.TimeoutExpired, OSError):
        return None
    return out if rc == 0 else None


def _add_commit(root, path, oldest):
    """The oldest (or newest) commit that added `path`, or None. The interview takes the NEWEST add:
    a spec directory deleted and re-created at the same path is a new spec (088 adversarial #7)."""
    args = ["log", "--diff-filter=A", "--format=%H"] + ([] if oldest else ["-1"]) + ["--", path]
    shas = (_git_out(root, *args) or "").split()
    return shas[-1] if shas else None


def _strictly_before(root, older, newer):
    return older != newer and _git_out(root, "merge-base", "--is-ancestor", older, newer) is not None


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
    interview = _add_commit(root, os.path.relpath(os.path.join(spec_dir, "interview.md"), root), oldest=False)
    arrival = _add_commit(root, ARRIVAL_PATH, oldest=True)
    return bool(interview and arrival and _strictly_before(root, interview, arrival))


HOW_TO_CONFIRM = """How to get it confirmed:
  1. Draft 3-5 cases in {path}, one per behaviour the developer must see work:

       ## AC-1 — <short title>
       **Given** <the state>
       **When** <the action>
       **Then** <the observable outcome>

  2. Show them to the developer with ONE AskUserQuestion whose question text is exactly what
     bash scripts/acceptance-cases.sh --question {spec_dir}  prints (the digest and every case in
     full), with an option labelled Confirm. Never confirm them yourself: the point is that a
     requirement the developer stated becomes a test. A correction typed under Other confirms
     nothing: edit the cases and ask again.
  3. When they picked Confirm, record it:
       bash scripts/acceptance-cases.sh --confirm {spec_dir} --quote "Confirm"
     --confirm writes only when that click was recorded for a question showing the digest and every
     case (specs 088 and 091: scripts/developer-answers-hook.sh records answers, hashed, in the git dir).
  4. Write one test per case that names it ({spec_id}-AC-<n>) before any production code.

A project that does not want this sets SPEC_ACCEPTANCE=off in .claude/settings.json env."""


def _confirmed_line(text):
    for l in (text or "").lstrip("﻿").splitlines():
        if l.startswith(CONFIRMED_PREFIX):
            return l.rstrip()
    return None


def _committed_unchanged(spec_dir):
    """True when the upstream's acceptance.md carries the same Confirmed line the working tree does.

    Spec 091 R9 (F107). It used to be HEAD's, and a forged line that reached disk by a route no guard
    reads (a script file) was laundered by one local commit. The upstream is a remote-tracking ref,
    which R2 keeps the agent from moving; no upstream, or one that is not under refs/remotes/ (a
    branch tracking `.`), means no shortcut, and the answer store has to back the line."""
    try:
        got = read_file(os.path.join(spec_dir, "acceptance.md"))
    except Unreadable:
        return False
    line = _confirmed_line(got if isinstance(got, str) else None)
    if line is None:
        return False
    # A timeout raises ScanFailed, which the backing check turns into a deny (095 O2); any other git
    # failure denies too.
    try:
        rc, _, err = _git(spec_dir, "rev-parse", "--git-dir")
        if rc != 0:
            raise ScanError("git rev-parse exited %d: %s" % (rc, err.strip()[:200]))
        rc, up, _ = _git(spec_dir, "rev-parse", "--symbolic-full-name", "@{upstream}")
        up = up.strip()
        if rc != 0 or not up.startswith("refs/remotes/"):
            return False                                   # no upstream: no shortcut, not an error
        if os.path.islink(os.path.join(spec_dir, "acceptance.md")):
            return False      # /security-review: a link to another spec's pushed file is not this one
        rc, top, _ = _git(spec_dir, "rev-parse", "--show-toplevel")
        if rc != 0:
            return False
        rel = os.path.relpath(os.path.realpath(os.path.join(spec_dir, "acceptance.md")),
                              os.path.realpath(top.strip())).replace(os.sep, "/")
        if rel.startswith("../"):
            return False
        rc, published, _ = _git(spec_dir, "show", "%s:%s" % (up, rel))
    except subprocess.TimeoutExpired as exc:
        raise ScanFailed(str(exc))
    except OSError as exc:
        raise ScanError("git could not run: %s" % exc)
    return rc == 0 and _confirmed_line(published) == line   # rc != 0: never pushed


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

    # Spec 088 (adversarial #3): a Confirmed line nobody has committed yet must be one --confirm could
    # have written, i.e. its quote is a recorded answer for this digest. trust-anchor-guard stops the
    # shell spellings it can see; this catches the ones it cannot (a printf that splits the prefix, a
    # glob for the file name). A line already on the upstream is trusted (spec 091 R9): the store is per
    # clone, and a pushed commit is in the shared history the developer reads.
    try:
        backed = _committed_unchanged(spec_dir) or answer_bound(spec_dir, conf["quote"], parsed["digest"])
    except ScanFailed:
        # Spec 095 R5 (developer O2): this is the forgery route, so a timeout denies here. The agent
        # can grow the tree until git outlasts the limit.
        return head + "could not be checked against the recorded answers: git timed out " \
            "(ACCEPTANCE_SCAN_TIMEOUT, %ss).\n\nA Confirmed line that is not on the upstream must be " \
            "backed by a recorded answer, and that check fails closed (spec 095). Commit and push the " \
            "line, or make git answer in time, and try again." % _scan_timeout()
    except ScanError as exc:
        return head + "could not be checked against the recorded answers.\n\n%s\n\nOnly a timeout " \
            "lets an edit through; fix git here (safe.directory, a broken .git) and try again." % exc
    if not backed:
        return head + "carry a Confirmed line that no recorded developer answer backs.\n\nThe line " \
            "quotes \"%s\" for digest %s, and no AskUserQuestion answer with those words was " \
            "recorded for a question showing that digest. Only scripts/acceptance-cases.sh --confirm " \
            "writes the line, after the developer answers (spec 088).\n\n%s" % (
                conf["quote"], parsed["digest"], how)

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
        # fail open: a scan that times out must not stop work (080 O6), and it says so (095 O2)
        ANNOUNCE.append("git grep for the %s-AC-n test names timed out (ACCEPTANCE_SCAN_TIMEOUT)" % spec_id)
        return None
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

# ------------------------------------------------------------------- the developer's answers
# Spec 088 R4/R5 (F094). --confirm used to write whatever it was given as "the developer's words".
# Now the words must be an answer the developer gave in an AskUserQuestion, to a question that showed
# the cases' digest. scripts/developer-answers-hook.sh (PostToolUse, AskUserQuestion) records one line per
# answered question in <git-common-dir>/claude-developer-words:
#
#     <epoch> <sha256 of the whitespace-collapsed answer> [<12-hex digest shown in the question> ...]
#
# Hashes only: an answer never lands on disk as text. The file is in the git dir (never committed or
# synced) and scripts/trust-anchor-guard-hook.sh keeps the agent's tools out of it. It keeps the last
# WORDS_KEEP lines; a lost line costs one re-ask.
WORDS_FILE = "claude-developer-words"
WORDS_KEEP = 500
_DIGEST_TOKEN = re.compile(r"(?<![0-9a-f])[0-9a-f]{%d}(?![0-9a-f])" % DIGEST_CHARS)


def _words_path(start):
    """<git-common-dir>/claude-developer-words for the repository holding `start`, or None."""
    gd = (_git_out(start, "rev-parse", "--git-common-dir") or "").strip()
    if not gd:
        return None
    if not os.path.isabs(gd):
        gd = os.path.join(start, gd)
    return os.path.join(os.path.realpath(gd), WORDS_FILE)


def answer_hash(text):
    return hashlib.sha256(_collapse(text).encode("utf-8")).hexdigest()


def _answers_of(payload):
    """[(question, answer)] from a PostToolUse AskUserQuestion payload. Measured 2026-10-01:
    tool_response is {questions, answers} with answers keyed by the question text. Only tool_response is
    read (spec 091 A8): tool_input is what the agent sent."""
    if not isinstance(payload, dict):
        return []
    holder = payload.get("tool_response")
    a = holder.get("answers") if isinstance(holder, dict) else None
    if not isinstance(a, dict):
        return []
    out = []
    for q, v in a.items():
        if isinstance(v, list):
            v = ", ".join(str(x) for x in v)
        if isinstance(q, str) and isinstance(v, str) and _collapse(v):
            out.append((q, v))
    return out


CONFIRM_LABEL = "Confirm"


def question_text(spec_dir, parsed=None):
    """The question --question prints: the digest, then every case in full, then how to answer. Spec 091
    R8 binds a digest only to an answer given to exactly this text (whitespace aside), so one function
    both shows the cases and decides what counts as having shown them."""
    parsed = parsed or load(spec_dir)
    if parsed is None:
        return None
    lines = ["Acceptance cases for spec %s (digest %s). Do these describe done?" % (
        os.path.basename(os.path.normpath(spec_dir)), parsed["digest"]), ""]
    for c in parsed["cases"]:
        lines += ["AC-%d — %s" % (c["number"], c["title"]),
                  "Given %s" % c["Given"], "When %s" % c["When"], "Then %s" % c["Then"], ""]
    lines.append('Options: "%s" if they do; Other, with what to change, if not.' % CONFIRM_LABEL)
    return "\n".join(lines)


def _disk_digests(start):
    """Digests of every specs/*/acceptance.md on disk now (the repository root, .specify/, and one
    package level down for a monorepo). A digest the question shows counts only if it is one of these
    (/tla GAP-1, spec 088): otherwise the agent could show a digest it precomputed for case text that
    is not on disk yet, get a yes for what is, then write the other text and confirm it."""
    top = (_git_out(start, "rev-parse", "--show-toplevel") or "").strip()
    found = {}
    for f in acceptance_files(top) if top else ():
        try:
            parsed = load(os.path.dirname(f))
        except Exception:
            continue
        if parsed and parsed.get("digest"):
            found.setdefault(parsed["digest"], _collapse(question_text(os.path.dirname(f), parsed)))
    return found


# Where an acceptance.md can live under a project root. One list for the digest filter above and for
# trust-anchor-guard-hook.sh, which imports it.
ACCEPTANCE_GLOBS = ("specs/*/acceptance.md", ".specify/specs/*/acceptance.md", "*/specs/*/acceptance.md")


def acceptance_files(root):
    return [f for pattern in ACCEPTANCE_GLOBS for f in glob.glob(os.path.join(root, pattern))]


def record_answers(payload, start):
    """Append one line per answered question. Returns the number recorded."""
    pairs = _answers_of(payload)
    path = _words_path(start) if pairs else None
    if not path:
        return 0
    on_disk = _disk_digests(start)
    now = int(datetime.datetime.now(datetime.timezone.utc).timestamp())

    # Spec 091 R8 (F104, O3). A digest is bound only to a click on Confirm, to the --question text for
    # the cases on disk. "No" to an unrelated question that happened to show the digest binds nothing.
    def bound(q, v):
        if _collapse(v).casefold() != CONFIRM_LABEL.casefold():
            return []
        return [d for d in _DIGEST_TOKEN.findall(q) if on_disk.get(d) == _collapse(q)]

    lines = "".join("%d %s%s\n" % (now, answer_hash(v), "".join(" " + d for d in bound(q, v)))
                    for q, v in pairs)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, lines.encode("ascii"))
    finally:
        os.close(fd)
    try:
        with open(path, "r", encoding="ascii", errors="replace") as fh:
            kept = fh.readlines()
        if len(kept) > WORDS_KEEP:
            tmp = "%s.tmp.%d" % (path, os.getpid())
            with open(tmp, "w", encoding="ascii") as fh:
                fh.writelines(kept[-WORDS_KEEP:])
            os.replace(tmp, path)
    except OSError:
        pass
    return len(pairs)


def answer_bound(start, quote, digest):
    """True when the store holds an answer equal to `quote` given to a question showing `digest`."""
    path = _words_path(start)
    if not path or not os.path.isfile(path):
        return False
    want = answer_hash(quote)
    try:
        with open(path, "r", encoding="ascii", errors="replace") as fh:
            for line in fh:
                f = line.split()
                if len(f) >= 3 and f[1] == want and digest in f[2:]:
                    return True
    except OSError:
        return False
    return False


NOT_BOUND = """acceptance-cases: not confirmed — no AskUserQuestion answer matches this quote for digest {digest}.

--confirm records the developer's answer, so the answer has to be one they gave (specs 088 and 091):
  1. Ask ONE AskUserQuestion whose question text is what
       bash scripts/acceptance-cases.sh --question {spec_dir}
     prints (digest {digest} and every case in full), with an option labelled Confirm.
  2. When they pick Confirm:
       bash scripts/acceptance-cases.sh --confirm {spec_dir} --quote "Confirm"
     Any other answer, a typed one included, confirms nothing.
Answers are recorded by scripts/developer-answers-hook.sh. If it is not wired in this project, run the
template sync first. Nothing was written."""


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
    if not answer_bound(spec_dir, quote, parsed["digest"]):
        print(NOT_BOUND.format(digest=parsed["digest"], spec_dir=spec_dir), file=sys.stderr)
        return 3
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
        print("usage: acceptance_cases.py check|digest|question|confirm|coverage|is-test|record-answers ...", file=sys.stderr)
        return 2
    cmd = argv[1]
    try:
        if cmd == "is-test":
            return 0 if is_test_path(argv[2]) else 1
        if cmd == "record-answers":
            # The PostToolUse hook. Never fails the tool call: a payload it cannot read records nothing.
            # The repository is the given directory (CLAUDE_PROJECT_DIR), else the payload's cwd.
            try:
                payload = json.loads(sys.stdin.read())
                start = argv[2] if len(argv) > 2 and os.path.isdir(argv[2]) else payload.get("cwd") or ""
                if os.path.isdir(start):
                    record_answers(payload, start)
            except Exception:
                pass
            return 0
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
        if cmd == "question":
            print(question_text(spec_dir))
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
