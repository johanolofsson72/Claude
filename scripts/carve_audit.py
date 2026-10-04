import os, re, sys, collections

reg = open(os.environ["REG"], encoding="utf-8", errors="replace").read()
budget = int(os.environ.get("BUDGET") or 2)

ROW = re.compile(r"^- \[([ xX/!])\] +\*{0,2}([^\s—*]+)", re.M)
rows, ticked = {}, 0
for line in reg.split("\n"):
    m = ROW.match(line)
    if m:
        rows[m.group(2)] = line
        ticked += m.group(1) in "xX"

# Below this many ticked rows, "no attribution" can honestly mean "nothing carved yet". The same
# floor carve-budget.md section 5 puts under the carve ratio, for the same reason.
MIN_TICKED = 10

# "carved by H7u", "Found by 091", "From H2" -- the id is the first token after the phrase.
ATTR = re.compile(r"(?:carved by|found by|opened by|from)\s+\**(?:spec\s+)?([A-Za-z]?[0-9][0-9A-Za-z.]*)", re.I)
parent, unresolved = {}, []
for rid, line in rows.items():
    m = ATTR.search(line)
    if not m:
        continue
    # A trailing period is sentence punctuation, not part of the id: "carved by 073." cited 073.
    pid = m.group(1).rstrip(".")
    if pid == rid:
        continue
    if pid in rows:
        parent[rid] = pid
    else:
        unresolved.append((rid, pid))

# Row 099 (ighweld F167): a decided excess is recorded by the developer as a header line,
#   Carve accepted: 064=3, 097=3 · 2026-10-03 · pre-measurement, all shipped
# The count binds the decision to what was decided: a fourth carve is over again. Budget only --
# section 3 has no depth exception. A line that starts like one but does not parse fails the audit,
# because ignoring it would look like a decision that was never recorded.
ACCEPT_ANY = re.compile(r"^\W*carve accepted\b", re.I)
ACCEPT = re.compile(r"^Carve accepted: (.+?) · (\d{4}-\d{2}-\d{2}) · \S.*$")
PAIR = re.compile(r"^([A-Za-z]?[0-9][0-9A-Za-z.]*)=([0-9]+)$")
accepted, malformed = {}, []
for no, line in enumerate(reg.split("\n"), 1):
    if not ACCEPT_ANY.match(line):
        continue
    m = ACCEPT.match(line)
    pairs = [PAIR.match(p.strip()) for p in m.group(1).split(",")] if m else [None]
    if not all(pairs):
        malformed.append((no, line))
        continue
    for p in pairs:
        accepted[p.group(1)] = (int(p.group(2)), m.group(2))

kids = collections.Counter(parent.values())
def allowed(pid):
    return max(budget, accepted[pid][0]) if pid in accepted else budget

over = sorted(((n, p) for p, n in kids.items() if n > allowed(p)), reverse=True)
waived = sorted((p, n) for p, n in kids.items() if budget < n <= allowed(p))

def depth(rid):
    seen, d = set(), 0
    while rid in parent and rid not in seen:
        seen.add(rid); rid = parent[rid]; d += 1
        if d > 50: break
    return d

deep = sorted(((depth(r), r) for r in rows if depth(r) > 2), reverse=True)

def chain(rid):
    out, seen = [rid], {rid}
    while rid in parent and parent[rid] not in seen:
        rid = parent[rid]; out.append(rid); seen.add(rid)
    return " -> ".join(reversed(out))

bad = 0
if over:
    bad += 1
    print(f"[CARVE BUDGET] {len(over)} row(s) carved more than {budget} (carve-budget.md section 2):")
    for n, pid in over[:10]:
        ks = sorted(k for k, v in parent.items() if v == pid)
        was = f" (accepted {accepted[pid][0]} on {accepted[pid][1]}, now {n})" if pid in accepted else ""
        print(f"  {pid} produced {n}{was}: {' '.join(ks[:12])}")
    print("  A decided excess is recorded with a header line in specs/INDEX.md:"
          " 'Carve accepted: <id>=<n> · <YYYY-MM-DD> · <why>'.")
if malformed:
    bad += 1
    print(f"[CARVE ACCEPTANCE] {len(malformed)} line(s) do not parse as"
          f" 'Carve accepted: <id>=<n>[, <id>=<n>] · <YYYY-MM-DD> · <why>':")
    for no, line in malformed[:10]:
        print(f"  line {no}: {line[:120]}")
for pid, n in waived:
    print(f"carve budget: {pid} produced {n}, accepted on {accepted[pid][1]} (Carve accepted line).")
if deep:
    bad += 1
    print(f"[CARVE DEPTH] {len(deep)} row(s) past depth 2 (section 3 — there is no depth 3):")
    for d, rid in deep[:10]:
        print(f"  {rid} is depth {d}:  {chain(rid)}")
if unresolved:
    print(f"[CARVE ATTRIBUTION] {len(unresolved)} row(s) name a parent this register does not hold:")
    for rid, pid in unresolved[:10]:
        print(f"  {rid} cites {pid}")
    print("  Reported, not dropped: a mis-parsed attribution and no attribution look the same otherwise.")
extra = f" ({len(unresolved)} unresolved attribution(s) above.)" if unresolved else ""
# With no resolved attribution, over and deep are empty by construction: "clean" would be a verdict
# on nothing. agentcrm read "clean -- 0 attributed" over a depth-3 chain (row 027). Exit 3 is not 1:
# project-maintenance.sh reads 1 as "the budget was exceeded", and that is not what we know.
if not parent and ticked >= MIN_TICKED:
    cite = f"; {len(unresolved)} cite a row this register does not hold" if unresolved else ""
    print(f"carve shape: unmeasurable — 0 attributed row(s) of {len(rows)} ({ticked} ticked){cite}. "
          f"Budget and depth cannot be computed from this register: write 'carved by <id>' on the rows "
          f"a spec carved (carve-budget.md section 4b).")
    sys.exit(3)
if not parent:
    print(f"carve shape: too young to measure — 0 attributed row(s), {ticked} ticked (under {MIN_TICKED}).{extra}")
elif not over and not deep:
    print(f"carve shape: clean — {len(parent)} attributed row(s), none over {budget} carves, none past depth 2.{extra}")
sys.exit(1 if bad else 0)
