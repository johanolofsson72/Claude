#!/usr/bin/env bash
# bench-hooks.sh — what one tool call costs in hook latency, measured against the real wiring.
#
#   bash scripts/bench-hooks.sh                    # fixture project, 5 runs per event
#   bash scripts/bench-hooks.sh --runs 9           # more runs, steadier medians
#   bash scripts/bench-hooks.sh --per-hook         # also print every hook's own median
#   bash scripts/bench-hooks.sh --project ~/repos/x  # a real project instead of the fixture
#   bash scripts/bench-hooks.sh --settings path/to/settings.json
#
# WHY IT EXISTS (spec 073, R9)
# ----------------------------
# 60 hooks are wired, and eight of them run on every Edit before the edit happens. Nobody felt any
# single one of them; everybody felt all of them together. A number that is felt and never measured
# gets argued about instead of fixed, so this prints it.
#
# WHAT IT RUNS — THE WIRING, NOT A LIST OF SCRIPTS
# ------------------------------------------------
# It reads .claude/settings.json and, per event, runs exactly the handlers Claude Code would: the
# `matcher` is tested against the tool name, the `if` rule against the tool input, and each command is
# started through /bin/sh with the payload on stdin, CLAUDE_PROJECT_DIR set, from the project root. A
# benchmark of a hand-copied list would measure the list, and the list is what drifts.
#
# TWO NUMBERS PER EVENT
# ---------------------
#   seq — every matching handler one after another: the CPU the call costs, and the wall time on a
#         harness that serialised them.
#   par — every matching handler at once, which is how Claude Code runs them ("All matching hooks run
#         in parallel", code.claude.com/docs/en/hooks). This is the delay the developer waits through.
# Both are reported because they fail differently: one slow hook dominates `par`, many cheap hooks
# dominate `seq`, and a change that fixes one can leave the other exactly where it was.
#
# THE FIXTURE
# -----------
# A throwaway git repository shaped like a project in mid-implementation: a .csproj marker, a register
# whose active spec has every artifact and a 15-answer interview (so the pipeline guards run to their
# end instead of exiting early — the common case while code is being written), 300 tracked source
# files, and a gitignored build/ with 3000 files, which is what a Flutter or Xcode tree carries. The
# scripts/ directory is a symlink to this repository's, so the hooks under test are the ones here.
#
# Bash events run pre -> the command itself -> post, in that order, because the post-layer compares the
# filesystem against a marker the pre-layer stamps; timing them apart would measure a state that never
# occurs.
#
# Exit: 0 printed a table · 2 could not run (no jq/python3, unreadable settings, bad argument).

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

command -v python3 >/dev/null 2>&1 || { echo "bench-hooks: python3 is required" >&2; exit 2; }
command -v jq      >/dev/null 2>&1 || { echo "bench-hooks: jq is required" >&2; exit 2; }

BENCH_SCRIPT_DIR="$SCRIPT_DIR" BENCH_REPO_ROOT="$REPO_ROOT" exec python3 - "$@" <<'PY'
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import uuid

script_dir = os.environ["BENCH_SCRIPT_DIR"]
repo_root = os.environ["BENCH_REPO_ROOT"]

args = sys.argv[1:]
runs = 5
per_hook = False
project = None
settings_path = os.path.join(repo_root, ".claude", "settings.json")
i = 0
while i < len(args):
    a = args[i]
    if a == "--runs" and i + 1 < len(args):
        runs = int(args[i + 1]); i += 2; continue
    if a == "--per-hook":
        per_hook = True; i += 1; continue
    if a == "--project" and i + 1 < len(args):
        project = os.path.abspath(os.path.expanduser(args[i + 1])); i += 2; continue
    if a == "--settings" and i + 1 < len(args):
        settings_path = os.path.abspath(args[i + 1]); i += 2; continue
    if a in ("-h", "--help"):
        with open(os.path.join(script_dir, "bench-hooks.sh")) as f:
            for line in f.readlines()[1:9]:
                print(line[2:].rstrip())
        sys.exit(0)
    print(f"bench-hooks: unknown argument {a}", file=sys.stderr)
    sys.exit(2)

try:
    with open(settings_path) as f:
        settings = json.load(f)
except Exception as e:  # noqa: BLE001
    print(f"bench-hooks: cannot read {settings_path}: {e}", file=sys.stderr)
    sys.exit(2)


def sh(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, shell=True, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def make_fixture():
    root = tempfile.mkdtemp(prefix="bench-hooks-")
    os.makedirs(os.path.join(root, ".claude"))
    os.symlink(script_dir, os.path.join(root, "scripts"))
    open(os.path.join(root, "App.csproj"), "w").write("<Project />\n")
    spec = os.path.join(root, "specs", "001-bench")
    os.makedirs(spec)
    open(os.path.join(root, "specs", "INDEX.md"), "w").write(
        "# Spec register\n\n## Specs\n\n- [/] 001 — bench — full track — benchmark row\n")
    open(os.path.join(spec, "spec.md"), "w").write("# Spec\n\n## Clarifications\n\n- none\n")
    for name in ("spec.allium", "plan.md", "tasks.md"):
        open(os.path.join(spec, name), "w").write("x\n")
    with open(os.path.join(spec, "interview.md"), "w") as f:
        f.write("# Spec interview — 001-bench\n\n")
        for q in range(1, 16):
            f.write(f"## Q{q} — q\n**Q:** q?\n**A (auto):** a.\n\n")
    for d in range(30):
        p = os.path.join(root, "src", f"Mod{d}")
        os.makedirs(p)
        for n in range(10):
            open(os.path.join(p, f"C{n}.cs"), "w").write("class C {}\n")
    for d in range(30):
        p = os.path.join(root, "build", f"out{d}")
        os.makedirs(p)
        for n in range(100):
            open(os.path.join(p, f"o{n}.o"), "w").write("x")
    os.makedirs(os.path.join(root, "out"))
    open(os.path.join(root, ".gitignore"), "w").write("build/\nout/\n.claude/state/\n.claude/.bash-write-marker\n.claude/.bash-write-blocked\n")
    sh("git init -q && git add -A . && git -c user.name=b -c user.email=b@b commit -qm fixture", root)
    return root


fixture = project is None
root = make_fixture() if fixture else project
if not os.path.isdir(root):
    print(f"bench-hooks: no such project {root}", file=sys.stderr)
    sys.exit(2)

source_file = os.path.join(root, "src", "Mod1", "C1.cs") if fixture else os.path.join(root, "BenchHooksProbe.cs")
write_target = os.path.join(root, "out", "bench.txt") if fixture else os.path.join(root, ".claude", "bench-hooks.tmp")


# ---------------------------------------------------------------- matching, as Claude Code does it
def glob_to_regex(glob):
    out = ""
    i = 0
    while i < len(glob):
        if glob.startswith("**/", i):
            out += "(?:.*/)?"; i += 3; continue
        if glob.startswith("**", i):
            out += ".*"; i += 2; continue
        c = glob[i]
        if c == "*":
            out += "[^/]*"
        elif c == "?":
            out += "[^/]"
        else:
            out += re.escape(c)
        i += 1
    return "^" + out + "$"


FILE_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit", "Read")


def if_matches(rule, tool, tool_input):
    """Permission-rule subset the wiring uses: Tool(pattern)."""
    m = re.match(r"^(\w+)\((.*)\)$", rule or "")
    if not m:
        return True
    rtool, pattern = m.group(1), m.group(2)
    if rtool == "Edit" and tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path", "")
        rel = os.path.relpath(path, root) if path.startswith(root + "/") else path
        return re.match(glob_to_regex(pattern), rel) is not None
    if rtool != tool:
        return False
    if tool == "Bash":
        cmd = tool_input.get("command", "")
        # Every subcommand is checked; one match runs the hook.
        for sub in re.split(r"&&|\|\||[;|\n]", cmd):
            sub = re.sub(r"^\s*(\w+=\S*\s+)*", "", sub).strip()
            if re.match(glob_to_regex(pattern.replace(":*", " *")).replace("[^/]*", ".*"), sub):
                return True
        return False
    return True


def handlers(event, tool, tool_input):
    out = []
    for group in settings.get("hooks", {}).get(event, []):
        matcher = group.get("matcher", "")
        if matcher and matcher != "*" and not re.fullmatch(matcher, tool):
            continue
        for h in group.get("hooks", []):
            if h.get("type", "command") != "command":
                continue
            if "if" in h and not if_matches(h["if"], tool, tool_input):
                continue
            out.append(h["command"])
    return out


def payload(event, tool, tool_input, tool_use_id):
    p = {
        "session_id": "bench", "transcript_path": "/dev/null", "cwd": root,
        "permission_mode": "default", "hook_event_name": event,
        "tool_name": tool, "tool_input": tool_input, "tool_use_id": tool_use_id,
    }
    if event == "PostToolUse":
        p["tool_response"] = {"stdout": "", "stderr": "", "interrupted": False}
    return json.dumps(p)


ENV = dict(os.environ, CLAUDE_PROJECT_DIR=root)


def run_one(cmd, data):
    t = time.perf_counter()
    subprocess.run(["/bin/sh", "-c", cmd], input=data.encode(), cwd=root, env=ENV,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return (time.perf_counter() - t) * 1000


def run_seq(cmds, data):
    return [run_one(c, data) for c in cmds]


def run_par(cmds, data):
    t = time.perf_counter()
    procs = [subprocess.Popen(["/bin/sh", "-c", c], stdin=subprocess.PIPE, cwd=root, env=ENV,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for c in cmds]
    for p in procs:
        try:
            p.stdin.write(data.encode()); p.stdin.close()
        except BrokenPipeError:
            pass
    for p in procs:
        p.wait()
    return (time.perf_counter() - t) * 1000


EVENTS = [
    # (label, tool, tool_input, shell command to perform between pre and post, or None)
    ("Edit source (.cs)", "Edit", {"file_path": source_file, "old_string": "class C {}", "new_string": "class C {}"}, None),
    ("Edit markdown", "Edit", {"file_path": os.path.join(root, "docs", "notes.md"), "old_string": "a", "new_string": "b"}, None),
    ("Bash ls", "Bash", {"command": "ls -la", "description": "list"}, "ls -la"),
    ("Bash grep 2>/dev/null", "Bash", {"command": "grep -rn class src 2>/dev/null | head -5", "description": "search"},
     "grep -rn class src 2>/dev/null | head -5"),
    ("Bash write file", "Bash", {"command": f"echo hi > {write_target}", "description": "write"},
     f"echo hi > '{write_target}'"),
]

results = []
hook_times = {}
for label, tool, tin, action in EVENTS:
    pre = handlers("PreToolUse", tool, tin)
    post = handlers("PostToolUse", tool, tin)
    rows = {("pre", "seq"): [], ("pre", "par"): [], ("post", "seq"): [], ("post", "par"): []}
    for r in range(runs + 1):              # run 0 warms caches and is discarded
        for mode in ("seq", "par"):
            tid = "toolu_bench_" + uuid.uuid4().hex[:12]
            d_pre = payload("PreToolUse", tool, tin, tid)
            d_post = payload("PostToolUse", tool, tin, tid)
            if mode == "seq":
                per = run_seq(pre, d_pre); t_pre = sum(per)
            else:
                t_pre = run_par(pre, d_pre); per = None
            if action:
                subprocess.run(["/bin/sh", "-c", action], cwd=root,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if mode == "seq":
                per2 = run_seq(post, d_post); t_post = sum(per2)
            else:
                t_post = run_par(post, d_post); per2 = None
            if r == 0:
                continue
            rows[("pre", mode)].append(t_pre)
            rows[("post", mode)].append(t_post)
            if mode == "seq":
                for c, t in zip(pre, per):
                    hook_times.setdefault((label, "pre", c), []).append(t)
                for c, t in zip(post, per2):
                    hook_times.setdefault((label, "post", c), []).append(t)
    med = {k: statistics.median(v) for k, v in rows.items()}
    results.append((label, len(pre), len(post), med))

if not fixture and os.path.exists(write_target):
    os.remove(write_target)

where = "fixture" if fixture else root
print(f"Hook latency per tool call — {where}, median of {runs} runs, ms")
print(f"{'event':<24}{'pre#':>5}{'pre seq':>9}{'pre par':>9}{'post#':>6}{'post seq':>10}{'post par':>10}{'total seq':>11}{'total par':>11}")
for label, npre, npost, m in results:
    ts = m[("pre", "seq")] + m[("post", "seq")]
    tp = m[("pre", "par")] + m[("post", "par")]
    print(f"{label:<24}{npre:>5}{m[('pre','seq')]:>9.0f}{m[('pre','par')]:>9.0f}{npost:>6}{m[('post','seq')]:>10.0f}{m[('post','par')]:>10.0f}{ts:>11.0f}{tp:>11.0f}")

if per_hook:
    print()
    print("Per hook (sequential run), median ms")
    for (label, phase, cmd), ts in hook_times.items():
        name = re.search(r"scripts/([\w.-]+)", cmd)
        name = name.group(1) if name else "inline: " + cmd[:48].replace("\n", " ")
        print(f"  {label:<24}{phase:<5}{statistics.median(ts):>7.0f}  {name}")

if fixture:
    shutil.rmtree(root, ignore_errors=True)
PY
