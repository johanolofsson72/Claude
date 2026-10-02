#!/bin/bash
# The template's own mutation gate (spec 085). Stryker has no bash target, so this samples operator
# mutants from the template's critical bash scripts and runs each module's own self-tests against
# every mutant, in throwaway worktrees of a snapshot of the working tree.
#
#   bash scripts/run-mutation-gate.sh                       # 12 mutants per module, today's seed
#   bash scripts/run-mutation-gate.sh --module scripts/project-freshness.sh --sample 20
#   bash scripts/run-mutation-gate.sh --seed 20261001       # reproduce a run
#   bash scripts/run-mutation-gate.sh --lines scripts/template-autosync.sh:337,532
#   bash scripts/run-mutation-gate.sh --jobs 2
#
# Operators, one class each: arithmetic comparison (-eq/-ne, -lt/-ge, -gt/-le), string test
# (-z/-n right after `[`, `[[` or `test`), boolean (&& / ||), exit/return code (0 -> 1, n -> 0)
# and file-test negation (`[ -f X` -> `[ ! -f X`, also -d -e -s -x). Only shell code is mutated:
# comments, quoted text, awk/python programs in quotes and heredoc bodies are not. A line that
# carries `# mutant-equivalent: <reason>` is skipped, and the reason is the record.
#
# The sample is stratified round-robin across operator classes from a seeded RNG. The default seed
# is today's UTC date, so every day draws a fresh sample (F071: a fixed sample gets armed and the
# file does not). --lines measures every site on the named lines instead, to re-measure a survivor.
#
# A run: snapshot the working tree through a temporary index into a run-private object directory
# (untracked files that are not ignored included; the real index, HEAD and object store are never
# written), check it out into one independent repository per job under
# ${MUTATION_WORKDIR:-$HOME/.cache/claude-mutation} (under $HOME because test-drive-sync.sh judges
# its sandbox by location; an absolute path that is not $HOME and not near the repository), run
# every module's tests once unmutated, then the mutants. The copies share nothing with the real
# repository: no remote, no hooks, no .git link (security review, spec 085). Tests run without
# SSH_AUTH_SOCK, GH_TOKEN, GITHUB_TOKEN and the askpass helpers.
#
# A red or timed-out baseline is UNMEASURED: no score, exit 2, the test is named. Every test run is
# bounded by max(MUTATION_MIN_LIMIT=60, MUTATION_LIMIT_FACTOR=3 x its baseline seconds). A timeout
# is reported and is NOT a kill (.claude/rules/mutation-timeouts.md). A mutant is killed when one of
# its module's tests exits non-zero without timing out; the first kill skips the rest.
#
# Output contract (scripts/project-maintenance.sh section 5): one line per module, every survivor,
# then `mutation score N%`: killed / valid over all modules, timeouts counted as not killed. A
# Stryker schema-1 report goes to .claude/state/mutation/mutation-report.json, timeouts written as
# Survived so its per-file score is strict too. Progress goes to stderr.
#
# Exit: 0 score >= MUTATION_BREAK (default 80) · 1 below it · 2 nothing measured (bad argument,
# red baseline, missing git/python3/timeout, a module with no sites, a test that could not be
# started: an infrastructure failure is never counted as a kill).
# The settings in force (break, limits, table) are printed and written to the report.
#
# MUTATION_TARGETS=<file> replaces the target table: lines `<module> <test> [<test>...]`.
# Template-only: listed in TEMPLATE_ONLY_SCRIPTS in template-autosync.sh, never shipped.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

die() { echo "run-mutation-gate: $*" >&2; exit 2; }
is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

SAMPLE=12
SEED=$(date -u +%Y%m%d)
JOBS=4
MODULES=""
LINES_ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --module) [ $# -ge 2 ] || die "--module needs a path"; MODULES="$MODULES $2"; shift ;;
    --sample) [ $# -ge 2 ] && is_uint "$2" && [ "$2" -gt 0 ] || die "--sample needs a positive number"; SAMPLE=$2; shift ;;
    --seed)   [ $# -ge 2 ] && is_uint "$2" || die "--seed needs a number"; SEED=$2; shift ;;
    --jobs)   [ $# -ge 2 ] && is_uint "$2" && [ "$((10#$2))" -gt 0 ] && [ "$((10#$2))" -le 16 ] ||
                die "--jobs needs a number from 1 to 16"; JOBS=$((10#$2)); shift ;;
    --lines)  [ $# -ge 2 ] || die "--lines needs <module>:<line>[,<line>...]"
              case "$2" in *:*[0-9]*) ;; *) die "--lines needs <module>:<line>[,<line>...], got: $2" ;; esac
              LINES_ARGS="$LINES_ARGS $2"; MODULES="$MODULES ${2%%:*}"; shift ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

BREAK=${MUTATION_BREAK:-80}
MIN_LIMIT=${MUTATION_MIN_LIMIT:-60}
FACTOR=${MUTATION_LIMIT_FACTOR:-3}
BASE_LIMIT=${MUTATION_BASELINE_LIMIT:-1800}
for v in BREAK MIN_LIMIT FACTOR BASE_LIMIT; do eval "is_uint \"\$$v\"" || die "$v must be a whole number"; done
BREAK=$((10#$BREAK)); MIN_LIMIT=$((10#$MIN_LIMIT)); FACTOR=$((10#$FACTOR)); BASE_LIMIT=$((10#$BASE_LIMIT))

command -v git >/dev/null 2>&1 || die "needs git"
command -v python3 >/dev/null 2>&1 || die "needs python3"
TO=""
command -v timeout >/dev/null 2>&1 && TO=timeout
[ -z "$TO" ] && command -v gtimeout >/dev/null 2>&1 && TO=gtimeout
[ -n "$TO" ] || die "needs timeout or gtimeout; an unbounded mutant can run all night"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "not a git repository"
cd "$ROOT" || die "cannot enter $ROOT"

# read, not $(cat <<...): bash 3.2 scans a heredoc inside $( ) for quotes and the Python has odd ones.
IFS= read -r -d '' PY <<'PYEOF'
import json, os, random, re, sys

CLASSES = ["arith_compare", "string_test", "boolean", "exit_code", "file_test"]
ARITH = {"-eq": "-ne", "-ne": "-eq", "-lt": "-ge", "-ge": "-lt", "-gt": "-le", "-le": "-gt"}
HEREDOC = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")

def code_mask(lines):
    """Per line, a list of booleans: True where the character is shell code. Quoted text,
    comments and heredoc bodies are False. $( ) inside double quotes is code again."""
    masks, stack, pending, body = [], ["code"], [], None
    for line in lines:
        mask = [False] * len(line)
        if body is not None:
            strip_tabs, delim = body
            if (line.lstrip("\t") if strip_tabs else line) == delim:
                body = pending.pop(0) if pending else None
            masks.append(mask)
            continue
        i, n = 0, len(line)
        while i < n:
            top, c = stack[-1], line[i]
            if top == "sq":
                if c == "'":
                    stack.pop()
                i += 1
                continue
            if top == "dq":
                if c == "\\":
                    i += 2
                elif c == '"':
                    stack.pop(); i += 1
                elif line.startswith("$(", i):
                    stack.append(0); i += 2
                else:
                    i += 1
                continue
            # code: "code" at top level, or an int paren depth inside $( )
            mask[i] = True
            if c == "\\":
                if i + 1 < n:
                    mask[i + 1] = True
                i += 2
            elif c == "'":
                mask[i] = False; stack.append("sq"); i += 1
            elif c == '"':
                mask[i] = False; stack.append("dq"); i += 1
            elif c == "#" and (i == 0 or line[i - 1] in " \t;(") and not (i > 0 and line[i - 1] in "${"):
                for j in range(i, n):
                    mask[j] = False
                break
            elif line.startswith("$(", i):
                mask[i + 1] = True; stack.append(0); i += 2
            elif c == "(" and isinstance(top, int):
                stack[-1] = top + 1; i += 1
            elif c == ")" and isinstance(top, int):
                if top == 0:
                    stack.pop()
                else:
                    stack[-1] = top - 1
                i += 1
            elif line.startswith("<<<", i):
                i += 3
            elif line.startswith("<<", i):
                m = HEREDOC.match(line, i)
                if m:
                    pending.append((m.group(1) == "-", m.group(3)))
                    i = m.end()
                else:
                    i += 2
            else:
                i += 1
        if pending and stack[-1] not in ("sq", "dq"):
            body = pending.pop(0)
        masks.append(mask)
    return masks

def candidates(line, mask):
    out = []
    def ok(a, b):
        return all(mask[a:b])
    for m in re.finditer(r"(?<=\s)(-eq|-ne|-lt|-ge|-gt|-le)(?=\s)", line):
        if ok(m.start(), m.end()):
            out.append(("arith_compare", m.start(1), m.group(1), ARITH[m.group(1)]))
    for m in re.finditer(r"(?:\[\[?|\btest)\s+(?:!\s+)?(-z|-n)(?=\s)", line):
        if ok(m.start(1), m.end(1)):
            out.append(("string_test", m.start(1), m.group(1), "-n" if m.group(1) == "-z" else "-z"))
    for m in re.finditer(r"(?<=\s)(&&|\|\|)(?=\s|$)", line):
        if ok(m.start(), m.end()):
            out.append(("boolean", m.start(1), m.group(1), "||" if m.group(1) == "&&" else "&&"))
    for m in re.finditer(r"\b(exit|return) +([0-9]+)(?=$|[ \t;})])", line):
        if ok(m.start(), m.end()):
            new = "1" if m.group(2) == "0" else "0"
            out.append(("exit_code", m.start(), m.group(0), m.group(1) + " " + new))
    for m in re.finditer(r"(?:\[\[?|\btest)\s+(-[fdesx])(?=\s)", line):
        if ok(m.start(1), m.end(1)):
            out.append(("file_test", m.start(1), m.group(1), "! " + m.group(1)))
    return out

def sites(module):
    text = open(module, encoding="utf-8", errors="surrogateescape", newline="").read()
    lines = text.split("\n")
    found = []
    for no, (line, mask) in enumerate(zip(lines, code_mask(lines)), 1):
        if "# mutant-equivalent:" in line:
            continue
        for cls, col, before, after in candidates(line, mask):
            found.append((no, col, cls, before, after))
    return found

def cmd_sites(args):
    # sites <out.tsv> <base dir> <seed> <sample> <index>:<module>[:<lines>] ...
    out, base, seed, sample, specs = args[0], args[1], int(args[2]), int(args[3]), args[4:]
    rows, notes = [], []
    for spec in specs:
        idx, module, *rest = spec.split(":")
        found = sites(os.path.join(base, module))
        if rest and rest[0]:
            wanted = set(int(x) for x in rest[0].split(","))
            picked = [s for s in found if s[0] in wanted]
            bare = sorted(wanted - set(s[0] for s in picked))
            if bare:
                print("run-mutation-gate: %s: no mutable site on line(s) %s" % (module, ",".join(map(str, bare))), file=sys.stderr)
                sys.exit(2)
        else:
            if not found:
                print("run-mutation-gate: %s: no mutable site at all; fix the target table" % module, file=sys.stderr)
                sys.exit(2)
            rng = random.Random("%d:%s" % (seed, module))
            by = {c: [s for s in found if s[2] == c] for c in CLASSES}
            for c in CLASSES:
                rng.shuffle(by[c])
            order = [c for c in CLASSES if by[c]]
            rng.shuffle(order)
            picked = []
            while len(picked) < sample and any(by[c] for c in order):
                for c in order:
                    if by[c] and len(picked) < sample:
                        picked.append(by[c].pop())
            picked.sort()
            if len(picked) < sample:
                notes.append("%s: %d requested, %d sites" % (module, sample, len(picked)))
        for no, col, cls, before, after in picked:
            rows.append((idx, module, no, col, cls, before, after))
    with open(out, "w", encoding="utf-8") as f:
        for i, r in enumerate(rows, 1):
            f.write("m%03d\t%s\t%s\t%d\t%d\t%s\t%s\t%s\n" % ((i,) + r))
    for n in notes:
        print("  note: " + n)

def cmd_apply(args):
    # apply <worktree> <module> <line> <col> <before> <after>
    wt, module, no, col, before, after = args[0], args[1], int(args[2]), int(args[3]), args[4], args[5]
    path = os.path.join(wt, module)
    real = os.path.realpath(path)
    if os.path.islink(path) or not real.startswith(os.path.realpath(wt) + os.sep):
        print("run-mutation-gate: %s resolves outside its worktree" % module, file=sys.stderr)
        sys.exit(3)
    text = open(path, encoding="utf-8", errors="surrogateescape", newline="").read()
    lines = text.split("\n")
    line = lines[no - 1]
    if line[col:col + len(before)] != before:
        print("run-mutation-gate: anchor moved at %s:%d" % (path, no), file=sys.stderr)
        sys.exit(3)
    lines[no - 1] = line[:col] + after + line[col + len(before):]
    tmp = path + ".mutant.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
        f.write("\n".join(lines))
    os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)

def cmd_report(args):
    # report <mutants.tsv> <verdict dir> <pristine dir> <json out> <break> <seed> <sample> <settings>
    tsv, vdir, pdir, jout, brk, seed, sample, settings = args
    brk = int(brk)
    mods, order = {}, []
    for raw in open(tsv, encoding="utf-8"):
        mid, idx, module, no, col, cls, before, after = raw.rstrip("\n").split("\t")
        try:
            status = open(os.path.join(vdir, mid), encoding="utf-8").read().strip() or "missing"
        except OSError:
            status = "missing"
        if module not in mods:
            mods[module] = []; order.append((idx, module))
        mods[module].append((mid, int(no), int(col), cls, before, after, status))
    missing = [m for ms in mods.values() for m in ms if m[6] not in ("killed", "survived", "timeout")]
    if missing:
        print("run-mutation-gate: %d mutant(s) have no verdict (%s); nothing scored" % (len(missing), missing[0][0]), file=sys.stderr)
        sys.exit(2)
    killed = valid = 0
    files = {}
    for idx, module in order:
        ms = mods[module]
        k = sum(1 for m in ms if m[6] == "killed")
        t = sum(1 for m in ms if m[6] == "timeout")
        killed += k; valid += len(ms)
        print("%s: %d/%d killed (%.1f%%)%s" % (module, k, len(ms), 100.0 * k / len(ms), ", %d timeout" % t if t else ""))
        for mid, no, col, cls, before, after, status in ms:
            if status != "killed":
                print("  %s %s:%d %s '%s' -> '%s'" % ("timeout" if status == "timeout" else "survived", module, no, cls, before, after))
        mutants = []
        for mid, no, col, cls, before, after, status in ms:
            entry = {"id": mid, "mutatorName": cls, "replacement": after,
                     "location": {"start": {"line": no, "column": col + 1}, "end": {"line": no, "column": col + 1 + len(before)}},
                     "status": "Killed" if status == "killed" else "Survived"}
            if status == "timeout":
                entry["statusReason"] = "timeout — not a kill (mutation-timeouts.md)"
            mutants.append(entry)
        try:
            source = open(os.path.join(pdir, idx), encoding="utf-8", errors="replace", newline="").read()
        except OSError:
            source = ""
        files[module] = {"language": "shell", "source": source, "mutants": mutants}
    score = 100.0 * killed / valid
    print("seed %s, %s per module; %d/%d killed" % (seed, sample, killed, valid))
    print("settings: " + settings)
    print("mutation score %.1f%%" % score)
    report = {"schemaVersion": "1", "thresholds": {"high": 80, "low": 60, "break": brk},
              "seed": seed, "sample": sample, "settings": settings, "files": files}
    os.makedirs(os.path.dirname(jout), exist_ok=True)
    tmp = jout + ".tmp.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1)
    os.replace(tmp, jout)
    sys.exit(0 if score >= brk else 1)

try:
    {"sites": cmd_sites, "apply": cmd_apply, "report": cmd_report}[sys.argv[1]](sys.argv[2:])
except SystemExit:
    raise
except Exception as e:  # a crash is unmeasured, never "below the break"
    print("run-mutation-gate: internal error: %r" % (e,), file=sys.stderr)
    sys.exit(2)
PYEOF
py() { python3 -c "$PY" "$@"; }

# ------------------------------------------------------------------ the target table
TARGETS_DEFAULT='scripts/template-autosync.sh scripts/test-drive-sync.sh scripts/test-template-autosync-arms.sh scripts/test-sync-count-honesty.sh scripts/test-core-owed-tick-guard.sh scripts/test-core-machinery-guard.sh scripts/test-template-autosync-owed.sh scripts/test-template-autosync-stranded.sh scripts/test-template-autosync-eol.sh scripts/test-template-autosync-unlisted.sh scripts/test-template-autosync-supply-chain.sh scripts/test-template-autosync-sandbox-writes.sh scripts/test-template-clone-refresh.sh
scripts/project-maintenance.sh scripts/test-project-maintenance.sh scripts/test-maintenance-trust.sh scripts/test-workload-placement.sh
scripts/project-freshness.sh scripts/test-project-freshness.sh
scripts/validate-scenario-traceability.sh scripts/test-validate-scenario-traceability.sh
scripts/settings-edit-guard-hook.sh scripts/test-settings-edit-guard.sh
scripts/guard-lib.sh scripts/test-guard-canonical-paths.sh scripts/test-guard-root-anchor.sh scripts/test-guard-lib.sh scripts/test-guard-fail-closed.sh
scripts/guard-precheck.sh scripts/test-guard-canonical-paths.sh
scripts/spec-interview-guard-hook.sh scripts/test-guard-canonical-paths.sh scripts/test-guard-root-anchor.sh scripts/test-guard-fail-closed.sh
scripts/destructive-command-guard-hook.sh scripts/test-destructive-command-guard.sh'
if [ -n "${MUTATION_TARGETS:-}" ]; then
  [ -f "$MUTATION_TARGETS" ] || die "MUTATION_TARGETS names no file: $MUTATION_TARGETS"
  TARGETS=$(grep -v '^[[:space:]]*#' "$MUTATION_TARGETS" | grep .)
else
  TARGETS=$TARGETS_DEFAULT
fi
# A table path is plain: relative, no `..`, no whitespace, colon or glob character. Symlinks are
# refused where it matters, in the checked-out copy (no_link below).
safe_path() { case "$1" in /*|*..*|''|*[!A-Za-z0-9._/-]*) return 1 ;; *) [ -f "$1" ] ;; esac; }
no_link() { # no_link <copy root> <path>: no component of the path is a symlink
  _p=$2
  while [ -n "$_p" ] && [ "$_p" != . ]; do
    [ -L "$1/$_p" ] && return 1
    case "$_p" in */*) _p=${_p%/*} ;; *) _p="" ;; esac
  done
  return 0
}
table_has() { printf '%s\n' "$TARGETS" | awk -v m="$1" '$1 == m { f = 1 } END { exit !f }'; }

if [ -z "$MODULES" ]; then
  MODULES=$(printf '%s\n' "$TARGETS" | awk '{ print $1 }')
fi
[ -n "$MODULES" ] || die "the target table is empty"
SEL=""
for m in $MODULES; do
  table_has "$m" || die "not in the target table: $m"
  case " $SEL " in *" $m "*) continue ;; esac
  SEL="$SEL $m"
done
for m in $SEL; do
  safe_path "$m" || die "module is not a relative path to a file in the repository: $m"
  [ -n "$(printf '%s\n' "$TARGETS" | awk -v m="$m" '$1 == m && NF > 1')" ] || die "no test listed for $m"
  for t in $(printf '%s\n' "$TARGETS" | awk -v m="$m" '$1 == m { for (i = 2; i <= NF; i++) print $i }'); do
    safe_path "$t" || die "test is not a relative path to a file in the repository: $t ($m)"
  done
done

# ------------------------------------------------------------------ run dir, cleanup
[ -n "${HOME:-}" ] || die "HOME is not set"
WORKDIR=${MUTATION_WORKDIR:-$HOME/.cache/claude-mutation}
case "$WORKDIR" in /*) ;; *) die "MUTATION_WORKDIR must be absolute: $WORKDIR" ;; esac
mkdir -p "$WORKDIR" || die "cannot create $WORKDIR"
WORKDIR=$(cd -P "$WORKDIR" && pwd) || die "cannot enter $WORKDIR"
HOME_P=$(cd -P "$HOME" 2>/dev/null && pwd)
case "$WORKDIR/" in # "$WORKDIR/" spells / as //
  //|"$HOME_P/"|"$ROOT"/*) die "MUTATION_WORKDIR may not be /, \$HOME or inside the repository: $WORKDIR" ;;
esac
case "$ROOT/" in "$WORKDIR"/*) die "MUTATION_WORKDIR may not contain the repository: $WORKDIR" ;; esac
# A run killed with SIGKILL leaves its dir. Collect only dirs this runner made (the marker) whose
# owner is gone; a live run of any age is left alone.
for d in "$WORKDIR"/run.??????; do
  [ -f "$d/.mutation-gate-run" ] || continue
  kill -0 "$(cat "$d/.mutation-gate-run" 2>/dev/null)" 2>/dev/null && continue
  rm -rf "$d"
done
WPIDS=""
kill_tree() { # children first, so `timeout` gets the TERM it forwards to its test
  for _c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$_c"; done
  kill -TERM "$1" 2>/dev/null
}
cleanup() {
  trap '' INT TERM HUP                 # a second signal must not cut the cleanup short
  for p in $WPIDS; do kill_tree "$p"; done
  [ -n "$WPIDS" ] && wait 2>/dev/null
  # Ours: no marker yet (the signal came right after mkdir), or our own pid in it.
  if [ -n "$RUN" ] && [ -d "$RUN" ] &&
     { [ ! -e "$RUN/.mutation-gate-run" ] || [ "$(cat "$RUN/.mutation-gate-run" 2>/dev/null)" = "$$" ]; }; then
    rm -rf "$RUN"
  fi
}
# The traps go in before the run dir exists and RUN is named before mkdir, so a signal at any
# instant after this leaves nothing behind (/tla GAP-2: mktemp's dir was invisible to cleanup
# until the assignment returned).
RUN=""
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
RUN="$WORKDIR/run.$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 6)"
case "$RUN" in *run.??????) ;; *) RUN=""; die "cannot name a run dir under $WORKDIR" ;; esac
mkdir "$RUN" 2>/dev/null || { RUN=""; die "cannot create a run dir under $WORKDIR"; }
echo "$$" > "$RUN/.mutation-gate-run"

# ------------------------------------------------------------------ snapshot + worktrees
export GIT_AUTHOR_NAME=mutation GIT_AUTHOR_EMAIL=mutation@localhost GIT_COMMITTER_NAME=mutation GIT_COMMITTER_EMAIL=mutation@localhost
# New blobs go to $RUN/objects (removed at exit); the real store is only read, as an alternate.
OBJ=$(cd -P "$(git rev-parse --git-common-dir)/objects" && pwd) || die "cannot find the object store"
mkdir -p "$RUN/objects"
w=0
while [ "$w" -lt "$JOBS" ]; do
  mkdir "$RUN/wt$w" || die "cannot create a copy under $RUN"
  w=$((w + 1))
done
(
  export GIT_INDEX_FILE="$RUN/index" GIT_OBJECT_DIRECTORY="$RUN/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$OBJ"
  git read-tree HEAD && git add -A -- . 2>/dev/null || exit 1
  w=0
  while [ "$w" -lt "$JOBS" ]; do
    git checkout-index -a --prefix="$RUN/wt$w/" || exit 1
    w=$((w + 1))
  done
) || die "could not snapshot the working tree"
rm -rf "$RUN/index" "$RUN/objects"
w=0
while [ "$w" -lt "$JOBS" ]; do
  # An independent repository: tests that read git state see one commit, no remote, no hooks.
  ( cd "$RUN/wt$w" && git init -q . && git -c core.hooksPath=/dev/null add -A . &&
      git -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm "mutation snapshot" ) >/dev/null 2>&1 ||
    die "could not prepare the copy $RUN/wt$w"
  w=$((w + 1))
done
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

# Module i gets $RUN/mod/i (its path), $RUN/pristine/i (its bytes), $RUN/tests/i (its tests).
mkdir -p "$RUN/mod" "$RUN/pristine" "$RUN/tests" "$RUN/base" "$RUN/v"
SPECS=""
i=0
for m in $SEL; do
  i=$((i + 1))
  printf '%s' "$m" > "$RUN/mod/$i"
  no_link "$RUN/wt0" "$m" || die "module is a symlink or under one: $m"
  for t in $(printf '%s\n' "$TARGETS" | awk -v m="$m" '$1 == m { for (j = 2; j <= NF; j++) print $j }'); do
    no_link "$RUN/wt0" "$t" || die "test is a symlink or under one: $t ($m)"
  done
  cp "$RUN/wt0/$m" "$RUN/pristine/$i"
  printf '%s\n' "$TARGETS" | awk -v m="$m" '$1 == m { for (j = 2; j <= NF; j++) print $j }' > "$RUN/tests/$i.list"
  LN=""
  for la in $LINES_ARGS; do [ "${la%%:*}" = "$m" ] && LN="${LN:+$LN,}${la#*:}"; done
  case "$LN" in *[!0-9,]*) die "--lines takes line numbers: $m:$LN" ;; esac
  # The sites are read from the snapshot, which is what the worktrees hold.
  SPECS="$SPECS $i:$m${LN:+:$LN}"
done

run_test() { # run_test <copy> <limit> <test> -> echoes "<rc> <seconds> <0 ran | 1 timed out | 2 infra>"
  # A copy or test that is gone, or a timeout that could not start its command (125/126), is an
  # infrastructure failure: it says nothing about the mutant, so it is neither a kill nor a survivor.
  [ -d "$1" ] && [ -f "$1/$3" ] || { echo "0 0 2"; return; }
  _s=$SECONDS
  ( cd "$1" && env -u CLAUDE_PROJECT_DIR -u SSH_AUTH_SOCK -u GH_TOKEN -u GITHUB_TOKEN -u GIT_ASKPASS -u SSH_ASKPASS \
      "$TO" -k 5 "$2" bash -- "$3" </dev/null >/dev/null 2>&1 )
  _rc=$?
  _e=$(( SECONDS - _s ))
  _to=0
  { [ "$_rc" -eq 124 ] || [ "$_rc" -eq 137 ]; } && [ "$_e" -ge "$2" ] && _to=1
  { [ "$_rc" -eq 125 ] || [ "$_rc" -eq 126 ]; } && _to=2
  echo "$_rc $_e $_to"
}

# ------------------------------------------------------------------ baseline
# Every (module, test) pair once, unmutated, spread over the workers.
: > "$RUN/base.tasks"
i=0
for m in $SEL; do
  i=$((i + 1))
  while read -r t; do printf '%s\t%s\n' "$i" "$t" >> "$RUN/base.tasks"; done < "$RUN/tests/$i.list"
done
echo "run-mutation-gate: baseline over $(grep -c . "$RUN/base.tasks") test run(s), $JOBS job(s)" >&2
base_worker() {
  _n=0
  while IFS="$(printf '\t')" read -r _i _t; do
    _n=$((_n + 1)); [ $(( (_n - 1) % JOBS )) -eq "$1" ] || continue
    printf '%s\t%s\t%s\n' "$_i" "$_t" "$(run_test "$RUN/wt$1" "$BASE_LIMIT" "$_t")" >> "$RUN/base/$1"
  done < "$RUN/base.tasks"
}
w=0; WPIDS=""
while [ "$w" -lt "$JOBS" ]; do base_worker "$w" & WPIDS="$WPIDS $!"; w=$((w + 1)); done
wait; WPIDS=""
RED=$(cat "$RUN"/base/* 2>/dev/null | awk -F'\t' '{ split($3, r, " "); if (r[1] != 0 || r[3] != 0) print }')
if [ -n "$RED" ]; then
  printf '%s\n' "$RED" | while IFS="$(printf '\t')" read -r _i _t _r; do
    set -- $_r
    if [ "$3" -eq 1 ]; then why="timed out after ${2}s"
    elif [ "$3" -eq 2 ]; then why="could not be started (exit $1)"
    else why="exit $1"; fi
    echo "run-mutation-gate: baseline red — $(cat "$RUN/mod/$_i"): $_t $why" >&2
  done
  echo "run-mutation-gate: UNMEASURED — a mutant measured against a red suite is not a measurement" >&2
  exit 2
fi
[ "$(cat "$RUN"/base/* | grep -c .)" -eq "$(grep -c . "$RUN/base.tasks")" ] || die "baseline lost a result; nothing scored"
# Per module: "<limit> <test>", fastest first.
for f in "$RUN"/tests/*.list; do
  i=$(basename "$f" .list)
  cat "$RUN"/base/* | awk -F'\t' -v i="$i" -v mn="$MIN_LIMIT" -v fa="$FACTOR" '
    $1 == i { split($3, r, " "); l = r[2] * fa; if (l < mn) l = mn; print r[2] "\t" l "\t" $2 }' |
    sort -n | cut -f2- > "$RUN/tests/$i"
done

# ------------------------------------------------------------------ mutants
py sites "$RUN/mutants.tsv" "$RUN/wt0" "$SEED" "$SAMPLE" $SPECS || exit 2
TOTAL=$(grep -c . "$RUN/mutants.tsv")
echo "run-mutation-gate: $TOTAL mutant(s), seed $SEED, $JOBS job(s)" >&2
mut_worker() {
  _w=$1; _n=0; _wt="$RUN/wt$1"
  while IFS="$(printf '\t')" read -r _id _i _m _no _col _cls _before _after; do
    _n=$((_n + 1)); [ $(( (_n - 1) % JOBS )) -eq "$_w" ] || continue
    if ! py apply "$_wt" "$_m" "$_no" "$_col" "$_before" "$_after"; then
      cp "$RUN/pristine/$_i" "$_wt/$_m"; continue      # no verdict: the report refuses to score
    fi
    _v=survived
    while IFS="$(printf '\t')" read -r _lim _t; do
      set -- $(run_test "$_wt" "$_lim" "$_t")
      if [ "$3" -eq 2 ]; then _v=infra; break
      elif [ "$3" -eq 1 ]; then _v=timeout
      elif [ "$1" -ne 0 ]; then _v=killed; break
      fi
    done < "$RUN/tests/$_i"
    cp "$RUN/pristine/$_i" "$_wt/$_m"
    [ "$_v" = infra ] || printf '%s\n' "$_v" > "$RUN/v/$_id"
    echo "[${_id#m}/$TOTAL] $_v $_m:$_no" >&2
  done < "$RUN/mutants.tsv"
}
w=0; WPIDS=""
while [ "$w" -lt "$JOBS" ]; do mut_worker "$w" & WPIDS="$WPIDS $!"; w=$((w + 1)); done
wait; WPIDS=""

SETTINGS="break $BREAK, limit max($MIN_LIMIT, $FACTOR x baseline s), table ${MUTATION_TARGETS:-default}"
py report "$RUN/mutants.tsv" "$RUN/v" "$RUN/pristine" "$ROOT/.claude/state/mutation/mutation-report.json" "$BREAK" "$SEED" "$SAMPLE" "$SETTINGS"
