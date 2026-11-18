#!/bin/bash
# checkpoint-cadence.sh — how many feature specs since the last integration checkpoint?
#
# WHY THIS EXISTS. .claude/rules/spec-hardening.md asks for an integration-hardening checkpoint
# after every 5 completed specs. Two readers enforced it, and both computed `DONE % 5` over every
# ticked row. That counted the checkpoint rows themselves (H1, H2) and carved rows (016a, "carved
# by …") as feature specs: fundit was told "checkpoint due" at 20 done with four feature specs
# ticked since H2 (F211, spec 068). The modulo also failed the other way — at 21 done the alarm went
# quiet, so a checkpoint skipped at a multiple of 5 was never mentioned again.
#
# One engine, two readers (spec-register-orientation-hook.sh, project-maintenance.sh). Neither
# recomputes; two readers of one question that could answer differently is the silent disagreement
# maintenance-due.sh was written to prevent.
#
# WHAT COUNTS. A ticked row ticked after the newest checkpoint, that is not:
#   a checkpoint  id H<digit>…, or track field (field 3) "checkpoint"
#   a carve       id NNN<letters> (016a), or "carved by <id>" on the row
#   standing      track field "standing" / "stående" (the T0 pointer row)
# The track is read from field 3 only: a slug must not be able to decide what a row is (a project's SC-NNNN).
#
# "THE NEWEST CHECKPOINT" IS THE HIGHEST H NUMBER, NOT THE LAST ONE IN THE FILE (row 110, F217-F219).
# rocky keeps its register in milestone order: H16 at line 106, H13 at line 274. Reading file order
# answered "8 since H13, due" when 3 specs had been ticked since H16. And "after it" is the order the
# rows were TICKED, read from git: the first commit that wrote `- [x] <id> ` into specs/INDEX.md,
# by its place in `git log` (a rebase rewrites dates, not the order). A row ticked in the
# checkpoint's own commit does not count. Where git cannot answer (no repository, a row with no tick
# in its history) the row's place in the file decides, which is the old reading.
#
# Usage:
#   bash scripts/checkpoint-cadence.sh [--dir DIR]
# Output: one line  since=<checkpoint id|none> count=<N> due=<0|1>
# Exit:   0 due · 1 not due · 4 no register / unreadable / usage

set -uo pipefail
export LC_ALL=C

EVERY=5
DIR="."
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "checkpoint-cadence.sh: unknown argument '$1'" >&2; exit 4 ;;
  esac
done

REG="$DIR/specs/INDEX.md"
[ -r "$REG" ] || { echo "checkpoint-cadence.sh: no readable register at $REG" >&2; exit 4; }

# The tick order: "<id>\t<n>", n the position in history of the first commit that ticked the row.
# Empty outside a repository, and then every row falls back to file order.
TICKS=$(git -C "$DIR" log --reverse --format='tformat:@@commit' -p --unified=0 -- specs/INDEX.md 2>/dev/null |
  awk '/^@@commit$/ { n++; next }
       /^\+- \[x\] / { l = $0; sub(/^\+- \[x\] +/, "", l); split(l, f, / — /); id = f[1]
                        gsub(/[*[:space:]]/, "", id); if (id != "" && !(id in seen)) { seen[id] = n; print id "\t" n } }')

# Every `- [x]` line, like the DONE count it replaces: a heading test would read zero on a
# register whose heading is written in Swedish. History entries never start with a checkbox.
# LC_ALL=C: awk sees the em-dash as three bytes, which is all the " — " split needs.
OUT=$( { printf '%s\n' "$TICKS"; echo "@@register"; cat "$REG"; } | awk -v every="$EVERY" '
  /^@@register$/ { reg = 1; next }
  !reg { if ($0 != "") { split($0, t, "\t"); tick[t[1]] = t[2] + 0 } ; next }
  /^- \[x\] / {
    pos++
    line = $0
    sub(/^- \[x\] +/, "", line)
    n = split(line, f, / — /)
    id = f[1]; gsub(/[*[:space:]]/, "", id)
    track = (n >= 3) ? tolower(f[3]) : ""
    # region: skip-checkpoint
    if (id ~ /^H[0-9]/ || track ~ /checkpoint/) {
      # Rank: H number, then its letters, then file position. A checkpoint with no H number ranks
      # below every H row and by position among its own kind.
      num = -1; suf = ""
      if (match(id, /^H[0-9]+/)) { num = substr(id, 2, RLENGTH - 1) + 0; suf = substr(id, RLENGTH + 1) }
      if (since == "" || num > bnum || (num == bnum && suf >= bsuf)) { since = id; bnum = num; bsuf = suf; bpos = pos }
      next
    }
    # endregion
    if (track ~ /standing|st\303\245ende/) next
    # region: skip-carved
    if (id ~ /^[0-9]+[a-z]+$/ || tolower($0) ~ /carved by /) next
    # endregion
    nf++; fid[nf] = id; fpos[nf] = pos
  }
  END {
    count = 0
    for (i = 1; i <= nf; i++) {
      if (since == "") { count++; continue }
      # region: after-checkpoint
      if ((since in tick) && (fid[i] in tick)) { if (tick[fid[i]] > tick[since]) count++ }
      else if (fpos[i] > bpos) count++
      # endregion
    }
    if (since == "") since = "none"
    due = 0
    # region: due-at-least
    if (count >= every) due = 1
    # endregion
    printf "since=%s count=%d due=%d\n", since, count, due
  }') || { echo "checkpoint-cadence.sh: could not read $REG" >&2; exit 4; }

printf '%s\n' "$OUT"
case "$OUT" in *due=1) exit 0 ;; *) exit 1 ;; esac
