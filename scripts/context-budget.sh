#!/usr/bin/env bash
# context-budget.sh — what every session loads before the first prompt (spec 081).
#
# Claude Code loads CLAUDE.md, .claude/CLAUDE.md, every .claude/rules/**/*.md whose frontmatter has
# no `paths:` key, and the files CLAUDE.md imports with a line starting `@`. In this template that
# was 68 KB (~17k tokens) on 2026-10-01, and nothing measured it, so it only grew. This prints each
# file largest first, the total and the cap.
#
#   bash scripts/context-budget.sh [--root DIR] [--max-bytes N]
#
# Exit 0 within the cap · 1 over it · 2 cannot measure (missing root, missing @-import, bad cap).
# A `rules … · CLAUDE.md …` line splits the total. In a synced project (.claude/.template-sync) the
# rules are the template's: a sync overwrites a local trim, so over the cap says what is left for the
# project's own files instead of "move rationale to docs" (row 099, ighweld F168).
# CLAUDE.local.md is shown on its own line and not counted: it is personal and never shipped.
# Bytes, not tokens: deterministic and tool-free; a token is roughly 4 bytes of English.

set -u

ROOT="."
CAP=40960
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --max-bytes) CAP="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "context-budget: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$CAP" in ''|*[!0-9]*) echo "context-budget: --max-bytes needs a number, got '$CAP'" >&2; exit 2 ;; esac
[ -d "$ROOT" ] || { echo "context-budget: no such directory: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)

size_of() { wc -c < "$1" | tr -d ' '; }

# A rule is scoped when a leading `---` frontmatter block holds a `paths:` key. A `paths:` line in
# the body is prose, and an empty list is still a deliberate opt-out of always-loading.
is_scoped() {
  awk 'NR == 1 { if ($0 != "---") exit 1; next }
       /^---[[:space:]]*$/ { exit 1 }
       /^paths:/ { found = 1; exit 0 }
       END { exit found ? 0 : 1 }' "$1"
}

LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT
STATUS=0

add() { printf '%s\t%s\n' "$(size_of "$1")" "${1#"$ROOT"/}" >> "$LIST"; }

for f in "$ROOT/CLAUDE.md" "$ROOT/.claude/CLAUDE.md"; do
  [ -f "$f" ] || continue
  add "$f"
  # @-imports: a line that starts with @ and a path. Followed one level, relative to the importer.
  while IFS= read -r line; do
    target="${line#@}"; target="${target%%[[:space:]]*}"
    [ -n "$target" ] || continue
    case "$target" in
      "~/"*) path="$HOME/${target#\~/}" ;;
      /*) path="$target" ;;
      *) path="$(dirname "$f")/$target" ;;
    esac
    if [ -f "$path" ]; then add "$path"
    else echo "context-budget: $f imports $target, which does not exist" >&2; STATUS=2; fi
  done < <(grep -E '^@[^[:space:]]' "$f" 2>/dev/null)
done

if [ -d "$ROOT/.claude/rules" ]; then
  while IFS= read -r -d '' f; do
    is_scoped "$f" || add "$f"
    grep -qE '^@[^[:space:]]' "$f" 2>/dev/null \
      && echo "context-budget: note: $f has an @-import line; imports are only followed from CLAUDE.md" >&2
  done < <(find "$ROOT/.claude/rules" -type f -name '*.md' -print0 2>/dev/null)
fi

TOTAL=0
RULES=0
while IFS="$(printf '\t')" read -r n name; do
  [ -n "$n" ] || continue
  TOTAL=$((TOTAL + n))
  case "$name" in .claude/rules/*) RULES=$((RULES + n)) ;; esac
done < "$LIST"

sort -t "$(printf '\t')" -k1,1nr -k2,2 "$LIST" | while IFS="$(printf '\t')" read -r n name; do
  printf '%8s  %s\n' "$n" "$name"
done
[ -f "$ROOT/CLAUDE.local.md" ] && printf '%8s  %s\n' "$(size_of "$ROOT/CLAUDE.local.md")" "CLAUDE.local.md (personal, not counted)"
printf 'rules %8s bytes · CLAUDE.md and imports %s bytes\n' "$RULES" "$((TOTAL - RULES))"
printf 'total %8s bytes (~%s tokens) · cap %s\n' "$TOTAL" "$((TOTAL / 4))" "$CAP"

[ "$STATUS" -ne 0 ] && exit "$STATUS"
if [ "$TOTAL" -gt "$CAP" ]; then
  if [ -f "$ROOT/.claude/.template-sync" ]; then
    # Only the CORE rules are the template's (row 110, F215). agentcrm carried 25922 bytes of its
    # own non-CORE rules, and this advice sent the whole overage upstream for a trim only the project
    # could make. The list comes from template-autosync.sh, never a copy; without it every rule is
    # treated as synced, which was the old reading.
    CORE_LIST=$(bash "$(dirname "$0")/template-autosync.sh" --list-core-rules 2>/dev/null)
    CORE=0; LOCAL_RULES=""
    while IFS="$(printf '\t')" read -r n name; do
      case "$name" in .claude/rules/*) ;; *) continue ;; esac
      if [ -z "$CORE_LIST" ] || grep -qxF "${name#.claude/rules/}" <<< "$CORE_LIST"; then CORE=$((CORE + n))
      else LOCAL_RULES="$LOCAL_RULES$n	$name
"; fi
    done < "$LIST"
    OVER=$((TOTAL - CAP)); LOCAL=$((RULES - CORE)); MD=$((TOTAL - RULES)); OWN=$((LOCAL + MD))
    room=$((CAP - CORE)); [ "$room" -lt 0 ] && room=0
    echo "over budget: $OVER bytes over. The $CORE bytes of CORE rules are synced from the template: a local"
    echo "trim is overwritten. This project owns $OWN bytes: local rules $LOCAL, CLAUDE.md and imports are $MD bytes,"
    echo "and $room fit beside the CORE rules."
    if [ "$LOCAL" -gt 0 ]; then
      printf 'largest local rules: %s\n' "$(printf '%s' "$LOCAL_RULES" | sort -t "$(printf '\t')" -k1,1nr \
        | awk -F'\t' 'NR <= 3 { printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')"
    fi
    if [ "$OWN" -ge "$OVER" ]; then
      echo "All $OVER are reachable here: trim the local rules or move rationale to .claude/docs/ and leave a pointer."
    else
      echo "Trimming everything local recovers $OWN; file the other $((OVER - OWN)) with the template."
    fi
  else
    echo "over budget: $((TOTAL - CAP)) bytes over. Move rationale to .claude/docs/ and leave a pointer (spec 081)."
  fi
  exit 1
fi
echo "within budget"
exit 0
