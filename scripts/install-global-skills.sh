#!/usr/bin/env bash
#
# install-global-skills.sh — put the template's project-wizard and project-update
# skills where Claude Code finds them in EVERY repo: ~/.claude/skills/<name>/.
#
# WHY THIS EXISTS. Those two skills are the only ones that must run in a repo that
# is not a template project yet — the wizard creates one, the updater repairs one —
# so they cannot live only in the project's own .claude/skills. Until spec 073 the
# global copies were refreshed by hand, or by .claude/skills/project-wizard/install.sh,
# which copies SKILL.md alone, prompts before overwriting (so it cannot run unattended),
# and knows nothing about project-update. A skill directory is more than its SKILL.md;
# a copy of one file is how three lineages of the wizard came to exist.
#
# What it does, per skill:
#   - copies every file of the template's skill directory into the global one;
#   - compares first (cmp), so a rerun changes nothing and says "unchanged";
#   - reports each skill as installed / updated / unchanged, and names the files;
#   - NEVER deletes a file that exists only in the global copy. It says so instead.
#     Global copies have diverged from the template before (a `templates/` dir the
#     template never shipped), and silently removing someone's local addition is
#     the kind of refresh nobody runs twice.
#
# Portable by construction: bash 3.2 (macOS), bash 5 (Linux), Git Bash on Windows.
# find/cmp/cp/mv only — no rsync (absent on Git Bash), no readlink -f, no sudo, ever:
# everything it writes is under the user's own config directory.
#
# Usage:
#   bash scripts/install-global-skills.sh           # install or refresh
#   bash scripts/install-global-skills.sh --check   # report only; exit 1 if any differ
#   bash scripts/install-global-skills.sh --quiet   # print only what changed
#
# The destination is $CLAUDE_CONFIG_DIR/skills when that is set (Claude Code honours
# it), else $HOME/.claude/skills.
#
# Exit: 0 done / in sync · 1 --check found a difference · 2 could not run

set -uo pipefail
export LC_ALL=C

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
TEMPLATE=$(cd "$SELF_DIR/.." && pwd -P)
SKILLS="project-wizard project-update"

CHECK=0; QUIET=0
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install-global-skills.sh: unknown argument '$a'" >&2; exit 2 ;;
  esac
done

if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  DEST_ROOT="$CLAUDE_CONFIG_DIR/skills"
elif [ -n "${HOME:-}" ]; then
  DEST_ROOT="$HOME/.claude/skills"
else
  echo "install-global-skills.sh: neither CLAUDE_CONFIG_DIR nor HOME is set" >&2; exit 2
fi

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

# Files that are platform litter, not skill content. Copying .DS_Store into
# everyone's config is noise; comparing it would make --check flap.
is_litter() {
  case "$1" in */.DS_Store|.DS_Store|*/Thumbs.db|Thumbs.db|*.swp|*~) return 0 ;; esac
  return 1
}

DIFFERS=0
for skill in $SKILLS; do
  src="$TEMPLATE/.claude/skills/$skill"
  dst="$DEST_ROOT/$skill"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "install-global-skills.sh: $src/SKILL.md is missing — is this the template repo?" >&2
    exit 2
  fi

  existed=0; [ -d "$dst" ] && existed=1
  changed=""; ncopy=0

  # `find | while read` rather than a for-loop over $(find): paths may contain
  # spaces. The loop runs in a subshell under bash 3.2, so it reports through
  # stdout (one "rel" per changed file) instead of setting variables.
  list=$(cd "$src" && find . -type f | sed 's|^\./||' | sort)
  changed=$(printf '%s\n' "$list" | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    is_litter "$rel" && continue
    cmp -s "$src/$rel" "$dst/$rel" 2>/dev/null || printf '%s\n' "$rel"
  done)

  # Files only in the global copy: reported, never removed (see header).
  extra=""
  if [ "$existed" -eq 1 ]; then
    extra=$(cd "$dst" && find . -type f | sed 's|^\./||' | sort | while IFS= read -r rel; do
      is_litter "$rel" && continue
      [ -f "$src/$rel" ] || printf '%s\n' "$rel"
    done)
  fi

  if [ -z "$changed" ]; then
    say "  $skill: unchanged ($dst)"
  elif [ "$CHECK" -eq 1 ]; then
    DIFFERS=1
    if [ "$existed" -eq 1 ]; then
      printf '  %s: differs from the template (%s)\n' "$skill" "$dst"
    else
      printf '  %s: not installed (%s)\n' "$skill" "$dst"
    fi
    printf '%s\n' "$changed" | sed 's/^/      /'
  else
    # Copy each changed file via a temp name + mv, so an interrupted run never
    # leaves a half-written SKILL.md that Claude Code would then load.
    fail=0
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      d=$(dirname "$dst/$rel")
      mkdir -p "$d" || { fail=1; break; }
      cp -p "$src/$rel" "$dst/$rel.install-tmp.$$" \
        && mv -f "$dst/$rel.install-tmp.$$" "$dst/$rel" \
        || { rm -f "$dst/$rel.install-tmp.$$"; fail=1; break; }
      ncopy=$((ncopy + 1))
    done <<EOF
$changed
EOF
    if [ "$fail" -ne 0 ]; then
      echo "install-global-skills.sh: could not write into $dst" >&2
      exit 2
    fi
    if [ "$existed" -eq 1 ]; then
      printf '  %s: updated — %d file(s) (%s)\n' "$skill" "$ncopy" "$dst"
    else
      printf '  %s: installed — %d file(s) (%s)\n' "$skill" "$ncopy" "$dst"
    fi
    [ "$QUIET" -eq 1 ] || printf '%s\n' "$changed" | sed 's/^/      /'
  fi

  if [ -n "$extra" ]; then
    printf '  %s: kept %s file(s) that exist only in the global copy — not from the template:\n' \
      "$skill" "$(printf '%s\n' "$extra" | grep -c .)"
    printf '%s\n' "$extra" | sed 's/^/      /'
  fi
done

if [ "$CHECK" -eq 1 ] && [ "$DIFFERS" -eq 1 ]; then
  echo "Run: bash \"$TEMPLATE/scripts/install-global-skills.sh\" to refresh them."
  exit 1
fi
exit 0
