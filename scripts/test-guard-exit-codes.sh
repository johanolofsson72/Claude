#!/usr/bin/env bash
# test-guard-exit-codes.sh — every PreToolUse guard exits 0 when it speaks (spec 083, R8, F029).
#
# The CLI reads a hook's stdout JSON only on exit 0. A guard that prints a perfect deny and exits 1
# has its deny thrown away — exit 1 is a "non-blocking error", which is an allow — and every guard
# test that read stdout alone stayed green over it. test-hook-channels §13 pinned that for one guard.
# This pins it for all of them, and for the ones added later: the list is read from
# .claude/settings.json, not written here.
#
# For every script-backed PreToolUse hook, a battery of payloads (empty, garbage, truncated, each tool
# shape, deny-shaped and allow-shaped) runs under three PATHs: full, no jq, neither jq nor python3.
# Every run must exit 0, and whatever it prints must be ONE JSON object whose hookSpecificOutput
# carries hookEventName "PreToolUse". A static arm adds that no guard script has an `exit <non-zero>`
# outside an embedded program. A sabotage arm proves both arms bite.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SELF_DIR/.." && pwd)
SETTINGS="$ROOT/.claude/settings.json"
BASH_BIN=$(command -v bash)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t exitc)
WORK=$(cd -P "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"
export TMPDIR="$WORK/tmp"; mkdir -p "$TMPDIR"

GUARDS=$(python3 - "$SETTINGS" <<'PY'
import json, re, sys
s = json.load(open(sys.argv[1]))
seen = []
for m in s["hooks"].get("PreToolUse", []):
    for h in m["hooks"]:
        for name in re.findall(r"scripts/([A-Za-z0-9._-]+\.sh)", h.get("command", "")):
            if name not in seen:
                seen.append(name)
print("\n".join(seen))
PY
)
COUNT=$(printf '%s\n' "$GUARDS" | grep -c .)
[ "$COUNT" -ge 10 ] && ok "$COUNT script-backed PreToolUse guards read from settings.json" || bad "only $COUNT guards found in settings.json"

path_without() {
  local dir="$WORK/path-$1"; shift
  mkdir -p "$dir"
  local d f n h skip IFS=:
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      n=${f##*/}; [ -e "$dir/$n" ] && continue; [ -x "$f" ] || continue
      skip=0; for h in "$@"; do case "$n" in "$h"|"$h".*) skip=1 ;; esac; done
      [ "$skip" -eq 1 ] || ln -s "$f" "$dir/$n" 2>/dev/null
    done
  done
  printf '%s' "$dir"
}
NOJQ=$(path_without nojq jq)
NONE=$(path_without none jq python3)

# A code project with a register whose active spec has no artifacts, so the pipeline guards have
# something to deny.
P="$WORK/proj"; mkdir -p "$P/src" "$P/scripts" "$P/specs/001-x" "$P/.claude"
git init -q "$P"; echo '{}' > "$P/package.json"
printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$P/specs/INDEX.md"

j() { python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])))' "$1"; }
PAYLOADS=(
  ''
  'not json'
  '[1,2]'
  '{}'
  '{"tool_name":"Edit","tool_input":{"file_path":"'"$P"'/src/App.cs"'
  "$(j '{"tool_name":"Edit","tool_input":{"file_path":"'"$P"'/src/App.cs","old_string":"a","new_string":"b"}}')"
  "$(j '{"tool_name":"Write","tool_input":{"file_path":"'"$P"'/src/scripts/app.js","content":"x"}}')"
  "$(j '{"tool_name":"Edit","tool_input":{"file_path":"'"$P"'/specs/INDEX.md","old_string":"[/] 001","new_string":"[x] 001"}}')"
  "$(j '{"tool_name":"Read","tool_input":{"file_path":"/home/u/.ssh/id_rsa"}}')"
  "$(j '{"tool_name":"Bash","cwd":"'"$P"'","tool_input":{"command":"rm -r -f build"}}')"
  "$(j '{"tool_name":"Bash","cwd":"'"$P"'","tool_input":{"command":"sed -i s/a/b/ src/App.cs"}}')"
  "$(j '{"tool_name":"Bash","cwd":"'"$P"'","tool_input":{"command":"ls -la"}}')"
  "$(j '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"/home/u/.aws"}}')"
)

# judge <label> <out> <rc>: exit 0, and nothing or one PreToolUse JSON object.
judge() {
  local label="$1" out="$2" rc="$3"
  if [ "$rc" -ne 0 ]; then bad "$label: exit $rc (the CLI ignores stdout on a non-zero exit)"; return; fi
  case "$out" in *[![:space:]]*) ;; *) return 0 ;; esac
  if printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
assert isinstance(d, dict)
h = d["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse"
assert ("permissionDecision" in h) or ("additionalContext" in h)
' 2>/dev/null; then :; else bad "$label: output is not one PreToolUse JSON object"; info "${out:0:200}"; fi
}

printf '\n[R8] every guard × every payload × three PATHs: exit 0, well-formed output\n'
DENIES=0
while IFS= read -r g; do
  [ -n "$g" ] || continue
  [ -f "$SELF_DIR/$g" ] || { bad "$g is wired but missing"; continue; }
  before=$FAIL
  for tier in full nojq none; do
    case "$tier" in full) p="$PATH" ;; nojq) p="$NOJQ" ;; none) p="$NONE" ;; esac
    for pl in "${PAYLOADS[@]}"; do
      OUT=$(printf '%s' "$pl" | CLAUDE_PROJECT_DIR="$P" PATH="$p" "$BASH_BIN" "$SELF_DIR/$g" 2>/dev/null); RC=$?
      judge "$g [$tier] ${pl:0:60}" "$OUT" "$RC"
      case "$OUT" in *'"deny"'*) DENIES=$((DENIES + 1)) ;; esac
    done
  done
  [ "$FAIL" -eq "$before" ] && ok "$g: ${#PAYLOADS[@]} payloads × 3 PATHs"
done <<EOF
$GUARDS
EOF
[ "$DENIES" -ge 20 ] && ok "the battery reached a deny $DENIES times (the arms above judged real verdicts)" \
  || bad "the battery reached a deny only $DENIES times — it is not exercising the guards"

printf '\n[R8] static: no guard exits non-zero outside an embedded program\n'
while IFS= read -r g; do
  [ -n "$g" ] || continue
  HITS=$(python3 - "$SELF_DIR/$g" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
inside = None
out = []
for n, line in enumerate(lines, 1):
    if inside:
        if line.strip() == inside:
            inside = None
        continue
    m = re.search(r"<<-?\s*'?\"?([A-Za-z_]+)'?\"?", line)
    if m and not line.lstrip().startswith("#"):
        inside = m.group(1)
    code = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
    if re.search(r"\bexit\s+([1-9][0-9]*)\b", code):
        out.append(f"{n}: {line.strip()}")
print("\n".join(out))
PY
)
  [ -z "$HITS" ] && ok "$g: every exit is 0" || { bad "$g exits non-zero"; info "$HITS"; }
done <<EOF
$GUARDS
EOF

printf '\n[sabotage] a guard that denies and exits 1 is caught by both arms\n'
SAB="$WORK/sab"; mkdir -p "$SAB"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$SAB/" 2>/dev/null
python3 - "$SAB/sensitive-file-guard-hook.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
i = t.rindex("exit 0")
open(p, "w").write(t[:i] + "exit 1" + t[i + len("exit 0"):])
PY
# Truncated on purpose: the swapped exit is the last one, on the cannot-read path.
OUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"/x/.ssh/a"' | "$BASH_BIN" "$SAB/sensitive-file-guard-hook.sh" 2>/dev/null); RC=$?
before=$FAIL
judge "sabotage" "$OUT" "$RC" >/dev/null
if [ "$FAIL" -gt "$before" ]; then FAIL=$before; ok "the dynamic arm rejects a deny on exit $RC"
else bad "the dynamic arm accepted a deny on exit $RC"; fi
HITS=$(grep -nE '^[^#]*\bexit 1\b' "$SAB/sensitive-file-guard-hook.sh")
[ -n "$HITS" ] && ok "the static arm sees the exit 1" || bad "the static arm missed the exit 1"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
