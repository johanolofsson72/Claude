#!/bin/bash
# Every script that drives template-autosync.sh must NAME the project it drives (spec 010, landed from consultpilot H7bm).
#
# The defect this gate closes. template-autosync.sh resolves its target as
# `${CLAUDE_PROJECT_DIR:-$PWD}`. A caller that selects its target with `cd` alone has therefore not
# selected it at all: under a Claude Code hook the harness has already exported
# CLAUDE_PROJECT_DIR, pointing at the real repository, and it wins. On 2026-08-30
# test-template-autosync-stranded.sh did exactly that from the Stop hook and synced the real
# repository against a three-file sandbox template — 54 `chore(sync)` commits made and pushed to
# origin/main, and 505 lines deleted in the working tree, including 61 of the 62 lines of
# .claude/rules/continuous-execution.md.
#
# Two halves are required of every driver, and the second is why this file exists:
#
#   CLAUDE_PROJECT_DIR=…            names the target. Without it, `cd` is decoration.
#   CLAUDE_TEMPLATE_SYNC_SANDBOX=…  declares the only directory the run may write inside, which
#                                   the sync then enforces itself, whatever its root resolved to.
#
# The interlock protects a caller that declares. THIS gate is what makes callers declare. Neither
# alone closes the class: the first requires someone to remember, the second is what remembers —
# once something runs it. The template has no gate runner; a project's run-gates.sh lists it (row 014).
#
# WHAT IS EXEMPT, AND WHY IT IS A PROPERTY AND NOT A LIST
#
#   Query-mode callers. `--is-core`, `--list-core-scripts`, `--list-core-rules` and
#   `--template-dir` all return from template-autosync.sh ABOVE the project-root resolution — they
#   never resolve a root, so they cannot write to one, so there is nothing for a declaration to
#   constrain. A caller whose every invocation is one of them is therefore exempt by that property.
#   test-validate-sync-sandbox-declarations.sh asserts the property directly: move any of those
#   branches below the resolution and the assertion reddens and the exemption stops applying on its
#   own. A hard-coded list of filenames would be the grandfather list that is how
#   the next script gets written the old way and passes anyway.
#
#   Production callers. Four callers target the real repository deliberately — that IS their job.
#   They are excluded by an argued path|reason list below, because a
#   silent omission is the thing this row exists to prevent and an argued one a reviewer can
#   contest.
#
#   Scripts that name the file without executing it. A grep, a sed extraction, a comment. The
#   measured example is test-template-clone-refresh.sh: it `sed`-extracts refresh_local_template
#   and passes its target as an ARGUMENT, so it never resolves a project root — and that function
#   returns early unless the clone's origin is johanolofsson72/Claude. Recorded here rather than in
#   that file, so it stays byte-identical and the reason still has a reader. The first census of
#   this defect got that file wrong in one direction and missed test-core-owed-tick-guard.sh in the
#   other, both times by looking for a variable name instead of an invocation.
#
# Offline. Reads scripts as text and starts nothing — a gate proving the sync cannot escape its
# sandbox must not become the caller that does.
#
# Scenario ids deliberately absent: this file is CORE and ships into projects whose SC numbering
# is their own (row 012). Labels AC-NN match consultpilot H7bm spec.md for cross-reference.
#
# Exit: 0 = clean, 1 = violations found, 2 = cannot answer.
# Run: bash scripts/validate-sync-sandbox-declarations.sh [--quiet]

set -u

QUIET=0
for a in "$@"; do
  case "$a" in
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

ROOT="${SANDBOX_GATE_ROOT:-}"
if [ -z "$ROOT" ]; then
  ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || { echo "cannot resolve repo root" >&2; exit 2; }
fi
[ -d "$ROOT/scripts" ] || { echo "no scripts/ under $ROOT" >&2; exit 2; }

# path|reason — contestable by a reviewer, which is the point. Two distinct reasons here, and they
# were briefly conflated: the first draft excluded core-machinery-guard-hook.sh saying "--is-core
# only, which returns above the project-root resolution", which is NOT why it trips. Remove the
# entry and the gate reports a line of prose inside its refusal MESSAGE that quotes
# the fix command. A reason a reviewer would have believed and that was never true.
#
# REASON A — genuine production drivers of the real repository. They must NOT declare a sandbox
# (their target is the real repo, deliberately), so the gate's "both halves" rule cannot express
# them and a list is the honest mechanism.
#
# REASON B — files that QUOTE the sync command in their own help or refusal text. The detector
# already skips comment lines and requires command-word position; a command quoted inside a
# multi-line message string satisfies both and is not distinguishable by regex without parsing
# shell quoting. This is the detector's one known blind spot in the false-POSITIVE direction, and
# it is why the list carries REASON B entries at all. The cost is real and named: a file on this
# list that later gains a genuine root-resolving invocation stays silent. See the register row
# carved from this observation.
EXCLUDED="
scripts/template-autosync-hook.sh|REASON A — SessionStart hook, syncs the real repository on purpose, and already passes CLAUDE_PROJECT_DIR
scripts/lane-catchup.sh|REASON A — developer-run catch-up that previews a --dry-run sync of its own repository: it cds to the git toplevel and passes CLAUDE_PROJECT_DIR for it. Its --template-dir line also trips the handle heuristic, because the variable holding the template path is assigned on a line that tests for template-autosync.sh, so a later install-global-skills.sh call through that variable reads as an invocation
scripts/core-owed-tick-guard-hook.sh|REASON A — PreToolUse guard, must answer about the repository holding the edited file, and passes CLAUDE_PROJECT_DIR for it
scripts/core-machinery-guard-hook.sh|REASON B — its refusal message quotes the template-autosync.sh --force command as the fix. Its only real invocation is --is-core, which would be exempt by property anyway
scripts/template-autosync.sh|the script itself
scripts/validate-sync-sandbox-declarations.sh|REASON B — this gate prints example invocations in its own help text and executes nothing
scripts/test-validate-sync-sandbox-declarations.sh|this gate's harness — its fixtures are the violations, written on purpose
"

# Built once, matched with a builtin. The previous form piped the list through `while read | grep -q`
# per file — 172 execs and 344 forks for a membership test — and its `break` never short-circuited,
# because it ran in a pipeline subshell.
EXCLUDED_KEYS="|"
while IFS='|' read -r _p _r; do
  [ -n "$_p" ] || continue
  EXCLUDED_KEYS="$EXCLUDED_KEYS$_p|"
done <<EOF
$EXCLUDED
EOF

is_excluded() { case "$EXCLUDED_KEYS" in *"|$1|"*) return 0 ;; *) return 1 ;; esac; }

# Which variables in THIS file hold the sync? A first attempt matched $SYNC/$SCRIPT by name and
# reported 53 violations, nearly all of them scripts where $SCRIPT means some other script
# entirely — the exact "regex broad enough to match the wrong thing" the header warns about,
# walked into on the first try. So the handles are derived from the file's own assignments: a
# variable assigned a path ending in `-autosync.sh`. That covers $SYNC and $SCRIPT where they mean
# the sync, and the derived copies test-template-autosync-unlisted.sh builds ($ERA =
# era-autosync.sh, $SAB = sabotaged-autosync.sh), while $SCRIPT elsewhere is left alone.
#
# The bound, stated rather than hidden: a file that copies the sync to a name NOT ending in
# `-autosync.sh` and runs it through a variable is invisible here. Nothing does that today; if
# something starts, this is the line to extend.
sync_handles() {  # <file> -> a `|`-joined alternation of variable names, or empty
  sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=[^#]*-autosync\.sh.*/\1/p' "$1" 2>/dev/null \
    | sort -u | tr '\n' '|' | sed 's/|$//'
}

# An invocation line: executes the sync, by literal path or through one of this file's handles.
invocation_lines() {  # <file>
  _h=$(sync_handles "$1"); _h=${_h:-__no_handles__}
  # [$] and [.] rather than \$ and \. — inside a double-quoted shell string the backslash is eaten
  # and the regex ends up with a bare `$`, which ERE reads as end-of-line and which silently matched
  # nothing. Character classes say the same thing and survive one round of quoting.
  # The optional leading quote matters: `bash "$_p/scripts/template-autosync.sh"` has no space
  # between the interpreter and the path, so without it test-template-autosync-owed.sh — a real
  # driver — went unseen while the gate reported itself as one.
  _lit='"?[^[:space:]"]*template-autosync[.]sh'
  # The interpreter must start a word. Without `(^|[[:space:]]|[(])` the `sh` at the end of every
  # `*.sh` filename matched: a GATES-style array of script names and a string listing them both read
  # as invocations, and so did the line `echo "FAIL: template-autosync.sh not found at $SCRIPT"`.
  _cmd='(^|[[:space:]]|[(]|`)(bash|sh)[[:space:]]+'

  # ARM B, added after the adversarial review of this row found the first arm blind to two forms
  # that genuinely run the sync — neither reported as a driver, nor as exempt: simply silent.
  #
  #     ( cd /elsewhere && exec "$SYNC" --force )      # no bash/sh token at all
  #     OUT=`bash "$SYNC" --force`                     # backtick is not a word anchor
  #
  # template-autosync.sh carries a #! line, so executing the path directly runs it. This arm
  # therefore matches the handle or the literal path in COMMAND-WORD POSITION — after a line
  # start, `(`, a backtick, `&&`, `||`, `;`, `|`, or `exec` — which is what distinguishes
  # `exec "$SYNC"` from `[ -f "$SYNC" ]` and from `cp "$SYNC" "$T/"`, neither of which runs it.
  # `[(][[:space:]]` and not a bare `[(]`: the first draft of this arm matched
  # `echo "  (scripts/template-autosync.sh), is shared verbatim…"` — prose inside a string. A
  # subshell opens with `( cd …`, with a space; a parenthesised citation does not.
  _word='(^|[(][[:space:]]|`|&&|[|][|]|;|[|])[[:space:]]*'
  # And the target must be a HANDLE VARIABLE, or a literal path after `exec`. A bare literal at
  # line start is prose — `template-autosync.sh reads that marker to decide…` inside a multi-line
  # message string was the second false positive. Both were caught by running the arm against this
  # repository before trusting it.
  # `exec` belongs inside the target, not outside it as well — the two spellings overlapped and
  # split "how exec is handled" across two places.
  _tgt='((exec[[:space:]]+)?"?[$]{?('"$_h"')}?"?|exec[[:space:]]+'"$_lit"')'
  { grep -nE "$_cmd"'([^|;&]*[[:space:]])?("?[$]{?('"$_h"')}?"?|'"$_lit"')' "$1" 2>/dev/null
    grep -nE "$_word$_tgt"'([[:space:]]|$)' "$1" 2>/dev/null
  } | grep -vE '^[0-9]+:[[:space:]]*#' | sort -t: -k1,1n -u
}

VIOLATIONS=0
CHECKED=0
EXEMPT_QUERY=0

# Both arms require the literal `template-autosync.sh` or a variable assigned a path ending in
# `-autosync.sh`, so a file containing neither cannot match. One grep narrows the candidates to
# the few files that mention the sync; it is a sound superset, not a heuristic.
CANDIDATES=$(grep -l 'autosync' "$ROOT"/scripts/*.sh 2>/dev/null)

for f in $CANDIDATES; do
  rel="scripts/${f##*/}"
  is_excluded "$rel" && continue

  lines=$(invocation_lines "$f")
  [ -n "$lines" ] || continue

  # The query modes return above the project-root resolution, so such an invocation cannot write. Drop
  # those lines once; a file with nothing left never resolves a root and is exempt BY THAT PROPERTY,
  # not by name. One filter replaces a predicate function, a flag, and a second pass.
  lines=$(printf '%s\n' "$lines" | grep -vE -- '--(is-core|list-core-scripts|list-core-rules|template-dir)([[:space:]]|$|[)"])')
  if [ -z "$lines" ]; then
    EXEMPT_QUERY=$((EXEMPT_QUERY + 1))
    continue
  fi

  CHECKED=$((CHECKED + 1))
  file_bad=0
  while IFS= read -r ln; do
    num=${ln%%:*}
    text=${ln#*:}

    # The two halves may sit on the invocation line or on a continuation above it (a `\`-joined
    # env prefix), so look at the invocation line plus the two lines before it.
    from=$((num - 2)); [ "$from" -lt 1 ] && from=1
    ctx=$(sed -n "${from},${num}p" "$f")

    case "$ctx" in *CLAUDE_PROJECT_DIR=*) has_target=1 ;; *) has_target=0 ;; esac
    case "$ctx" in *CLAUDE_TEMPLATE_SYNC_SANDBOX=*) has_sandbox=1 ;; *) has_sandbox=0 ;; esac

    # Presence is not enough. `CLAUDE_TEMPLATE_SYNC_SANDBOX=/` satisfies every check above while
    # declaring the filesystem root, which constrains nothing — the interlock now refuses it, and
    # a gate that still called such a driver compliant would be the tool certifying the bypass.
    case "$ctx" in
      *CLAUDE_TEMPLATE_SYNC_SANDBOX=/[[:space:]]*|*CLAUDE_TEMPLATE_SYNC_SANDBOX=\"/\"[[:space:]]*|*CLAUDE_TEMPLATE_SYNC_SANDBOX=/)
        VIOLATIONS=$((VIOLATIONS + 1)); file_bad=1
        say "  $rel:$num — declares the filesystem root as its sandbox, which constrains nothing"
        continue ;;
    esac

    if [ "$has_target" -eq 0 ] || [ "$has_sandbox" -eq 0 ]; then
      VIOLATIONS=$((VIOLATIONS + 1)); file_bad=1
      miss=""
      [ "$has_target"  -eq 0 ] && miss="CLAUDE_PROJECT_DIR"
      [ "$has_sandbox" -eq 0 ] && miss="${miss:+$miss and }CLAUDE_TEMPLATE_SYNC_SANDBOX"
      say "  $rel:$num — drives the sync without $miss"
      say "      $(printf '%s' "$text" | sed 's/^[[:space:]]*//' | cut -c1-100)"
    fi
  done <<EOF
$lines
EOF
  [ "$file_bad" -eq 0 ] && say "  ok   $rel"
done

say ""
if [ "$VIOLATIONS" -gt 0 ]; then
  say "[sandbox-declarations] $VIOLATIONS violation(s) across $CHECKED driver(s); $EXEMPT_QUERY exempt (query modes only)"
  say ""
  say "  A driver must NAME its target project and DECLARE its sandbox:"
  say "      ( cd \"\$P\" && CLAUDE_PROJECT_DIR=\"\$P\" CLAUDE_TEMPLATE_SYNC_SANDBOX=\"\$TMP\" \\"
  say "          bash scripts/template-autosync.sh … )"
  say "  \`cd\` alone does not choose the target — template-autosync.sh reads"
  say "  \${CLAUDE_PROJECT_DIR:-\$PWD}, and under a hook that variable is already set to the"
  say "  real repository. Spec 010."
  exit 1
fi
say "[sandbox-declarations] $CHECKED driver(s) named and declared; $EXEMPT_QUERY exempt (query modes only)"
exit 0
