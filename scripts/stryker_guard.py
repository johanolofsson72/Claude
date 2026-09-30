#!/usr/bin/env python3
"""stryker_guard.py -- the two ways a Stryker.NET run reads as success and measured nothing (row 047).

    python3 scripts/stryker_guard.py configs <root>   # every committed config's mutate patterns
    python3 scripts/stryker_guard.py live <root>      # Stryker or a dotnet build running in <root>
    STRYKER_GUARD_CMD='<bash command>' python3 scripts/stryker_guard.py command <root>

1. THE PATTERN SAYS ONE THING AND STRYKER DOES ANOTHER. ighweld-2026 measured three shapes:
   `'**/X.cs{845-1080}'` (F184) has a hyphen where Stryker wants `..`, so the braces become part of
   the glob, the glob matches no file, and the run still prints a score. `{98..120}` (F197) is a
   CHARACTER span -- Stryker's docs say "the indices of the first character and the last character"
   under a heading that says "lines" -- so a line-numbered span scopes a couple of dozen characters.
   And a well-formed span did not shrink the run at all (F185). None of the three is an error to
   Stryker, so none of them is visible in its output.

2. A SECOND BUILD OVERWRITES THE MUTATED ASSEMBLY (F069). A `dotnet build` or `dotnet test` in the
   same project while Stryker runs replaces the assembly Stryker is testing, and the run scores about
   0% with no warning. ighweld lost a full run to it.

Both callers -- section 5 of project-maintenance.sh and stryker-guard-hook.sh -- ask this file, so
the rules exist once. Output is TSV; the last column of a line is the sentence the caller prints.

THE COST OF A WRONG ANSWER IS NOT SYMMETRIC. The hook sits in front of every `dotnet` command Claude
issues, and a false deny there blocks work for the length of a Stryker run -- hours. So a process is a
build only when its EXECUTABLE is dotnet and its first argument is a verb, never because the words
appear somewhere in its arguments (a `git commit -m "fix dotnet test"` is not a build); `--no-build`
and `--help` build nothing; and every input it cannot read fails open in the hook. The maintenance
report is the other way round: an unreadable input is said, never passed as clean.

What this does NOT read, on purpose: a pattern assembled at runtime (`-m "$P"`) -- guessing what it
expands to would invent a finding, so it is reported as skipped. StrykerJS patterns have their own
range syntax and are out of scope. The live check scopes to the project ROOT, not to one .csproj: a
Stryker run on project A also refuses `dotnet build B/` in the same repository.
"""
import json
import os
import re
import shlex
import subprocess
import sys

PRUNE = {"bin", "obj", "node_modules", ".git", "StrykerOutput", ".stryker-tmp"}
GOOD_SPAN = re.compile(r"\{(\d{1,12})\.\.(\d{1,12})\}")
PATTERN_LIMIT = 512       # characters of one mutate pattern the glob matcher will compile
PARSE_LIMIT = 64 * 1024   # bytes of command the tokenizer reads; shlex is superlinear (1 MB took 19 s)

# The command side includes `run` and `watch`: both build first, and the build is the collision. The
# process side leaves them out -- a `dotnet run` web server or a `dotnet watch` lives for hours, and
# blocking Stryker for as long as a terminal stays open is the false deny this file exists to avoid.
CMD_VERBS = ("build", "test", "run", "publish", "pack", "msbuild", "vstest", "watch")
PROC_VERBS = tuple(v for v in CMD_VERBS if v not in ("run", "watch"))
NO_BUILD = ("--no-build", "-h", "--help", "-?")
SHELLS = ("bash", "sh", "zsh", "dash")
RUNNER = "run-mutation-gate.sh"   # the project-local runner, in scripts/ (not shipped; 045)
SEPARATORS = set(";&|()")
ECHO_LIMIT = 120                  # characters of a pattern quoted back in a deny reason

MSG = {
    "badspan": "has a span Stryker cannot read (a span is {start..end}, two dots). Stryker treats the "
               "braces as part of the glob, matches no file and still reports a score (ighweld F184).",
    "nomatch": "matches no .cs file. Stryker mutates nothing for it and still reports a score "
               "(ighweld F184).",
    "span": "carries a span. Spans are CHARACTER offsets, not line numbers (Stryker docs: 'the indices "
            "of the first character and the last character'), and a span did not shrink the run "
            "(ighweld F185). Mutate the whole file.",
    "unreadable": "could not be parsed, so it was not checked.",
}


# ----------------------------------------------------------------------------------- patterns

def scan(root):
    """(.cs files, stryker-config*.json files) under root, relative with `/`, in one walk."""
    cs, configs = [], []
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in PRUNE]
        for f in files:
            low = f.lower()
            if low.endswith(".cs"):
                cs.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/"))
            elif low.startswith("stryker-config") and low.endswith(".json"):
                configs.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/"))
    return cs, configs


def glob_rx(g):
    g = g.replace("\\", "/")
    while g.startswith("./"):
        g = g[2:]
    g = g.lstrip("/")
    g = re.sub(r"(?:\*\*/)+", "**/", g)       # `**/**/` is `**/`, and N of them is O(depth^N)
    g = re.sub(r"\*{3,}", "**", g)
    i, out = 0, ""
    while i < len(g):
        if g.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif g.startswith("**", i):
            out, i = out + ".*", i + 2
        elif g[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif g[i] == "?":
            out, i = out + "[^/]", i + 1
        elif g[i] == "[" and (j := g.find("]", i + 2)) != -1:
            cls = g[i + 1:j]
            if cls.startswith("!"):
                cls = "^" + cls[1:]
            out, i = out + "[" + cls.replace("\\", "\\\\") + "]", j + 1
        else:
            out, i = out + re.escape(g[i]), i + 1
    # Anchored at the start or after any `/`, so it matches the full relative path or any trailing run
    # of its segments. Case-insensitive because the claim is "nothing could match": leniency can only
    # miss a finding, never invent one.
    return re.compile(r"(?:.*/)?" + out + r"\Z", re.I)


def matches_any(glob, files):
    # Lenient on purpose: the full relative path, or any trailing run of its segments. The verdict
    # "matches nothing" is only ever claimed when no reading of the base directory could match.
    if not glob:
        return False
    rx = glob_rx(glob)
    return any(rx.match(f) for f in files)


def split_spans(body):
    """(glob, [brace groups]) -- trailing {...} groups, scanned right to left, no regex."""
    groups, end = [], len(body)
    while end > 0 and body[end - 1] == "}":
        start = body.rfind("{", 0, end - 1)
        if start == -1 or "}" in body[start + 1:end - 1]:
            break
        groups.append(body[start:end])
        end = start
    return body[:end], groups[::-1]


def classify(pattern, files):
    if len(pattern) > PATTERN_LIMIT:
        return "unreadable"
    neg = pattern.startswith("!")
    body = pattern[1:] if neg else pattern
    glob, spans = split_spans(body)
    try:
        for group in spans:
            gm = GOOD_SPAN.fullmatch(group)
            if not gm or int(gm.group(1)) > int(gm.group(2)):
                return "badspan"
        if not neg and not matches_any(glob, files):
            return "nomatch"
    except re.error:
        return "unreadable"
    return "span" if spans else "ok"


def mutate_values(toks):
    """(literal values, count of runtime-assembled ones) for -m/--mutate in a token list."""
    vals, skipped = [], 0
    for i, t in enumerate(toks):
        v = None
        if t in ("-m", "--mutate") and i + 1 < len(toks):
            v = toks[i + 1]
        elif t.startswith("--mutate="):
            v = t[len("--mutate="):]
        if v is None:
            continue
        if "$" in v:
            skipped += 1   # after shlex the quoting is gone, so a `$` is never read as literal
        else:
            vals.append(v)
    return vals, skipped


def runner_patterns(root):
    """Literal -m/--mutate values on the Stryker lines of the project runner, with line numbers."""
    found, skipped = [], 0
    try:
        raw = open(os.path.join(root, "scripts", RUNNER), encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return found, skipped
    i = 0
    while i < len(raw):
        n, line = i + 1, raw[i]
        while line.endswith("\\") and i + 1 < len(raw):   # join continuation lines
            i += 1
            line = line[:-1] + " " + raw[i]
        i += 1
        try:
            toks = shlex.split(line, comments=True)
        except ValueError:
            continue
        # Only a line that runs Stryker: `grep -m 1`, `python3 -m json.tool` and `git commit -m` are
        # not mutate patterns.
        if not any("stryker" in t.lower() for t in toks):
            continue
        vals, sk = mutate_values(toks)
        skipped += sk
        found.extend(("scripts/%s:%d" % (RUNNER, n), v) for v in vals)
    return found, skipped


def loads_lenient(text):
    """JSON as the .NET config reader takes it: BOM, // and /* */ comments, trailing commas."""
    text = text.lstrip("\ufeff")
    tok = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/|,(?=\s*[}\]])', re.S)
    return json.loads(tok.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "", text))


def ci_get(d, key):
    for k, v in d.items():
        if isinstance(k, str) and k.lower() == key:
            return v
    return None


def cmd_configs(root):
    files, configs = scan(root)
    items = []
    for rel in sorted(configs):
        try:
            d = loads_lenient(open(os.path.join(root, rel), encoding="utf-8", errors="replace").read())
        except Exception:
            print("unreadable\t%s\t-\tis not JSON, so its mutate patterns were not checked." % rel)
            continue
        if not isinstance(d, dict):
            continue
        inner = ci_get(d, "stryker-config")
        d = inner if isinstance(inner, dict) else d
        mut = ci_get(d, "mutate")
        if isinstance(mut, str):
            mut = [mut]
        if isinstance(mut, list):
            items.extend((rel, p) for p in mut if isinstance(p, str))
    found, skipped = runner_patterns(root)
    items.extend(found)
    if skipped:
        print("skipped\tscripts/%s\t-\thas %d runtime-assembled pattern(s) ($...) that were not checked."
              % (RUNNER, skipped))
    for src, p in items:
        v = classify(p, files)
        if v != "ok":
            print("%s\t%s\t%s\t%s" % (v, src, p.replace("\t", " "), MSG[v]))
    return 0


# ----------------------------------------------------------------------------------- invocations

def argv_kind(toks, verbs):
    """'stryker' | 'build' | None for an argv starting at the program -- by executable and verb, never
    by substring. One reading for both sides: the process table (PROC_VERBS) and a command (CMD_VERBS)."""
    if not toks:
        return None
    exe = os.path.basename(toks[0]).lower()
    if exe == RUNNER:
        return "stryker"
    if exe in ("dotnet-stryker", "dotnet-stryker.exe"):
        return "stryker"
    if exe not in ("dotnet", "dotnet.exe") or len(toks) < 2:
        return None
    first = toks[1]
    target = toks[2] if first == "exec" and len(toks) > 2 else first
    if first == "stryker" or toks[1:3] == ["tool", "run"] and toks[3:4] == ["dotnet-stryker"]:
        return "stryker"
    if "stryker.cli" in os.path.basename(target).lower():
        return "stryker"
    if first in verbs and not any(t in NO_BUILD for t in toks[2:]):
        return "build"
    return None


def skip_interpreter(toks):
    """`bash -x scripts/run-mutation-gate.sh` or a shim script: the script is the program."""
    if toks and os.path.basename(toks[0]) in SHELLS:
        j = 1
        while j < len(toks) and toks[j].startswith("-") and toks[j] != "-c":
            j += 1
        if j < len(toks) and not toks[j].startswith("-"):
            return toks[j:]
    return toks


# ----------------------------------------------------------------------------------- processes

def cwds_of(pids):
    """{pid: cwd} for the pids it could read. One lsof call for all of them, not one each."""
    out, rest = {}, []
    for p in pids:
        try:
            out[p] = os.readlink("/proc/%s/cwd" % p)
        except OSError:
            rest.append(p)
    if not rest:
        return out
    try:
        r = subprocess.run(["lsof", "-a", "-d", "cwd", "-p", ",".join(rest), "-Fpn"],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return out
    cur = None
    for line in r.stdout.splitlines():
        if line.startswith("p"):
            cur = line[1:]
        elif line.startswith("n") and cur:
            out[cur] = line[1:]
    return out


def live(root, kinds=("stryker", "build")):
    """([(pid, kind, args)] of those kinds inside root, [why the table was incomplete])."""
    try:
        r = subprocess.run(["ps", "-Ao", "pid=,ppid=,args="], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None, ["ps could not be run"]
    if r.returncode != 0 or not r.stdout.strip():
        return None, ["ps -Ao pid=,ppid=,args= is not supported here"]
    rows, parent = [], {}
    for line in r.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3:
            rows.append(parts)
            parent[parts[0]] = parts[1]
    # My own ancestors are waiting on me, so none of them is a concurrent build -- even one that is a
    # `dotnet test` running a test that shells out to this file.
    mine, p = set(), str(os.getpid())
    while p in parent and p not in mine:
        mine.add(p)
        p = parent[p]
    cands = [(pid, argv_kind(skip_interpreter(args.split()), PROC_VERBS), args)
             for pid, _pp, args in rows if pid not in mine]
    cands = [c for c in cands if c[1] in kinds]   # a cwd is only looked up when it can matter
    if not cands:
        return [], []
    where = cwds_of([c[0] for c in cands])
    real_root = os.path.realpath(root).rstrip("/")
    found, blind = [], []
    for pid, kind, args in cands:
        cwd = where.get(pid)
        if not cwd:
            blind.append("the working directory of pid %s (%s) could not be read" % (pid, kind))
            continue
        cwd = os.path.realpath(cwd)
        if cwd == real_root or cwd.startswith(real_root + "/"):
            found.append((pid, kind, args[:200]))
    return found, blind


# ----------------------------------------------------------------------------------- commands

WRAPPERS = {"env", "nohup", "time", "exec", "command", "nice", "sudo", "timeout", "gtimeout", "caffeinate"}
KEYWORDS = {"if", "then", "elif", "else", "do", "while", "until", "!", "{", "}"}
OPT_WITH_VALUE = {"-n", "-k", "-s", "-u", "--signal", "--kill-after", "--adjustment", "--unset"}


def strip_heredocs(cmd):
    """Drop heredoc bodies: a line of prose inside `cat > f <<EOF` is data, not a command."""
    out, ends = [], []
    for line in cmd.split("\n"):
        if ends:
            if line.strip() == ends[0]:
                ends.pop(0)
            continue
        out.append(line)
        ends.extend(m.group(2) for m in re.finditer(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line))
    return "\n".join(out)


def simple_commands(cmd):
    lex = shlex.shlex(cmd.replace("\n", " ; "), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    cur = []
    for t in lex:
        if t and set(t) <= SEPARATORS:
            if cur:
                yield cur
            cur = []
        else:
            cur.append(t)
    if cur:
        yield cur


def invocation(toks):
    """(kind, the invocation's own argv) after env assignments, shell keywords and wrappers."""
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in KEYWORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
        elif t in WRAPPERS:
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 2 if toks[i] in OPT_WITH_VALUE else 1
            if t in ("timeout", "gtimeout") and i < len(toks) and re.match(r"^[0-9.]+[smhd]?$", toks[i]):
                i += 1
        else:
            break
    argv = skip_interpreter(toks[i:])
    return argv_kind(argv, CMD_VERBS), argv


def verdict(root, cmd):
    """[] to allow, or the reasons to deny."""
    if not cmd or "STRYKER_GUARD=off" in cmd:
        return []
    body = strip_heredocs(cmd)
    kinds, pats = set(), []
    if len(body) > PARSE_LIMIT:
        # A command this size after its heredocs are gone is not a dotnet call worth tokenizing, so it
        # gets a coarse reading: the run-alone half still holds, the pattern half is skipped.
        if re.search(r"(?:^|[\s;&|(])(?:dotnet\s+stryker|dotnet-stryker|\S*%s)\b" % re.escape(RUNNER), body):
            kinds.add("stryker")
        if re.search(r"(?:^|[\s;&|(])dotnet\s+(?:%s)(?=\s|$|;)" % "|".join(CMD_VERBS), body):
            kinds.add("build")
    else:
        try:
            cmds = list(simple_commands(body))
        except ValueError:
            return []  # unbalanced quoting: fail open
        for toks in cmds:
            kind, argv = invocation(toks)
            kinds.add(kind)
            if kind == "stryker":
                pats.extend(mutate_values(argv[1:])[0])
    kinds.discard(None)
    if not kinds:
        return []
    starts_stryker = "stryker" in kinds
    # Starting Stryker collides with anything; a build collides only with Stryker, so only a live
    # Stryker's cwd is worth a lookup.
    running, _blind = live(root, ("stryker", "build") if starts_stryker else ("stryker",))
    reasons = []
    for pid, k, args in running or []:       # an unreadable table fails open here: the hook allows
        reasons.append("%s is running in this project (pid %s: %s). Stryker must run alone: a build beside "
                       "it overwrites the mutated assembly and the run scores about 0%% with no warning "
                       "(ighweld F069). Wait for it to finish, or stop it." %
                       ("a Stryker run" if k == "stryker" else "a dotnet build/test", pid, args))
    if pats:
        files, _ = scan(root)
        spans_ok = "STRYKER_SPANS_ARE_CHARACTERS=1" in cmd
        for p in pats:
            v = classify(p, files)
            if v in ("ok", "unreadable") or (v == "span" and spans_ok):
                continue
            shown = p if len(p) <= ECHO_LIMIT else p[:ECHO_LIMIT] + "..."
            extra = " If you mean characters, prefix STRYKER_SPANS_ARE_CHARACTERS=1." if v == "span" else ""
            reasons.append("mutate pattern '%s' %s%s" % (shown, MSG[v], extra))
    return reasons


def main(argv):
    if len(argv) != 3 or argv[1] not in ("configs", "live", "command"):
        sys.stderr.write(__doc__)
        return 2
    root = argv[2]
    if argv[1] == "configs":
        return cmd_configs(root)
    if argv[1] == "live":
        found, blind = live(root)
        for pid, kind, args in found or []:
            print("%s\t%s\t%s" % (pid, kind, args))
        for why in blind:
            print("unknown\t-\t%s" % why)
        return 0
    reasons = verdict(root, os.environ.get("STRYKER_GUARD_CMD", ""))
    print("deny\t" + " | ".join(reasons) + " (row 047; override: STRYKER_GUARD=off)" if reasons else "allow")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
