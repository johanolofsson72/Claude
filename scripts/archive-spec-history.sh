#!/bin/bash
# archive-spec-history.sh — one-shot (repeatable) context-cost cleanup.
#
# WHY: specs/INDEX.md and specs/SCENARIOS.md each carry a "## ... history"
# section that grows one entry per spec and gets RE-READ in full on every
# subsequent spec. On a 60+ spec project that history balloons to tens of
# thousands of tokens that buy nothing — the live rows/ledger are what the
# pipeline actually needs. This script moves the OLD history entries out to a
# sibling ".history.md" archive (never read per-spec) and keeps only the N
# NEWEST entries inline (ordering auto-detected: works whether the register
# appends newest-at-bottom or prepends newest-at-top). The live spec rows /
# SC-id ledger are never touched.
#
# Safe by construction:
#   - The history region is everything BELOW the last "## ... history" heading,
#     and it admits ONLY two things: "- YYYY-MM-DD ..." entries (one line each,
#     per .claude/rules/spec-register.md and .claude/rules/scenarios.md) and
#     blank lines. Anything else is a ledger block that was appended in the wrong
#     place, and the script REFUSES the file rather than moving it (exit 3).
#     This guard is why the section header no longer claims the script "operates
#     only on the history section" — it used to say that, and it was false: the
#     split is positional, so four scenario ledger blocks appended below the
#     heading were swept as if they were history. Measured before the fix: 155
#     lines and 76 live "✓ validated" SC-ids relocated into the archive, and
#     NOTHING NOTICED. That silence is the K5 violation; row H5j.
#
#     This comment used to attribute the silence to validate-scenario-traceability.sh
#     "reporting 100% and exit 0 throughout, because it reads both files". No such
#     script existed — not here, not in the template, not anywhere in this repo's
#     history. The relocation was unwatched because there was no watcher, which is a
#     different and worse fact than a gate that failed to bite, and a reader had no
#     way to tell the two apart. Spec 007bs built the gate and corrected this line;
#     the coverage figure it reports is now a real measurement.
#   - Reversible — the repo is git-tracked; `git diff` shows exactly what moved,
#     `git checkout -- <file>` undoes it.
#   - Idempotent — re-running with the same KEEP just re-confirms; nothing is
#     lost or duplicated (archived entries are prepended once, newest-first).
#
# BYTE BUDGET (spec 007bt). KEEP controls how MANY entries stay inline and has
# never controlled how LARGE one may be, while both rules that govern this file
# say an entry is "- YYYY-MM-DD — <one sentence>", never a paragraph. Measured
# 2026-08-28 in specs/SCENARIOS.md: three of seven inline entries ran 2075, 2634
# and 2925 bytes — nine to twelve sentences each, 88% of the section's bytes —
# and passed every check this project had, because each was one line and a
# markdown bullet has no length limit. --max-bytes is that missing measurement.
#
#   The default of 300 is calibrated, not chosen: across all four history files
#   there are 48 entries that are genuinely one sentence, and their sizes run
#   p50 171, p90 236, p95 285. 300 is the smallest round number above p95, so it
#   admits 46 of the 48 that already comply and excludes every entry that does
#   not. 500 would admit all 124 and gate nothing; 250 would flag seven entries
#   that were written correctly.
#
#   Bytes rather than sentences because sentence-splitting over prose holding
#   "007bi:", file paths, "e.g." and "0.04 s" is a heuristic, and a gate whose
#   verdict rests on a heuristic is one people argue with instead of obeying.
#   The rule still says one sentence; this is the measurable floor under it.
#
# Exit codes:
#   0  success (or nothing to do)
#   1  no specs/ directory found
#   2  usage error (unknown arg, non-numeric --keep or --max-bytes)
#   3  REFUSED — a history region contained something that is not a history
#      entry. Nothing was written. Distinct from 1/2 so a test asserting the
#      refusal cannot pass because the script died of an unrelated fault.
#   4  OVER BUDGET — an entry that STAYS INLINE exceeds --max-bytes. The writes
#      still happened: refusing to archive because an entry is too long would
#      leave MORE bytes inline than completing the run does, which is the
#      opposite of this script's purpose. That is the deliberate difference from
#      3, where writing is what does the damage. 3 beats 4 when both apply — a
#      refused file wrote nothing and still holds non-history content, so its
#      budget figure describes a region the caller does not have.
#
# Usage:
#   scripts/archive-spec-history.sh                 # cleans ./specs/*, KEEP=5
#   scripts/archive-spec-history.sh --keep 8        # keep the 8 newest inline
#   scripts/archive-spec-history.sh --dir path/to/specs
#   scripts/archive-spec-history.sh --dry-run       # report only, write nothing
#   scripts/archive-spec-history.sh --max-bytes 400 # loosen the per-entry budget
#   scripts/archive-spec-history.sh --max-bytes 0   # disable the budget entirely
#
# Cross-platform: POSIX awk + bash. Runs under macOS, Linux, and Git Bash/WSL.

set -eu

KEEP=5
MAX_BYTES=300
SPECS_DIR=""
DRY_RUN=0
# Set to 1 by archive_history() when a file is refused. The function itself
# always returns 0 — `set -e` is live, so returning non-zero would kill the
# script at that call and a refused INDEX.md would stop SCENARIOS.md from ever
# being examined (silently breaking the "a clean sibling is still processed"
# guarantee). The refusal is reported per file and settled once, at the end.
REFUSED=0
# Set by archive_history() when a KEPT entry exceeds MAX_BYTES. Accumulated the same
# way and for the same reason as REFUSED: a fault in INDEX.md must not stop
# SCENARIOS.md from being examined. Settled once, at the end, where 3 beats 4.
OVER_BUDGET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP="${2:?--keep needs a number}"; shift 2 ;;
    --max-bytes) MAX_BYTES="${2:?--max-bytes needs a number}"; shift 2 ;;
    --dir) SPECS_DIR="${2:?--dir needs a path}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$KEEP" in ''|*[!0-9]*) echo "--keep must be a non-negative integer" >&2; exit 2 ;; esac
# Same shape as --keep's check, deliberately: a leading '-' lands in the [!0-9] class,
# so a negative budget is rejected here rather than silently flagging every entry.
case "$MAX_BYTES" in ''|*[!0-9]*) echo "--max-bytes must be a non-negative integer (0 disables the check)" >&2; exit 2 ;; esac

# Locate the specs dir: explicit --dir, else ./specs, else walk up to a repo root.
if [ -z "$SPECS_DIR" ]; then
  if [ -d "./specs" ]; then
    SPECS_DIR="./specs"
  else
    d="$PWD"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
      if [ -d "$d/specs" ]; then SPECS_DIR="$d/specs"; break; fi
      [ -d "$d/.git" ] && break
      d=$(dirname "$d")
    done
  fi
fi
[ -n "$SPECS_DIR" ] && [ -d "$SPECS_DIR" ] || { echo "no specs/ dir found (use --dir)" >&2; exit 1; }

# budget_report <live-basename> <keep-file> <line-base>
# Measures every entry that will remain INLINE and prints the ones over MAX_BYTES.
# Returns 1 when any entry is over budget, 0 otherwise. Prints nothing when clean —
# the check is invisible on a compliant file, exactly like the foreign-content guard.
#
# WHY THIS IS CHECKED HERE AND NOT WHERE THE OTHER GUARD IS. The foreign-content
# guard runs over the WHOLE region BEFORE the keep/move partition, so its verdict
# never depends on --keep; that is right for it, because content in the wrong place
# is wrong at any --keep, and a fault that appears at 5 and vanishes at 20 teaches
# people it is spurious. This guard is the opposite case and is checked over the KEPT
# set AFTER the partition, because it measures in-flight cost rather than an invariant
# of the file: an entry this run archives has stopped being read by the pipeline, and
# reporting it would make the gate red about bytes the run just removed. Do not
# "align" the two — the difference is the point.
#
# An entry is a top-level "- " bullet plus its following non-bullet lines, and its
# size is the SUM of those lines; newline separators are not counted, so the number
# matches `wc -c` on the quoted line.
#
# That summing is DEFENSIVE, not the defence. It was written to stop "press Enter to
# split the entry" from evading the budget, and then measured: the evasion is
# unreachable. The guard above admits only "- YYYY-MM-DD ..." lines and blank lines,
# so a continuation line is foreign content and the file is REFUSED with exit 3
# before this function is ever called. The summing stays because this must hold the
# same entry model as the partitioner it reads, and because it is correct if that
# guard is ever loosened — but do not describe it as what closes the hole. Exit 3
# closes the hole, and the harness asserts exit 3 for exactly that case.
#
# LC_ALL=C is load-bearing, not decorative. gawk under a UTF-8 locale returns
# CHARACTERS from length(); macOS awk returns bytes. History entries carry em dashes
# (2 bytes), "✓" (3 bytes) and backticked paths, so without the pin the same entry
# measures materially smaller on Linux and a developer there passes a budget a
# developer here fails. Same conclusion spec 007bs reached for status classification.
budget_report() {
  bname="$1"; keepfile="$2"; linebase="$3"
  # `if`, not `[ ... ] && return 0` — `set -e` is live and a trailing failed test in an
  # && list takes the function's exit status with it, which would report "over budget"
  # on every clean file the moment the budget is enabled.
  if [ "$MAX_BYTES" -eq 0 ]; then return 0; fi

  over=$(LC_ALL=C awk -v max="$MAX_BYTES" -v base="$linebase" '
    function dateof(s){ if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return substr(s, RSTART, RLENGTH); return "?" }
    /^- / { cur++; startln[cur]=NR; dt[cur]=dateof($0); by[cur]=length($0); next }
            { if (cur) by[cur] += length($0) }
    END{ for(i=1;i<=cur;i++) if (by[i] > max) printf "           line %-5d %s   %d bytes\n", base+startln[i], dt[i], by[i] }
  ' "$keepfile") || true

  [ -n "$over" ] || return 0

  n=$(printf '%s\n' "$over" | grep -c '^' )
  echo "  OVER BUDGET: $bname — $n entr$([ "$n" -eq 1 ] && echo y || echo ies) over the ${MAX_BYTES}-byte budget:"
  printf '%s\n' "$over"
  echo "         A history entry is '- YYYY-MM-DD — <one sentence>', never a paragraph"
  echo "         (.claude/rules/scenarios.md, .claude/rules/spec-register.md). Rewrite these to"
  echo "         one sentence — the detail belongs in the spec's own directory — or archive them."
  return 1
}

# archive_history <live-file> <archive-file> <history-heading-regex>
# <history-heading-regex> MUST be anchored to a markdown heading (^#+ ...) so a
# history ENTRY that merely mentions the words "register history" in its prose is
# not mistaken for the section heading (that would split the file at the wrong
# line). Splits the file at the LAST heading matching the regex.
# Keeps the KEEP newest top-level "- " bullets (with their continuation lines)
# inline — detecting whether newest is at the top or bottom from the first vs
# last entry's ISO date — and moves the older bullets to the archive.
archive_history() {
  live="$1"; archive="$2"; heading_re="$3"
  [ -f "$live" ] || { echo "  skip: $live (not found)"; return 0; }

  # Line number of the last heading that matches (history is the final section).
  hdr_line=$(awk -v re="$heading_re" 'tolower($0) ~ re {n=NR} END{print n+0}' "$live")
  if [ "$hdr_line" -eq 0 ]; then
    echo "  skip: $(basename "$live") — no history section (nothing to archive)"
    return 0
  fi

  # ---- GUARD -------------------------------------------------------------
  # The region below the heading admits ONLY dated history entries and blank
  # lines. Anything else (a heading, a table row, a mermaid fence, a horizontal
  # rule, an undated bullet) is ledger content sitting in the wrong place;
  # moving it would make proven scenarios invisible to the next spec.
  #
  # Checked over the WHOLE region and BEFORE the keep/move partition below, so
  # the verdict never depends on --keep. A guard evaluated after partitioning
  # would pass at --keep 20 and fail at --keep 5 on the same file, which teaches
  # people the fault is spurious.
  #
  # Anchored at line start, so a history entry whose prose quotes '#', '|' or a
  # date is admitted normally — the real entries do all three.
  foreign=$(awk -v h="$hdr_line" '
    NR<=h                                            { next }
    /^[[:space:]]*$/                                 { next }
    /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/  { next }
                                                     { printf "%d:%.120s", NR, $0; exit }
  ' "$live") || true

  if [ -n "$foreign" ]; then
    fl=${foreign%%:*}; ft=${foreign#*:}
    echo "  FAULT: $(basename "$live") — line $fl below '$(awk -v h="$hdr_line" 'NR==h' "$live")' is not a history entry:"
    echo "           $ft"
    echo "         That region admits ONLY '- YYYY-MM-DD ...' entries (one line each) and blank lines."
    echo "         Scenario/ledger blocks belong ABOVE the heading — everything below it is treated as"
    echo "         archivable history, and archived history is never read during the pipeline."
    echo "         Nothing was moved; $(basename "$live") is unchanged."
    REFUSED=1
    return 0
  fi
  # ---- end GUARD ---------------------------------------------------------

  tmp_body=$(mktemp); tmp_keep=$(mktemp); tmp_move=$(mktemp); tmp_meta=$(mktemp)
  trap 'rm -f "$tmp_body" "$tmp_keep" "$tmp_move" "$tmp_meta"' RETURN

  # Body = everything up to and including the history heading line.
  awk -v h="$hdr_line" 'NR<=h' "$live" > "$tmp_body"

  # History region = everything after the heading. Group into entries: an entry
  # starts at a top-level "- " bullet and includes following non-bullet lines.
  # Keep the KEEP NEWEST entries inline; archive the rest. Registers differ in
  # convention: some append newest-at-bottom (the template example), some prepend
  # newest-at-top (every real project checked). So detect ordering from the first
  # vs last entry's ISO date and keep whichever END holds the newest entries —
  # never blindly keep-last, or a newest-first register archives its RECENT
  # history and keeps ancient entries inline.
  # fmeta carries ONE number out of the partition: how many region lines sit ABOVE
  # the kept block. The budget report needs it to name a line the reader can open —
  # on a newest-first file the kept entries never move, so it is 0; on a
  # newest-at-bottom file they shift up by exactly the archived lines.
  awk -v h="$hdr_line" -v keep="$KEEP" -v fkeep="$tmp_keep" -v fmove="$tmp_move" -v fmeta="$tmp_meta" '
    function dateof(s){ if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return substr(s, RSTART, RLENGTH); return "" }
    NR<=h { next }
    { region[++n]=$0 }
    END{
      e=0
      for(i=1;i<=n;i++) if (region[i] ~ /^- /) starts[++e]=i
      if (e<=keep) { for(i=1;i<=n;i++) print region[i] > fkeep; print 0 > fmeta; exit }   # nothing to move
      fd = dateof(region[starts[1]]); ld = dateof(region[starts[e]])
      newestFirst = (fd != "" && ld != "" && fd > ld) ? 1 : 0
      if (newestFirst) {
        # newest at top → keep entries 1..keep, archive keep+1..e
        keepEnd = starts[keep+1] - 1
        for(i=1;i<=n;i++){ if (i<=keepEnd) print region[i] > fkeep; else print region[i] > fmove }
        print 0 > fmeta
      } else {
        # newest at bottom (or undated) → keep the last KEEP, archive 1..(e-keep)
        moveEnd = starts[e-keep+1] - 1
        for(i=1;i<=n;i++){ if (i<=moveEnd) print region[i] > fmove; else print region[i] > fkeep }
        print moveEnd > fmeta
      }
    }
  ' "$live"

  # grep -c prints "0" AND exits non-zero on no match; use `|| true` so we keep
  # that "0" without appending a second line (which would break the -eq test).
  moved=$(grep -cE '^- ' "$tmp_move" 2>/dev/null || true)
  moved=${moved:-0}

  keep_offset=$(cat "$tmp_meta" 2>/dev/null || echo 0)
  case "$keep_offset" in ''|*[!0-9]*) keep_offset=0 ;; esac

  # The line number this reports must be the one the caller finds when they open the
  # file AFTER this run — the report is useless otherwise. When we rewrite the file the
  # kept entries start immediately under the heading; when we do not (a dry run, or
  # nothing to move) they sit where they already were, keep_offset lines further down.
  if [ "$DRY_RUN" -eq 1 ] || [ "$moved" -eq 0 ]; then
    line_base=$((hdr_line + keep_offset))
  else
    line_base=$hdr_line
  fi

  if [ "$moved" -eq 0 ]; then
    echo "  ok:   $(basename "$live") — history ≤ keep=$KEEP, nothing to move"
    budget_report "$(basename "$live")" "$tmp_keep" "$line_base" || OVER_BUDGET=1
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  DRY:  $(basename "$live") — would archive $moved entr$([ "$moved" -eq 1 ] && echo y || echo ies) → $(basename "$archive"), keep newest $KEEP inline"
    budget_report "$(basename "$live")" "$tmp_keep" "$line_base" || OVER_BUDGET=1
    return 0
  fi

  # Prepend moved entries (older) to the archive, newest archived batch on top of
  # the older archive but below the archive header. Build fresh archive content.
  arch_tmp=$(mktemp)
  {
    echo "# $(basename "${live%.md}") — archived history"
    echo
    echo "Old history entries moved out of $(basename "$live") to keep per-spec context cheap."
    echo "This file is NOT read during the pipeline. Newest archived batch first."
    echo
    cat "$tmp_move"
    if [ -f "$archive" ]; then
      # Append the previous archive body (strip its header block: first 5 lines).
      echo
      awk 'NR>5' "$archive"
    fi
  } > "$arch_tmp"
  mv "$arch_tmp" "$archive"

  # Rebuild the live file: body (through heading) + kept entries.
  { cat "$tmp_body"; cat "$tmp_keep"; } > "$live.tmp" && mv "$live.tmp" "$live"
  echo "  ok:   $(basename "$live") — archived $moved entr$([ "$moved" -eq 1 ] && echo y || echo ies) → $(basename "$archive"), kept newest $KEEP inline"
  # AFTER the write, deliberately. Exit 4 reports a cost; it does not veto the cleanup.
  # Refusing to archive because a kept entry is too long would leave MORE bytes inline
  # than completing the run does — the opposite of what this script is for.
  budget_report "$(basename "$live")" "$tmp_keep" "$line_base" || OVER_BUDGET=1
}

echo "Archiving spec history in: $SPECS_DIR (keep newest $KEEP inline)$([ "$DRY_RUN" -eq 1 ] && echo '  [DRY RUN]')"
archive_history "$SPECS_DIR/INDEX.md"     "$SPECS_DIR/INDEX.history.md"     '^#+ .*register history'
archive_history "$SPECS_DIR/SCENARIOS.md" "$SPECS_DIR/SCENARIOS.history.md" '^#+ .*scenario history'

# 3 BEATS 4. A refused file wrote nothing and still holds content that is not history,
# so any budget figure computed for it describes a region the caller does not have. The
# refusal is the fact that has to be acted on first; re-run after fixing it to see the
# budget verdict for the real region.
if [ "$REFUSED" -ne 0 ]; then
  echo "REFUSED: at least one history region held content that is not a history entry. Nothing was"
  echo "moved for that file. Move the offending block ABOVE its history heading and re-run."
  exit 3
fi

if [ "$OVER_BUDGET" -ne 0 ]; then
  echo "OVER BUDGET: at least one entry that stays inline exceeds the ${MAX_BYTES}-byte budget."
  if [ "$DRY_RUN" -eq 1 ]; then
    # Say what actually happened. Claiming "archiving completed" after a dry run would be
    # the same class of untruth this spec exists to remove — a report about a run nobody made.
    echo "Nothing was written (dry run). The entries above are the ones that would stay inline."
  else
    echo "Archiving completed — this is a report about what is still there, not a refusal to write."
  fi
  echo "Rewrite the named entries to one sentence, or raise the budget with --max-bytes N."
  exit 4
fi

echo "Done. Review with 'git diff', undo with 'git checkout -- $SPECS_DIR'."
