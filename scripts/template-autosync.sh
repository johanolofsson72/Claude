#!/bin/bash
# Deterministic template → project sync. No LLM, no judgment calls.
#
# Copies the mechanical half of what /project-update does — scripts/, rules/,
# docs/, agents/, and core-hook wiring — from the template repo into THIS
# project, then commits. The half that needs judgment (CLAUDE.md prose merges,
# settings.json project-specific hooks, tech-stack decisions) is never touched;
# it is reported so a human can run /project-update deliberately.
#
# Safety model — the manifest:
#   Every sync records `<sha256>  <relpath>` for each file it wrote into
#   .claude/.template-sync. On the next run a project file is only overwritten
#   when its current hash still matches the manifest (i.e. nobody edited it
#   locally since the last sync). A locally-modified file is SKIPPED and
#   reported, never clobbered. Files in the CORE set (enforcement machinery,
#   not prose) are overwritten even without a manifest entry — that is the
#   spine that must not drift.
#
# Intentional differences — the record (.claude/.sync-local, spec 007af):
#   Some project files are SUPPOSED to differ from the template forever, and
#   reporting those on every run is a permanent false alarm — the one line in
#   this output a reader learns to skip, on which the next genuinely-stale file
#   will be reported. `.claude/.sync-local` holds one line per accepted
#   difference:
#
#       <project-sha256>  <template-sha256>  <relpath>
#
#   Both hashes, not one. A record keyed on the project's bytes alone goes
#   silent and then STAYS silent when the template rewrites that file, which is
#   the same defect pointed upstream. So: neither side moved → silent; either
#   side moved → reported, naming which one. That is what stops the record from
#   becoming a blindfold.
#
#   Only `--accept-local` ever writes it. A sync that recorded its own skips
#   would be a rubber stamp, and the failure that causes — a genuinely stale
#   file going quiet — is invisible.
#
# Retraction — the third verb (spec 007aw):
#   This sync adds and updates. It never removes, which is a deliberate choice,
#   but until 007aw it also never SAID so: the manifest is rebuilt from what the
#   copy loop saw, so a path the template stopped shipping fell out of it in
#   silence, on the one run where the fact was still observable. So the loop now
#   records what it VISITED, and a path in the previous manifest that it never
#   visited — and that is still on disk — is an ORPHAN. Orphans are carried
#   forward in the stamp as
#
#       # orphan <first-seen-date> <relpath>
#
#   and re-reported until the file is gone, at which point the line drops itself.
#   VISITED and not a manifest diff, because that diff measured 33% precision on
#   this project's history; VISITED and not the template's filesystem, because
#   007aq's build-output filter skips paths that are still sitting on it.
#
#   Reports, never deletes. Deleting is a large power for a script that runs
#   unattended at SessionStart, commits and pushes.
#
# Usage:
#   template-autosync.sh [--check] [--dry-run] [--force] [--no-commit] [--quiet]
#   template-autosync.sh --accept-local <path>...
#   template-autosync.sh --is-core <project-relative-path>
#     --check         report drift and exit 0 without writing anything
#     --dry-run       same as --check but also prints the file list it would write
#     --force         sync even when the template SHA matches the stamp
#     --no-commit     write files but leave them unstaged
#     --ignore-in-progress
#                     sync even while a rebase, merge or cherry-pick is in
#                     progress. Without it such a run DEFERS: it writes nothing
#                     at all — no file, no manifest, no stamp — says so, and
#                     leaves the work for the next session start (spec 007be).
#     --quiet         only print the one-line summary
#     --accept-local  record <path> as an intentional local difference and exit.
#                     Writes nothing else: no sync, no commit, no push. Refuses a
#                     path that is missing, is not shipped by the template, is
#                     identical to it, or is in the CORE set (which this sync
#                     overwrites unconditionally, so silence there is a promise
#                     it would break on its very next run).
#     --is-core       ask whether <path> is CORE machinery and exit immediately.
#                     0 = yes (the refusal text is written to stdout), 1 = no,
#                     2 = cannot answer. Writes nothing, resolves no template and
#                     makes no network call, so a PreToolUse hook can afford it
#                     before every edit.
#
# Exit codes: 0 = up to date / synced / not applicable, 1 = hard error.
# Fails open by design: this runs from a SessionStart hook and must never
# block a session from starting.

set -u

TEMPLATE_REPO_URL="https://github.com/johanolofsson72/Claude.git"
TEMPLATE_TARBALL="https://codeload.github.com/johanolofsson72/Claude/tar.gz/refs/heads/main"

MODE_CHECK=0; MODE_DRYRUN=0; FORCE=0; DO_COMMIT=1; QUIET=0; MODE_ACCEPT=0; ACCEPT_PATHS=""
MODE_IS_CORE=0; IS_CORE_PATH=""
# Spec 007be. IGNORE_IN_PROGRESS is the escape hatch out of the deferral gate below; DEFERRED is
# what the gate sets and the report block reads. Both are declared here rather than beside the gate
# because `set -u` is on and the report block runs on --check and --dry-run too, which never reach
# the gate at all.
IGNORE_IN_PROGRESS=0; DEFERRED=0; IN_PROGRESS_OP=""
ORIG_ARGS="$*"   # kept for the self-update re-exec below (flags contain no spaces)
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE_CHECK=1 ;;
    --dry-run)   MODE_CHECK=1; MODE_DRYRUN=1 ;;
    --force)     FORCE=1 ;;
    --no-commit) DO_COMMIT=0 ;;
    --ignore-in-progress) IGNORE_IN_PROGRESS=1 ;;
    --quiet)     QUIET=1 ;;
    --accept-local)
      MODE_ACCEPT=1
      # Everything after the flag is a path, so a caller can accept several at once. The loop stops
      # at the next flag rather than swallowing it, which keeps `--accept-local x --quiet` honest.
      while [ $# -gt 1 ]; do
        case "$2" in --*) break ;; esac
        ACCEPT_PATHS="$ACCEPT_PATHS $2"
        shift
      done
      ;;
    --is-core)
      MODE_IS_CORE=1
      # One path, and only if it is not the next flag — so `--is-core --quiet` is a
      # missing argument (exit 2) rather than a silent "not CORE".
      if [ $# -gt 1 ]; then case "$2" in --*) ;; *) IS_CORE_PATH="$2"; shift ;; esac; fi
      ;;
    -h|--help)   grep -E '^#( |$)' "$0" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

# Recording a difference needs the template's actual bytes, so "already at this SHA"
# must not short-circuit the resolution. Nothing is synced either way — the accept
# path exits before the copy loop.
[ "$MODE_ACCEPT" -eq 1 ] && FORCE=1

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
# The final summary is the machine-readable result — the SessionStart wrapper
# greps it for "[synced]". --quiet suppresses chatter, never this.
tell() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# ------------------------------------------------------------------- CORE sets
# Enforcement machinery: always overwritten, manifest or not. These are the
# files whose drift silently disables a gate — exactly what bit cv.
CORE_SCRIPTS="pipeline-trigger-match.sh pipeline-trigger-match.py emit-pipeline-reminder.sh
emit-clarify-reminder.sh emit-analyze-reminder.sh feature-pipeline-detect.sh
spec_active.py resolve-active-spec.sh test-active-spec-resolution.sh
spec-register-guard-hook.sh spec-register-orientation-hook.sh pipeline-state-guard-hook.sh
spec-interview-guard-hook.sh spec-md-coverage-reminder-hook.sh scenario-map-reminder-hook.sh
sync-feature-json-hook.sh
scenario-map-orientation-hook.sh continuous-execution-hook.sh stop-validation-hook.sh
repeat-failure-guard-hook.sh spec-run-log-hook.sh stack-marker-canary-hook.sh
detect-stack.sh detect-verify-command.sh test-detect-verify-command.sh
prune-dangling-hooks.py prune-agent-worktrees.sh
speckit-extension-policy.sh
archive-spec-history.sh test-archive-spec-history.sh skill-audit.sh test-pipeline-hooks.sh tlc-cleanup.sh
test-template-clone-refresh.sh test-sync-count-honesty.sh
core-machinery-guard-hook.sh test-core-machinery-guard.sh
project-maintenance.sh project-freshness.sh
sync-core-hooks.py sync-local-llm-hooks.py sync-graphify-wiring.py fix-hook-paths.py
template-autosync.sh template-autosync-hook.sh
template-sync-verify.sh template-sync-verify-hook.sh"

CORE_RULES="feature-pipeline.md continuous-execution.md validation-followup.md
spec-register.md spec-interview.md spec-hardening.md scenarios.md specs.md tests.md
security.md project-workflow.md github-actions.md allium.md"

is_core() {
  case "$2" in
    scripts) printf '%s\n' $CORE_SCRIPTS | grep -qx "$1" ;;
    rules)   printf '%s\n' $CORE_RULES   | grep -qx "$1" ;;
    *) return 1 ;;
  esac
}

# The one place this project says this well, and now it has two callers: the
# --accept-local refusal below, which fires AFTER a doomed edit, and --is-core above,
# which fires before one. Spec 007ak's block was deleted twice for want of the second
# caller; two copies of the sentence would put this very fix back on a drift path.
core_refusal_text() {
  printf "'%s' is CORE machinery. This sync overwrites it unconditionally:\n" "$1"
  printf 'manifest or not, local edit or not. A change that lives only in this project\n'
  printf 'is deleted by the next sync, and recording it as an intentional difference\n'
  printf 'would only promise a silence that same sync would break. Land the change in\n'
  printf 'the template instead.\n'
}

# ------------------------------------------------------------ --is-core (spec 007ao)
# Answers "who owns this file" and nothing else: no sync, no commit, no template, no
# network. It sits here, above even the project-root walk, because every early exit
# below this line is `exit 0` — and in this mode 0 means CORE, so borrowing any of
# them would answer the question wrongly and confidently. Cost matters too: the
# script reaches arg parsing in 6 ms and template resolution in 1.015 s, with the
# clone fetch bounded at 20 s (007ao research.md M7), and scripts/core-machinery-
# guard-hook.sh calls this before every Edit.
#
# The path is PROJECT-RELATIVE. Resolving an absolute one would need the root walk
# this block exists to precede, and a caller that has a file path has already walked
# to the root to find this script.
#   0 = CORE, refusal text on stdout · 1 = not CORE · 2 = cannot answer
if [ "$MODE_IS_CORE" -eq 1 ]; then
  case "$IS_CORE_PATH" in
    "")  warn "[is-core] no path given."; exit 2 ;;
    /*)  warn "[is-core] '$IS_CORE_PATH' is absolute; pass a path relative to the project root."; exit 2 ;;
  esac
  IS_CORE_REL=${IS_CORE_PATH#./}
  # Exactly one segment under each directory. `.claude/skills/x/scripts/detect-stack.sh`
  # is somebody else's file that happens to share a basename, and the sync would never
  # touch it — so neither does this answer.
  case "$IS_CORE_REL" in
    scripts/*/*|.claude/rules/*/*) exit 1 ;;
    scripts/*)                     IS_CORE_CLASS=scripts ;;
    .claude/rules/*)               IS_CORE_CLASS=rules ;;
    *)                             exit 1 ;;
  esac
  is_core "$(basename "$IS_CORE_REL")" "$IS_CORE_CLASS" || exit 1
  core_refusal_text "$IS_CORE_REL"
  exit 0
fi

# ---------------------------------------------------------------- project root
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -d "$DIR/.git" ]; then PROJECT_ROOT="$DIR"; break; fi
  DIR=$(dirname "$DIR")
done
[ -n "$PROJECT_ROOT" ] || { say "[skip] not inside a git repository"; exit 0; }
[ -d "$PROJECT_ROOT/.claude" ] || { say "[skip] no .claude/ — not a Claude Code project"; exit 0; }

# Never sync the template onto itself. Identify it by remote URL — file markers
# are useless here because the sync copies scripts/sync-prompt.md and friends
# into every project, so every synced project looks like the template.
ORIGIN=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)
case "$ORIGIN" in
  *johanolofsson72/Claude.git|*johanolofsson72/Claude|*:johanolofsson72/Claude*)
    say "[skip] this IS the template repo"; exit 0 ;;
esac

# ------------------------------------------------- is git mid-operation? (spec 007be)
# One answer, two callers: the deferral gate below the --accept-local block, and 007bd's
# commit arm ~1500 lines down, which is now reachable only under --ignore-in-progress. Both
# used to be — and the second one was — a hand-written four-marker `if`; spec 007ay is this
# project's record of what an idiom copied to N sites costs, and N=2 is where that starts.
#
# $IN_PROGRESS_OP carries the operation's NAME, not just a boolean, because the deferral block
# says which one is in progress. 007bd's `[mid-rebase]` block keeps its generic wording — it is
# not this spec's block to reword — but telling a developer mid-cherry-pick that "a rebase/merge"
# is in progress is mildly false, and the variable is free.
#
# rebase-merge and rebase-apply are both "rebase": they are the interactive and the am-based
# backend for the same operation, and the difference is git's business rather than the reader's.
#
# The markers are paths under .git/, inherited from 007bd. The project-root walk above requires
# `-d "$DIR/.git"`, so a linked worktree (whose .git is a FILE) never becomes $PROJECT_ROOT and
# the question never arises. If that walk ever learns about worktrees, this is the one place that
# has to learn with it.
operation_in_progress() {
  if [ -d "$PROJECT_ROOT/.git/rebase-merge" ] || [ -d "$PROJECT_ROOT/.git/rebase-apply" ]; then
    IN_PROGRESS_OP="rebase"
  elif [ -f "$PROJECT_ROOT/.git/MERGE_HEAD" ]; then
    IN_PROGRESS_OP="merge"
  elif [ -f "$PROJECT_ROOT/.git/CHERRY_PICK_HEAD" ]; then
    IN_PROGRESS_OP="cherry-pick"
  else
    IN_PROGRESS_OP=""
    return 1
  fi
  return 0
}

# ------------------------------------------------------------- template source
# Preference: explicit env var → local clone → GitHub tarball (David's path).
TEMPLATE_DIR=""
TEMPLATE_SHA=""
TEMPLATE_TMP=""

# A local clone is preferred over the tarball, and until this existed it was also
# never refreshed: resolve_local_template took `rev-parse HEAD` as the template's
# SHA and copied whatever bytes happened to be checked out. sync-prompt.md Step -1
# tells every developer to clone the template to ~/repos/Claude, so the moment they
# follow that instruction their autosync pins itself to the commit they cloned --
# silently, forever. The stamp then matches the frozen SHA on every run, so the
# hook reports a clean sync and nothing ever says the source is months stale.
#
# So: fetch, then decide by relationship to origin/main. Four states, and only one
# of them is the bug:
#
#   equal     nothing to do.
#   behind    the stale-clone bug. Fast-forward it (clean trees only) and say so.
#   ahead     the template author's own machine, mid-work. Leave it alone -- those
#             unpushed commits are exactly what their other projects should receive.
#   diverged  local commits AND upstream commits. Ambiguous, so touch nothing and
#             warn; rewriting someone's clone and ignoring their commits are both
#             wrong, and a human can tell which one they meant.
#
# Fails open in every direction: no network, no git, not a clone, a clone of some
# other repo living at that path -- all of them fall back to "use it as-is", which
# is precisely the behaviour that existed before.
refresh_local_template() {
  _c="$1"
  git -C "$_c" rev-parse --git-dir >/dev/null 2>&1 || return 0
  case "$(git -C "$_c" remote get-url origin 2>/dev/null)" in
    *johanolofsson72/Claude.git|*johanolofsson72/Claude|*:johanolofsson72/Claude*) ;;
    *) return 0 ;;   # a different repo parked at that path: not ours to fetch
  esac

  # Bounded, because this runs from SessionStart. A fetch that hangs on a dead
  # network must not become the session's startup cost.
  _to=""
  if command -v timeout  >/dev/null 2>&1; then _to="timeout 20"
  elif command -v gtimeout >/dev/null 2>&1; then _to="gtimeout 20"; fi
  $_to git -C "$_c" fetch --quiet origin main >/dev/null 2>&1 || {
    warn "[note] template clone at $_c could not be fetched (offline?) -- using it as-is"
    return 0
  }

  _head=$(git -C "$_c" rev-parse HEAD 2>/dev/null)          || return 0
  _up=$(git -C "$_c" rev-parse origin/main 2>/dev/null)     || return 0
  [ "$_head" = "$_up" ] && return 0

  _behind=0; _ahead=0
  git -C "$_c" merge-base --is-ancestor "$_head" "$_up" 2>/dev/null && _behind=1
  git -C "$_c" merge-base --is-ancestor "$_up" "$_head" 2>/dev/null && _ahead=1

  if [ "$_behind" -eq 1 ]; then
    if [ -n "$(git -C "$_c" status --porcelain 2>/dev/null | head -1)" ]; then
      # Dirty AND behind: the uncommitted work is deliberate (the -dirty- SHA below
      # exists for exactly that case), so it wins -- but say the source is stale,
      # because that is the part nobody would otherwise notice.
      warn "[warn] template clone at $_c is behind origin/main and has uncommitted changes."
      warn "       Syncing from the working tree as-is. Commit or stash, then re-run to fast-forward."
      return 0
    fi
    if git -C "$_c" merge --ff-only --quiet origin/main >/dev/null 2>&1; then
      warn "[ok] template clone fast-forwarded to origin/main -- the files below come from the newer template"
    else
      warn "[warn] template clone at $_c is behind origin/main but would not fast-forward."
      warn "       Syncing from the stale checkout. Fix the clone with: git -C $_c pull --ff-only"
    fi
    return 0
  fi

  [ "$_ahead" -eq 1 ] && return 0   # author's machine, mid-work: their commits are the point

  warn "[warn] template clone at $_c has diverged from origin/main (local commits AND upstream commits)."
  warn "       Nothing was changed. Syncing from the local checkout; reconcile it by hand."
}

resolve_local_template() {
  for cand in "${CLAUDE_TEMPLATE_DIR:-}" "$HOME/repos/Claude" "$HOME/repos/claude"; do
    [ -n "$cand" ] || continue
    if [ -f "$cand/scripts/sync-prompt.md" ] && [ -d "$cand/.claude/rules" ]; then
      refresh_local_template "$cand"
      TEMPLATE_DIR="$cand"
      TEMPLATE_SHA=$(git -C "$cand" rev-parse --short=12 HEAD 2>/dev/null || echo "local-unknown")
      # A dirty working tree means the files being copied are NOT what the SHA
      # describes. Stamping the clean SHA would make the next run think it is
      # up to date and skip the (still uncommitted) changes forever.
      if [ -n "$(git -C "$cand" status --porcelain 2>/dev/null | head -1)" ]; then
        TEMPLATE_SHA="$TEMPLATE_SHA-dirty-$(date -u '+%Y%m%d%H%M%S')"
      fi
      return 0
    fi
  done
  return 1
}

resolve_remote_template() {
  command -v curl >/dev/null 2>&1 || return 1
  TEMPLATE_SHA=$(git ls-remote "$TEMPLATE_REPO_URL" main 2>/dev/null | cut -c1-12)
  [ -n "$TEMPLATE_SHA" ] || return 1
  # Only pay for the download when the SHA actually moved.
  STAMP_SHA=$(sed -n 's/^sha=//p' "$PROJECT_ROOT/.claude/.template-sync" 2>/dev/null | head -1)
  if [ "$TEMPLATE_SHA" = "$STAMP_SHA" ] && [ "$FORCE" -eq 0 ]; then
    return 2   # up to date, no download needed
  fi
  TEMPLATE_TMP=$(mktemp -d 2>/dev/null || mktemp -d -t claude-template)
  curl -fsSL --max-time 60 "$TEMPLATE_TARBALL" 2>/dev/null | tar -xz -C "$TEMPLATE_TMP" 2>/dev/null || return 1
  TEMPLATE_DIR=$(find "$TEMPLATE_TMP" -maxdepth 1 -type d -name 'Claude-*' | head -1)
  [ -n "$TEMPLATE_DIR" ] && [ -d "$TEMPLATE_DIR/.claude/rules" ]
}

cleanup() { [ -n "$TEMPLATE_TMP" ] && rm -rf "$TEMPLATE_TMP"; }
trap cleanup EXIT

if ! resolve_local_template; then
  resolve_remote_template
  RC=$?
  if [ "$RC" -eq 2 ]; then say "[ok] already at template $TEMPLATE_SHA"; exit 0; fi
  if [ "$RC" -ne 0 ]; then
    # A sync that cannot reach the template does nothing and says so quietly; it runs
    # from a SessionStart hook and must never make offline look like breakage. An
    # --accept-local that cannot reach it has to fail loudly instead: the template's
    # hash is half the record, and inventing it would silence a file forever against
    # a value nobody ever computed.
    if [ "$MODE_ACCEPT" -eq 1 ]; then
      warn "[accept-local] refused: the template could not be resolved (no local clone, and no network)."
      warn "               Recording a difference needs the template's bytes. Set CLAUDE_TEMPLATE_DIR"
      warn "               to a local clone, or retry with a connection."
      exit 1
    fi
    say "[skip] template unreachable (offline?) — nothing changed"; exit 0
  fi
fi

STAMP="$PROJECT_ROOT/.claude/.template-sync"
# Spec 007bf hoisted this from below the copy loop, where it sat next to the block that first
# needed it. The stranded-writes detector runs at the `[ok] already at template` early exit, which
# is ~1000 lines above that, and this is a constant with no reader in between — so the hoist
# carries no behaviour and the alternative (a second spelling of the same literal) is how the two
# copies of a path drift apart.
STAMP_REL=".claude/.template-sync"
# Spec 007ax. Declared here rather than beside the stamp write, because `set -u` is on and the
# commit gate reads it on every path — including the ones that return before the stamp is composed.
STAMP_REWRITTEN=0

# --------------------------------------------------------------------- hashing
# Spec 007az moved this block above the stamp comparison below. It used to sit after it, which
# was fine while only the sync path hashed anything — and stopped being fine the moment the
# `[ok] already at template` path needed to hash too. Nothing between the old position and this
# one calls any of the three, so the move carries no behaviour.
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}
sha_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum 2>/dev/null | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 2>/dev/null | cut -d' ' -f1
  else cksum 2>/dev/null | cut -d' ' -f1; fi
}
manifest_hash() { grep -F "  $1" "$STAMP" 2>/dev/null | head -1 | cut -d' ' -f1; }

# ------------------------------------------------ CORE divergence (spec 007az)
# Spec 007ao made this script refuse a project that tries to WRITE into a CORE file, and tell the
# author to land the change in the template instead. Nothing checked that they did.
#
# Spec 007as landed a fix in msroute's CORE copy, wrote "needs template propagation" in its own
# run-log, and shipped. Eighteen hours later a sync deleted all 35 net lines of it. The run-log is
# not pipeline input and SessionStart surfaces it only while the row is `- [/]`, so from the moment
# the row was ticked the note was addressed to nobody.
#
# 007at and 007au both report at the DESTROYING sync — correctly, and too late to matter. The
# interval before it is what this is for: it opens when someone edits a CORE file, closes at the
# next template release, and is bounded by nothing. During it the stamp comparison below exits
# before a single file is hashed, so every session start says `[ok]` while the work sits there
# waiting to be overwritten.
#
# The comparison is free. For a CORE file the manifest hash IS the template's hash — copy_file
# writes $SRC_HASH on every arm that emits a manifest line — so no resolve, clone or fetch is
# needed to answer it. Verified 58/58 on this project (spec research.md M2).
#
# Measured before it was designed rather than after (M4): across all 42 stamped projects on the
# author's machine it fires on ONE, naming two files, both genuine. Compare the heuristic 007au
# had to REJECT at 33% precision as "the line readers learn to skip". If that ratio ever moves,
# the block is wrong and the fix is to delete it — not to add a threshold, which is exactly how
# the 33% version nearly shipped.

# Paths on stdin, one per line -> `<sha>  <path>` for each readable one.
#
# One process, not one per file: 0.024 s against 1.475 s over 58 files (M5), and this runs
# unattended at every session start of every project. 1.5 s is the tax that gets a feature
# deleted rather than fixed — the same reasoning the skills loop already records for its single
# `git check-ignore`.
#
# Same three backends as sha_of, in the same order, so a manifest written by one is never
# compared against a hash produced by another. The cksum arm falls back to a per-file loop rather
# than going silent: a wrong-algorithm comparison would report every CORE file as divergent, and
# silence would drop the real ones. It is correct on every backend and the 1.5 s is only ever
# paid on a machine with neither sha256sum nor shasum, which is not a machine in this fleet.
sha_many() {
  if command -v sha256sum >/dev/null 2>&1;  then tr '\n' '\0' | xargs -0 sha256sum 2>/dev/null
  elif command -v shasum >/dev/null 2>&1;   then tr '\n' '\0' | xargs -0 shasum -a 256 2>/dev/null
  else
    while IFS= read -r _f; do
      [ -n "$_f" ] && printf '%s  %s\n' "$(sha_of "$_f")" "$_f"
    done
  fi
}

# The CORE paths whose current bytes differ from what the manifest records, one per line.
core_divergence() {
  [ -f "$STAMP" ] || return 0

  # Membership comes from the same two variables is_core reads — never a second list, because a
  # second definition of CORE drifts from the first the moment either changes (the trap 007au
  # records where it classifies revert candidates). Filtered in one awk rather than by calling
  # is_core per path: 114 of msroute's manifest lines are CORE-SHAPED and only 58 are CORE, and a
  # subprocess each would cost precisely what sha_many exists to avoid.
  _core_paths=$(
    printf '%s\n' $CORE_SCRIPTS | sed 's#^#scripts/#'
    printf '%s\n' $CORE_RULES   | sed 's#^#.claude/rules/#'
  )

  # This guard is not defensive tidiness, and it is the ONLY thing standing between an empty
  # manifest and a hang. GNU xargs runs its utility once on empty input unless -r, BSD xargs does
  # not, and sha256sum with no arguments reads stdin — so the portable spelling of "hash nothing"
  # blocks forever on one of the two platforms, at session start, unattended.
  _want=$(printf '%s\n' "$_core_paths" \
    | awk 'NR == FNR { core[$0]; next } NF == 2 && ($2 in core) { print $1 "  " $2 }' - "$STAMP")
  [ -n "$_want" ] || return 0

  # A path the manifest names but the project no longer has produces no line from sha_many, so it
  # is never reported — a CORE file the project deleted is re-added by the next sync and there is
  # no divergence to speak of. That is FR-003 satisfied by construction rather than by a branch
  # that could be got wrong. The converse, a CORE file present with no manifest line, is absent
  # from $_want for the same structural reason: no evidence, no claim.
  _have=$(printf '%s\n' "$_want" | awk '{ print $2 }' | sha_many)

  # Both streams are `<sha>  <path>`, so they concatenate around a sentinel instead of needing a
  # process substitution. The script is bash and could use one; nothing else in it does.
  printf '%s\n--\n%s\n' "$_want" "$_have" \
    | awk '$0 == "--" { seen = 1; next }
           seen == 0  { want[$2] = $1; next }
           ($2 in want) && want[$2] != $1 { print $2 }'
}

# Silent on empty input. This text is forwarded verbatim into every session start, and a block
# that fires with nothing to report is what trains readers to skip the block.
#
# Past tense on the finding, timeless on the contract, because one wording has to be true on two
# paths in different states: on the early exit the files still differ, on the sync path the copy
# loop has already overwritten them by the time anything renders. "These differ" is false in the
# second case; "these will be overwritten" is false in it too.
#
# It names paths and stops. Not "you are about to lose work" — M4's own true positive is a case
# where nothing was lost, because the template had independently fixed the same bug. The block
# reports what it can prove and lets the developer read the diff.
report_owed() {
  [ -n "$1" ] || return 0
  tell "[owed] this sync found CORE file(s) differing from the bytes the template shipped:"
  printf '%s\n' "$1" | while IFS= read -r _p; do
    [ -n "$_p" ] && tell "         $_p"
  done
  tell "       CORE is overwritten unconditionally — a change that lives only here does not"
  tell "       survive. Land it in the template, push, then sync."
}

# ------------------------------------------- stranded writes (spec 007bf)
# Four arms of this script write to the working tree and do not commit: --no-commit,
# --ignore-in-progress during a rebase/merge/cherry-pick, 007av's fatal staging class (a held
# index.lock, an unmatched pathspec), and a commit that fails outright. The first two are the
# developer's choice; the second two are nobody's.
#
# On every one of them the stamp is still rewritten with the new template SHA — and the early exit
# at the top of this script reads the stamp. So the run that strands the files is the last run that
# ever looks at them: from then on every session start prints `[ok] already at template` and
# nothing else, forever (research.md M1, M2b, M3, M8).
#
# The worst instance is the CREATED file. A CORE rule the project did not have yet is written
# untracked — `??` in git status, invisible to `git diff`, absent from every clone — and CORE rules
# are the files that make this project's pipeline blocking. The sync creates one, files the receipt
# saying the project is current, and leaves it where a clone will not find it.
#
# Two fixes were measured and rejected before this one:
#
#   Hold the stamp back until the commit succeeds.  WORSE (M7). The next sync re-enters the copy
#   loop, finds the bytes already correct, writes nothing, records nothing — and commits the STAMP
#   ALONE under `0 updated, 0 added (stamp advance)`, asserting the project is at template X while
#   the files that would make that true sit uncommitted beside it. It adds a commit and fixes
#   nothing.
#
#   Have a later sync re-write and commit them.  Structurally impossible from the copy loop (M1b:
#   the bytes are already correct, so --force writes nothing either), and committing paths this
#   process did not write is 007av's defect, 007bb's and 007bd's at once.
#
# So: report, do not act. The family's posture, and the only one with a measurement behind it.
#
# Emits "<kind>\t<path>" per line, untracked before modified, each sorted — untracked is the larger
# problem and a fixed order is what the tests assert on. Empty output is the healthy answer and the
# common one: measured across all 42 stamped projects on the author's machine, zero manifest paths
# are dirty (M5). That is the property that lets this block be trusted rather than skipped, and it
# is the same bar 007az set for [owed] and 007au failed at 33% precision.
stranded_writes() {
  # Every guard fails SILENT. This runs unattended at every session start, its contract is that a
  # template problem never stops a session starting, and a detector that cannot answer must not
  # guess. A project with no commits in particular cannot strand anything against a HEAD it has
  # not got — that is not a finding, it is a project on its first day.
  [ -n "$PROJECT_ROOT" ] && [ -f "$STAMP" ] || return 0
  git -C "$PROJECT_ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1 || return 0

  # The manifest's path column, plus the stamp itself. The stamp has no manifest line of its own —
  # it is the file the manifest lives in — and it belongs here because 007ax established that a
  # stamp left dirty is the same event as the files it claims to have shipped.
  _paths=$(awk '!/^#/ && NF == 2 { print $2 }' "$STAMP" 2>/dev/null)
  [ -n "$_paths" ] || return 0
  _paths="$_paths
$STAMP_REL"

  # Two processes, not one per path. ~172 paths on this project and this is on the session-start
  # path of 42 of them; a subprocess per file is the 1.5-second tax that gets a feature deleted
  # rather than fixed (the same reasoning sha_many already records).
  #
  # `git diff HEAD` covers staged AND unstaged in one answer, which is both cheaper and more
  # correct than asking twice: an index entry is not a commit, so a staged-but-uncommitted write is
  # every bit as stranded as an unstaged one.
  #
  # $_paths is word-split into a pathspec deliberately, exactly like stage_all's `git add` and
  # 007bb's $COMMIT_PATHS, and safe on the same guarantee — every path this sync writes is a
  # template path with no spaces in it.
  _mod=$(git -C "$PROJECT_ROOT" diff --name-only HEAD -- $_paths 2>/dev/null)
  # --exclude-standard is load-bearing, not tidiness. `git add` refuses an ignored path silently
  # (007an measured it, 007aq is the __pycache__ case), so an ignored write was never going to be
  # committed by anyone — naming it would be this block reporting a file the project deliberately
  # excludes, which is precisely the false line that teaches readers to skip the block.
  _unt=$(git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- $_paths 2>/dev/null)

  # Per-path work happens ONLY for what those two returned, which on a healthy project is nothing.
  _keep() {
    _p="$1"
    [ -f "$PROJECT_ROOT/$_p" ] || return 1     # a deleted manifest path is report_orphans' business
    [ "$_p" = "$STAMP_REL" ] && return 0      # no manifest line of its own; see above
    # Clause 4, and the whole difference between "the sync reports its own unfinished work" and
    # "the sync has opinions about the developer's tree": keep the path only if its bytes on disk
    # are the bytes the manifest says this sync wrote. A developer who edited a template file
    # afterwards has moved it off that hash, and the sync then says nothing — the dirt is theirs,
    # and copy_file already has a name for it (`skip (locally edited)`).
    _mh=$(manifest_hash "$_p")
    [ -n "$_mh" ] && [ "$_mh" = "$(sha_of "$PROJECT_ROOT/$_p")" ]
  }

  { printf '%s\n' "$_unt" | grep -v '^$' | sort | while IFS= read -r _p; do
      _keep "$_p" && printf 'untracked\t%s\n' "$_p"
    done
    printf '%s\n' "$_mod" | grep -v '^$' | sort | while IFS= read -r _p; do
      _keep "$_p" && printf 'modified\t%s\n' "$_p"
    done
  }
  # Explicit, because the healthy path ends on a `grep` that found nothing and would otherwise
  # hand back 1. Nothing reads this status today; a function whose success code says "there is
  # nothing wrong here" is a trap for whoever adds `set -e` or an `&&` to a call site.
  return 0
}

# Silent on empty input, for the reason report_owed is: this text is forwarded verbatim into every
# session start of every project, and a block that fires with nothing to report is what trains a
# reader to skip the place the next real finding will appear.
#
# `tell`, not `say`, so --quiet does not swallow it. 007be measured what that costs: a block
# printed with `say` reaches a session start as complete silence.
#
# It names paths and one command. Not "you are about to lose work" — nothing here knows that, and
# report_owed's own true positive was a case where nothing was lost. Not "commit them now" either:
# the state that stranded these may still be live, and telling a developer mid-rebase to commit is
# the advice 007bd removed from this script in the form of an actual `git add`.
report_stranded() {
  [ -n "$1" ] || return 0
  tell "[stranded] file(s) this sync wrote that the repository does not hold:"
  printf '%s\n' "$1" | while IFS="$(printf '\t')" read -r _k _p; do
    [ -n "$_p" ] && tell "$(printf '             %-10s %s' "$_k" "$_p")"
  done
  tell "           The stamp already names this template, so no later sync writes them again or"
  tell "           mentions them. \`git add -- <path>\` when your tree is in a state to take them."
}

STAMP_SHA=$(sed -n 's/^sha=//p' "$STAMP" 2>/dev/null | head -1)
if [ "$TEMPLATE_SHA" = "$STAMP_SHA" ] && [ "$FORCE" -eq 0 ]; then
  say "[ok] already at template $TEMPLATE_SHA"
  # Rendered here rather than collected for later, because on this path there is no later.
  report_owed "$(core_divergence)"
  # Spec 007bf. THE call site. This line is the entire output of a stranded project — the stamp
  # names the new template, so every run lands here and says `[ok]` over files the repository has
  # never seen. After [owed] because [owed] asks for a decision and this asks for a command.
  report_stranded "$(stranded_writes)"
  exit 0
fi

# Measured BEFORE the copy loops, because the copy loops are what destroy the evidence: a CORE
# file that diverged is overwritten by copy_file and would hash equal to the manifest by the time
# any report block runs. Rendered much further down, with the others, so nothing that reads this
# script's output sees the block order change.
#
# Inherited rather than re-measured after a self-update re-exec, and that is not an optimisation —
# re-measuring is WRONG there, which the first run of this code proved by accusing the sync of
# editing itself. Pass 1 writes the new template-autosync.sh and re-execs; the stamp is not
# rewritten until the very end, so pass 2 opens with the NEW bytes on disk and the OLD hash in
# the manifest. That is the exact signature of a local edit, and it is the sync's own write.
#
# The same reasoning as the line above, one process further out: pass 1's measurement was taken
# before anything had been written, so pass 1 is the only pass that ever saw the truth. The
# re-exec is just a copy loop that happened in a previous process, and $WROTE/$ADDED already
# cross it by the same route.
#
# AUTOSYNC_REEXEC is the discriminator, not the emptiness of the carried value — "pass 1 found
# nothing" and "there was no pass 1" are different states and only one of them may re-measure.
if [ "${AUTOSYNC_REEXEC:-0}" -eq 1 ]; then
  OWED="${AUTOSYNC_CARRY_OWED-}"
else
  OWED=$(core_divergence)
fi

# ------------------------------------------------- the intentional-difference record
# `<project-sha256>  <template-sha256>  <relpath>`, one line per accepted difference.
#
# Field-exact on $3, deliberately NOT the substring match manifest_hash uses: this
# lookup decides whether a file goes SILENT, and a record borrowed by a path that
# merely starts the same (`git.md` answering for `git.md.orig`) is a file nobody is
# ever told about. Comment lines are skipped so the file can explain itself.
LOCAL_RECORD="$PROJECT_ROOT/.claude/.sync-local"
local_record() {
  [ -f "$LOCAL_RECORD" ] || return 1
  awk -v p="$1" '$1 !~ /^#/ && NF == 3 && $3 == p { print $1 " " $2; found = 1; exit }
                 END { exit !found }' "$LOCAL_RECORD" 2>/dev/null
}

# Bootstrap discrimination: on the very first sync there is no manifest, so a
# file that differs from the template is ambiguous — it could be an older
# template version (safe to update) or a deliberate project customization
# (must not be touched). Resolve it against the template's own git history: if
# the project's exact bytes ever WERE a template version, nobody customized it.
# Only possible with a local clone; the tarball path has no history, so it
# falls back to the conservative "skip and report".
HISTORY_DEPTH="${TEMPLATE_HISTORY_DEPTH:-60}"
matches_template_history() {
  SRCREL="$1"; CUR="$2"
  [ -n "$TEMPLATE_TMP" ] && return 1
  git -C "$TEMPLATE_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  for h in $(git -C "$TEMPLATE_DIR" log --format=%H -n "$HISTORY_DEPTH" -- "$SRCREL" 2>/dev/null); do
    OLD=$(git -C "$TEMPLATE_DIR" show "$h:$SRCREL" 2>/dev/null | sha_stdin)
    [ "$OLD" = "$CUR" ] && return 0
  done
  return 1
}

# ------------------------------------------------------------------ stack gate
# testing=mobile means .claude/docs/testing.md holds the MOBILE content under
# the canonical name. Stamping the web doc over it is the documented failure
# that left a Flutter app reading "browser back mid-flow" instructions.
STACK=$(sed -n 's/^testing=//p' "$PROJECT_ROOT/.claude/.sync-stack" 2>/dev/null | head -1)
[ -n "$STACK" ] || STACK="unknown"

# ------------------------------------------------------- --accept-local (spec 007af)
# The ONLY writer of .claude/.sync-local, and it writes nothing else: no copy loop,
# no manifest, no commit, no push. That asymmetry — many readers, one deliberate
# writer — is the safety argument for keeping the record out of the manifest, which
# is regenerated wholesale on every run.
if [ "$MODE_ACCEPT" -eq 1 ]; then
  [ -n "$ACCEPT_PATHS" ] || { warn "[accept-local] refused: no path given."; exit 1; }

  # Which template file feeds this project path. They differ under the mobile stack
  # gate, where testing-mobile.md is written to the canonical testing.md — so the
  # record has to hash whichever file this project is actually fed from.
  accept_source_rel() {
    if [ "$STACK" = "mobile" ]; then
      case "$1" in
        .claude/docs/testing.md)                 printf '%s' ".claude/docs/testing-mobile.md"; return ;;
        .claude/docs/spec-testing-checklist.md)  printf '%s' ".claude/docs/spec-testing-checklist-mobile.md"; return ;;
      esac
    fi
    printf '%s' "$1"
  }

  # Both passes over the same list: validate every path, and only then write any of
  # them. A refusal that had already written the paths before it would make "writes
  # nothing on a refusal" true per-path and false per-invocation.
  for REL in $ACCEPT_PATHS; do
    REL=${REL#./}
    SRCREL=$(accept_source_rel "$REL")
    DEST="$PROJECT_ROOT/$REL"
    SRC="$TEMPLATE_DIR/$SRCREL"

    case "$REL" in
      scripts/*)        CLS=scripts ;;
      .claude/rules/*)  CLS=rules ;;
      *)                CLS=other ;;
    esac

    if [ ! -f "$DEST" ]; then
      warn "[accept-local] refused: '$REL' is not in this project."
      exit 1
    fi
    if [ ! -f "$SRC" ]; then
      warn "[accept-local] refused: the template does not ship '$SRCREL', so there is nothing to"
      warn "               differ from — this sync never looks at that path."
      exit 1
    fi
    if is_core "$(basename "$REL")" "$CLS"; then
      # One subshell, so _first survives the loop; the prefix appears once and the
      # continuations align under it, exactly as this refusal has always read.
      core_refusal_text "$REL" | { _first=1; while IFS= read -r _l; do
        if [ "$_first" -eq 1 ]; then warn "[accept-local] refused: $_l"; _first=0
        else warn "               $_l"; fi
      done; }
      exit 1
    fi
    if [ "$(sha_of "$DEST")" = "$(sha_of "$SRC")" ]; then
      warn "[accept-local] refused: '$REL' is identical to the template — there is no difference to"
      warn "               accept, and the record would be stale the moment it was written."
      exit 1
    fi
  done

  for REL in $ACCEPT_PATHS; do
    REL=${REL#./}
    SRCREL=$(accept_source_rel "$REL")
    P_HASH=$(sha_of "$PROJECT_ROOT/$REL")
    T_HASH=$(sha_of "$TEMPLATE_DIR/$SRCREL")

    # Rebuilt whole and sorted rather than appended: this is a committed file two
    # people may touch, and an append-ordered record turns a one-line change into a
    # diff nobody reads. Rebuilding is also what makes a re-accept a replacement —
    # two lines for one path would make the answer depend on read order.
    RECORD_TMP=$(mktemp 2>/dev/null || mktemp -t syncrecord)
    {
      [ -f "$LOCAL_RECORD" ] && awk -v p="$REL" '$1 !~ /^#/ && NF == 3 && $3 != p { print }' "$LOCAL_RECORD"
      printf '%s  %s  %s\n' "$P_HASH" "$T_HASH" "$REL"
    } | sort -k3 > "$RECORD_TMP"
    {
      printf '# Intentional local differences from the template (spec 007af).\n'
      printf '# <project-sha256>  <template-sha256>  <path> — the two hashes the difference was\n'
      printf '# accepted at. Neither side moved: silent. Either side moved: reported again, saying\n'
      printf '# which. Written only by `scripts/template-autosync.sh --accept-local <path>`.\n'
      cat "$RECORD_TMP"
    } > "$LOCAL_RECORD"
    rm -f "$RECORD_TMP"

    tell "[accept-local] recorded $REL"
    tell "               project  $P_HASH"
    tell "               template $T_HASH  ($SRCREL @ $TEMPLATE_SHA)"
  done

  tell "[accept-local] nothing else was written — commit .claude/.sync-local with the change that made"
  tell "               the difference intentional."
  exit 0
fi

# --------------------------------------- defer while git is mid-operation (spec 007be)
# 007bd stopped this sync STAGING into a half-finished rebase. It still wrote, and the write is
# the half nothing ever argued for — 007bd's own test says so: "Withholding the write would be a
# different spec." This is that spec.
#
# Two measurements decided it. First, the run that makes those writes is the LAST run that ever
# looks at them (research.md M1): it writes the stamp too, the stamp already names the new
# template SHA, so the next session start short-circuits at "already at template X" and exits
# above the copy loop. The rules stay untracked indefinitely. The stamp is a receipt for work the
# sync declined to finish.
#
# Second, the obvious alternative — write to disk, skip the manifest and the stamp — is WORSE than
# today (M3). The next run finds the files identical to the template, takes the copy loop's
# CUR_HASH = SRC_HASH early return (which records no $WROTE entry), and therefore stages and
# commits ONLY the stamp: `0 updated, 0 added (stamp advance)` beside two uncommitted files the
# same sync put there, with the manifest now recording their hashes so no future run touches them
# either. 007bb and 007ax's defect rebuilt from parts.
#
# So the exit goes BEFORE the copy loop, and it is not a fifth early-exit path. MODE_CHECK is
# already threaded through every subsystem this has to turn off, because --check and --dry-run
# needed exactly that: the copy loop's two `[ "$MODE_CHECK" -eq 1 ] ||` guards suppress every
# atomic_copy, the check block does `rm -f "$NEW_MANIFEST"`, and its `exit 0` sits above the
# self-update, the hook re-wiring, the outputStyle seed, the extension policy, the stack marker,
# the stamp, stage_all and the commit. A second way to say "write nothing" would be a second
# thing to keep in step with the first.
#
# `[ "$MODE_CHECK" -eq 0 ]` is not redundant. A developer who typed --check or --dry-run asked for
# a report; nothing was withheld from them, and a [deferred] block on that run would be reporting
# a decision the gate did not make.
#
# Placed after the --accept-local block on purpose: recording an intentional difference writes one
# uncommitted record file and is a deliberate act the developer just typed, not a sync arriving
# unasked from a hook. --is-core exits even higher.
if [ "$IGNORE_IN_PROGRESS" -eq 0 ] && [ "$MODE_CHECK" -eq 0 ] && operation_in_progress; then
  DEFERRED=1
  MODE_CHECK=1
  MODE_DRYRUN=1
fi

WROTE=""; SKIPPED=""; ADDED=""; ADOPTED=""

# ---------------------------------------------------- recording what this sync wrote
# Spec 007ay. $WROTE and $ADDED are space-delimited path lists, and appending to one
# correctly is load-bearing three times over: they become the argument list for
# `git add`, the counts in the headline's cross-check, and the file names in the
# [changed] block.
#
# The leading and trailing spaces in the membership test are the whole mechanism —
# they make the pattern match a WHOLE space-delimited field, so an already-recorded
# `scripts/graphify-ab.sh` cannot suppress `scripts/graphify-a.sh`. Get that spacing
# wrong and the append is skipped: a file dropped from `git add` with no error and no
# output. Before this spec the idiom was hand-written at EIGHT sites, which is eight
# chances to get it wrong; worse, it had already drifted into two silently different
# variants — five testing the union, three testing $WROTE alone, with nothing at any
# site saying which was deliberate.
#
# Both lists are tested, always. A file this sync CREATED is not also a file it
# UPDATED, and the [changed] renderer walks the two lists independently — so a path
# in both renders twice, with opposite verbs. Measured (007ay research.md M1): a
# project seeded with settings.json reported `add .claude/settings.json` and
# `update .claude/settings.json` four lines apart, in the same block.
#
# `return 0` is explicit, not decoration: three call sites are the last statement of
# an `if` body, and a `case` falling through with the status of its last test would
# change that block's result — the same trap fold_helper_writes documents below.
# The empty-argument guard keeps a call site with an unset variable from appending a
# blank field, which would reach `git add` as a stray empty argument.
record_write() {
  [ -n "${1:-}" ] || return 0
  case " $WROTE $ADDED " in *" $1 "*) ;; *) WROTE="$WROTE $1" ;; esac
  return 0
}

record_add() {
  [ -n "${1:-}" ] || return 0
  case " $WROTE $ADDED " in *" $1 "*) ;; *) ADDED="$ADDED $1" ;; esac
  return 0
}
# Spec 007af. INTENTIONAL is the only bucket that is never reported; the other two
# are the two ways a recorded difference comes back, and STALE is a record whose
# subject has gone away.
INTENTIONAL=""; LOCAL_MOVED=""; TMPL_MOVED=""; STALE=""; SEEN_RECORDS=""
# Spec 007aw. Every path the copy loop VISITED, which is not the same set as the paths it wrote
# and not the same set as the manifest keeps. It is the only thing that can answer "did the
# template stop shipping this", because the manifest is regenerated from what the loop saw and so
# forgets a retracted path on the very run that could have noticed it.
VISITED=""
NEW_MANIFEST=$(mktemp 2>/dev/null || mktemp -t manifest)

# The template's mode is the template's to choose. Git records ONE permission bit per
# file (100644 / 100755), so the exec bit is the whole of what a mode difference can mean
# in a commit, and mirroring it is a complete account of what the sync can affect.
#
# `[ -x ]` and `chmod +x`/`-x` are POSIX. Deliberately NOT `stat`, whose format flag
# differs between macOS (-f '%Lp') and Linux (-c '%a'), and not `chmod --reference`, which
# is GNU-only — neither is worth carrying for the fuller mode git discards anyway.
exec_bit_differs() {   # exec_bit_differs <src> <dst>
  if [ -x "$1" ]; then [ ! -x "$2" ]; else [ -x "$2" ]; fi
}

mirror_exec_bit() {    # mirror_exec_bit <src> <dst>
  if [ -x "$1" ]; then chmod +x "$2" 2>/dev/null; else chmod -x "$2" 2>/dev/null; fi
}

# Write via temp + rename, never `cp` onto a live path.
#
# This sync overwrites scripts/template-autosync.sh — itself — while bash is
# still reading it. bash reads a script incrementally by byte offset, so a plain
# `cp` truncates and rewrites the SAME inode under the running interpreter, which
# then resumes at its old offset inside different content and dies with a syntax
# error somewhere in the middle of the file. `mv` swaps the directory entry
# instead: the running process keeps its original inode open and finishes
# cleanly, while the next exec picks up the new file. Same reasoning protects any
# hook script that happens to be executing during a sync.
#
# The two arms disagreed about whose mode wins: `cp` into a temp file that does not exist
# takes the SOURCE's mode, while `cp` over an existing destination keeps the DESTINATION's.
# The same sync therefore produced two different modes depending on which arm it took, and
# neither arm recorded which. Mirroring after both is what makes them agree.
atomic_copy() {
  _dst="$2"
  if cp "$1" "$_dst.autosync-tmp.$$" 2>/dev/null && mv -f "$_dst.autosync-tmp.$$" "$_dst" 2>/dev/null; then
    mirror_exec_bit "$1" "$_dst"
    return 0
  fi
  rm -f "$_dst.autosync-tmp.$$" 2>/dev/null
  cp "$1" "$_dst"   # last-resort fallback (e.g. a filesystem without rename)
  mirror_exec_bit "$1" "$_dst"
}

# copy_file <template-abs> <project-rel> <class> [<template-rel>]
copy_file() {
  SRC="$1"; REL="$2"; CLASS="$3"; SRCREL="${4:-$2}"
  DEST="$PROJECT_ROOT/$REL"
  BASE=$(basename "$REL")
  SRC_HASH=$(sha_of "$SRC")

  # Spec 007aw. Recorded HERE, at the top, before any branching — so it holds every path the
  # template still ships regardless of what this call decides to do with it. That is the whole
  # discrimination: the three shapes that reach a `return 0` below without writing a manifest line
  # (a .sync-local record, a SKIPPED file with no OLD_HASH, a non-CORE file the project deleted)
  # are exactly the false positives a manifest-generation diff produces — measured at 33%
  # precision on this project's own history and again on constructed data (research.md M2, M3).
  # Recording before the branches makes them structurally excluded, rather than a list of
  # exceptions that has to be maintained beside the branches that produce them.
  #
  # No `case ... in *" $REL "*` dedup, deliberately. The six loops are disjoint and the mobile gate
  # renames rather than duplicating, so each path arrives once; and this is only ever read as a
  # membership test, where a duplicate would be harmless anyway. Spec 007ay is an open row about
  # that idiom being hand-written at eight sites — a ninth, for a guarantee this variable does not
  # need, is the wrong direction.
  VISITED="$VISITED $REL"

  if [ -f "$DEST" ]; then
    CUR_HASH=$(sha_of "$DEST")
    if [ "$CUR_HASH" = "$SRC_HASH" ]; then
      # A record for a file that no longer differs is rot: harmless, but it is the
      # one way this file accumulates lies. Reported so a human can delete it —
      # never deleted here, because the sync does not get to un-decide things.
      if local_record "$REL" >/dev/null; then
        STALE="$STALE $REL"
        SEEN_RECORDS="$SEEN_RECORDS $REL"
      fi
      printf '%s  %s\n' "$SRC_HASH" "$REL" >> "$NEW_MANIFEST"
      # Bytes agreeing is not the same as files agreeing. This early return is the only
      # path that reaches a file whose content is already correct, so it is the only place
      # an EXISTING mode divergence can be seen at all — without this, deleting the chmod
      # loop would stop new churn and freeze every instance of the old churn in place.
      # The $WROTE entry is outside the MODE_CHECK guard on purpose: --check/--dry-run then
      # list a pending correction under `update` with no extra code. No difference means no
      # entry, so a sync over an agreeing project still reports 0 updated and writes nothing.
      if exec_bit_differs "$SRC" "$DEST"; then
        [ "$MODE_CHECK" -eq 1 ] || mirror_exec_bit "$SRC" "$DEST"
        WROTE="$WROTE $REL"
      fi
      return 0                                  # identical content; mode reconciled above
    fi
    OLD_HASH=$(manifest_hash "$REL")
    if [ "$CUR_HASH" != "$OLD_HASH" ] && ! is_core "$BASE" "$CLASS"; then
      # Has this difference been accepted? Asked BEFORE the history lookup for two
      # reasons. A settled record is the answer that lookup is searching for, so
      # running it anyway costs ~0.2 s of every sync to reach the same negative
      # forever. And bytes that ARE an older template version would be "adopted" —
      # overwritten — which would make recording a divergence the thing that
      # deletes it.
      REC=$(local_record "$REL")
      if [ -n "$REC" ]; then
        SEEN_RECORDS="$SEEN_RECORDS $REL"
        REC_PROJECT=${REC%% *}; REC_TEMPLATE=${REC##* }
        if [ "$REC_PROJECT" != "$CUR_HASH" ]; then
          # Project side first: if both moved, the local edit is the one the
          # developer made and the one they can explain.
          LOCAL_MOVED="$LOCAL_MOVED $REL"
        elif [ "$REC_TEMPLATE" != "$SRC_HASH" ]; then
          TMPL_MOVED="$TMPL_MOVED $REL"
        else
          INTENTIONAL="$INTENTIONAL $REL"
        fi
        # No manifest line either way. The manifest records bytes this sync WROTE;
        # it wrote none of these, and .sync-local is where their record lives.
        return 0
      fi
      # No manifest entry (first sync) → ask the template's history whether
      # these bytes are just an older template version.
      if [ -z "$OLD_HASH" ] && matches_template_history "$SRCREL" "$CUR_HASH"; then
        ADOPTED="$ADOPTED $REL"                 # stale template copy → update it
      else
        SKIPPED="$SKIPPED $REL"                 # differs, unrecorded → hands off
        [ -n "$OLD_HASH" ] && printf '%s  %s\n' "$OLD_HASH" "$REL" >> "$NEW_MANIFEST"
        return 0
      fi
    fi
    [ "$MODE_CHECK" -eq 1 ] || atomic_copy "$SRC" "$DEST"
    WROTE="$WROTE $REL"
  else
    # New file: only add CORE machinery, plus template-owned SKILLS. A doc/rule
    # the project deliberately removed (wordpress.md on a .NET project) must stay
    # removed — but a missing skill is never a decision, it is just a project that
    # predates the skill. Skills are add-if-missing yet manifest-protected on
    # update (they are not in the CORE set), so a customized skill is still safe.
    is_core "$BASE" "$CLASS" || [ "$CLASS" = "skills" ] || return 0
    [ "$MODE_CHECK" -eq 1 ] || { mkdir -p "$(dirname "$DEST")"; atomic_copy "$SRC" "$DEST"; }
    ADDED="$ADDED $REL"
  fi
  printf '%s  %s\n' "$SRC_HASH" "$REL" >> "$NEW_MANIFEST"
}

for f in "$TEMPLATE_DIR"/scripts/*.sh "$TEMPLATE_DIR"/scripts/*.py; do
  [ -f "$f" ] || continue
  copy_file "$f" "scripts/$(basename "$f")" scripts
done

for f in "$TEMPLATE_DIR"/.claude/rules/*.md; do
  [ -f "$f" ] || continue
  copy_file "$f" ".claude/rules/$(basename "$f")" rules
done

for f in "$TEMPLATE_DIR"/.claude/agents/*.md; do
  [ -f "$f" ] || continue
  copy_file "$f" ".claude/agents/$(basename "$f")" agents
done

# Template-owned skills. Until this existed the sync shipped rules, docs, scripts
# and agents but never skills — so a fix to /project-wizard or /project-update sat
# in the template while 35 projects kept running the old copy. Since those two
# skills are what bootstrap and update a project, a stale copy reproduces bugs
# that were fixed months earlier. `find`, not a glob: skills carry nested files
# (ui-ux-pro-max/data/*.csv, project-wizard/install.sh).
#
# Spec 007aq. That `find` is the only recursive loop in this script — the other five are
# flat globs over *.sh/*.py/*.md and cannot reach a subdirectory — which makes it the only
# one that walks the template's WORKING TREE rather than a list of files the template means
# to ship. It shipped three compiled __pycache__/*.cpython-314.pyc to every project for
# months. They land on a path the project gitignores, so `git add` refuses them and they
# were committed never, in any project, once.
#
# The rule is: the sync copies what the template would SHIP. Two things are not content, and
# a path matching EITHER is skipped.
#
#   1. Compiled python, always. `__pycache__/` as a path segment, `.pyc`/`.pyo` as a suffix.
#      Unconditional rather than a fallback, because python writes these next to any .py it
#      imports and the template does not get a say: it is equally build output on a template
#      that gitignored it, one that forgot to, and one extracted from a tarball with no git
#      at all. Making it conditional bought a hole — a .pyc the template had not gitignored
#      shipped anyway — for no benefit anybody could name.
#   2. Anything the template's own git disowns. The generalisation, so the next .DS_Store or
#      .pytest_cache/ needs no edit here. Additive: it can only remove more, never restore
#      something rule 1 rejected.
#
# --no-index is mandatory and is the trap. The three .pyc were TRACKED — they entered with
# the skill, before this repo's .gitignore learned about __pycache__/, and git's ignore rules
# do not apply to a path already in the index, which is exactly why only those three survived.
# check-ignore SKIPS tracked paths, so without --no-index it reports nothing at all and rule 2
# becomes a silent no-op that reviews clean. --no-index asks the question this loop actually
# has — what shape of path is this — rather than what the index currently holds.
#
# No exit code is read, and that is deliberate rather than an oversight. check-ignore exits 1
# when nothing matched and 128 when it could not be asked (the tarball case, no .git), and
# BOTH produce empty output — so both are already the right answer for an additive list. An
# exit-code test here would be three branches where the code has one behaviour, and the
# tempting spelling of it (-ne 0) is wrong, because a clean template is the exit-1 case.
#
# One process for the whole list, over stdin: this runs unattended at SessionStart, and one
# subprocess per file would be 41 of them per sync with nobody to pay for it.
if [ -d "$TEMPLATE_DIR/.claude/skills" ]; then
  SKILL_FILES=$(cd "$TEMPLATE_DIR/.claude/skills" && find . -type f 2>/dev/null | sed 's#^\./##')
  SKILL_PATHS=$(printf '%s\n' "$SKILL_FILES" | grep -v '^$' | sed 's#^#.claude/skills/#')

  SKILL_IGNORED=$(
    printf '%s\n' "$SKILL_PATHS" | grep -E '(^|/)__pycache__/|\.py[co]$'
    printf '%s\n' "$SKILL_PATHS" | git -C "$TEMPLATE_DIR" check-ignore --no-index --stdin 2>/dev/null
  )

  for rel in $SKILL_FILES; do
    # Excluded HERE, before copy_file, and nowhere else. $WROTE and $ADDED are written only
    # by copy_file and they feed all four downstream consumers — the new manifest, the
    # `git add` argument list, the [changed] name block and the [written] reconciliation
    # block. Skipping the copy and then filtering a report would reproduce the defect in
    # the report.
    case "
$SKILL_IGNORED
" in *"
.claude/skills/$rel
"*) continue ;; esac
    copy_file "$TEMPLATE_DIR/.claude/skills/$rel" ".claude/skills/$rel" skills
  done
fi

for f in "$TEMPLATE_DIR"/.claude/docs/*.md; do
  [ -f "$f" ] || continue
  B=$(basename "$f")
  case "$STACK:$B" in
    # Mobile/hybrid: the canonical names carry mobile content — never overwrite
    # them with the browser versions.
    mobile:testing.md|mobile:spec-testing-checklist.md) continue ;;
    mobile:testing-mobile.md)                copy_file "$f" ".claude/docs/testing.md" docs ".claude/docs/testing-mobile.md"; continue ;;
    mobile:spec-testing-checklist-mobile.md) copy_file "$f" ".claude/docs/spec-testing-checklist.md" docs ".claude/docs/spec-testing-checklist-mobile.md"; continue ;;
    # Web: no mobile docs.
    web:testing-mobile.md|web:spec-testing-checklist-mobile.md|web:deployment-mobile.md) continue ;;
  esac
  copy_file "$f" ".claude/docs/$B" docs
done

# A record whose path the copy loop never reached — the template stopped shipping it,
# or the project deleted it. Nothing is skipped on its behalf any more, so the record
# is doing nothing except waiting to be believed about a file that is not there.
if [ -f "$LOCAL_RECORD" ]; then
  for _r in $(awk '$1 !~ /^#/ && NF == 3 { print $3 }' "$LOCAL_RECORD" 2>/dev/null); do
    case " $SEEN_RECORDS " in *" $_r "*) ;; *) STALE="$STALE $_r" ;; esac
  done
fi

# ------------------------------------------- paths the template stopped shipping (spec 007aw)
# This sync adds files and updates files. It has no third verb, and until now it did not merely
# fail to remove a retracted path — it failed to MENTION one, and then destroyed the evidence.
#
# The manifest is rebuilt from what the copy loop saw, so a path the template no longer ships is
# never iterated, never written to NEW_MANIFEST, and silently absent from the stamp after the next
# write. Reproduced end to end (research.md M0): the run reports `0 written, 0 created, 0 skipped`
# — indistinguishable from a healthy no-op — while the manifest line disappears and the file stays
# on disk. And the window is exactly ONE run (M4): on the next sync the previous generation has
# forgotten it too, and the orphan is undetectable from the manifest forever.
#
# Asked of VISITED and not of a manifest-generation diff, because that diff measures 33% precision
# (M2: three events across 35 stamp commits, one of them real). Asked of VISITED and not of the
# template's filesystem either, which is the tempting one-liner and is wrong in the case that
# opened this row: 007aq excludes build output with a `continue` placed BEFORE copy_file, and does
# not delete anything, so the three .pyc are still sitting on the template's disk. "On the
# template's disk" and "shipped" are different questions.
#
# The previous generation is read straight from $STAMP, which is not overwritten until the stamp
# block far below — no snapshotting needed.
#
# The field test is deliberately NOT `$1 ~ /^[0-9a-f]{64}$/`: sha_of falls back to `cksum` when
# neither sha256sum nor shasum exists, which prints a decimal, and a 64-hex assumption would
# silently disable this whole block on such a machine. `!~ /=/` drops the sha= / synced= / source=
# header lines, including a source= path that contains a space.
#
# The candidate set is the manifest body UNION the orphan lines already recorded, and the union is
# not a nicety — without it this block reproduces the very defect it exists to fix, one level up.
# A path is written to the manifest body only while the template still ships it, so the run that
# first reports an orphan is also the run that stops the body mentioning it. Ask the body alone on
# the NEXT run and the path is gone from it, the record is not carried forward, and the orphan
# evaporates exactly as it does today (measured: AC-2 failed this way on the first draft). An
# existing `# orphan` line is itself the claim "once written, no longer shipped", so it is a
# first-class source that gets re-tested every run — still unvisited? still on disk? — rather than
# a note that is only ever written. That re-test is also what lets a record DROP when the template
# resumes shipping a path: it becomes visited, and falls out with no special case.
ORPHAN_NEW=""; ORPHAN_STANDING=""; ORPHAN_LINES=""
if [ -f "$STAMP" ]; then
  ORPHAN_TODAY=$(date -u '+%Y-%m-%d')
  ORPHAN_CANDIDATES=$(
    { awk 'NF == 2 && $1 !~ /^#/ && $1 !~ /=/ { print $2 }' "$STAMP" 2>/dev/null
      awk '$1 == "#" && $2 == "orphan" { print $4 }' "$STAMP" 2>/dev/null
    } | grep -v '^$' | LC_ALL=C sort -u
  )
  for _m in $ORPHAN_CANDIDATES; do
    # Still shipped — the loop reached it, whatever it then decided to do.
    case " $VISITED " in *" $_m "*) continue ;; esac
    # Already resolved. The sync wrote this path once, so it was there; if it is gone the developer
    # has already acted, and a line about a condition nobody can act on is the permanent false
    # alarm .sync-local needed a STALE bucket to catch.
    [ -f "$PROJECT_ROOT/$_m" ] || continue

    # Field 4 is the path: `# orphan <first-seen> <path>`. Carrying the ORIGINAL date is what makes
    # the standing line worth printing — "since when" is the only thing it adds over a count.
    _seen=$(awk -v p="$_m" '$1 == "#" && $2 == "orphan" && $4 == p { print $3; exit }' "$STAMP" 2>/dev/null)
    if [ -n "$_seen" ]; then
      ORPHAN_STANDING="$ORPHAN_STANDING $_m"
    else
      _seen="$ORPHAN_TODAY"
      ORPHAN_NEW="$ORPHAN_NEW $_m"
    fi
    # Composed NOW, into a variable, because `> "$STAMP"` truncates the file before the block body
    # runs — reading the old stamp from inside that redirect would read an empty file.
    ORPHAN_LINES="$ORPHAN_LINES# orphan $_seen $_m
"
  done
fi
N_ORPHAN_NEW=$(echo "$ORPHAN_NEW" | tr ' ' '\n' | grep -c .)
N_ORPHAN_STANDING=$(echo "$ORPHAN_STANDING" | tr ' ' '\n' | grep -c .)

# Reported = the three buckets a reader can act on. INTENTIONAL is deliberately not
# among them: the whole point of the record is that a settled difference stops
# costing anybody a line.
REPORTED="$SKIPPED$LOCAL_MOVED$TMPL_MOVED"

if [ "$MODE_CHECK" -eq 1 ]; then
  rm -f "$NEW_MANIFEST"

  # -------------------------------------------------- the deferral, said out loud (spec 007be)
  # First, above the [check] lines, because on a deferred run the deferral IS the headline and
  # the counts are its detail.
  #
  # `tell`, not `say`, and that is load-bearing rather than stylistic: the SessionStart hook always
  # passes --quiet, which is exactly what `say` suppresses. Measured with the unchanged hook
  # (research.md M4), a deferral printed with `say` reaches the developer as complete silence —
  # the same silence as before, one layer further away. The [check] lines below keep `say`,
  # correctly: a developer who typed --check is not being interrupted.
  #
  # Silent when nothing was withheld (FR-007be-07). Mid-operation against an up-to-date template
  # the run is a no-op either way, and this text is forwarded verbatim into every session start.
  #
  # No file list of its own. --dry-run's list renders directly underneath on a manual run and is
  # suppressed by --quiet from the hook, which is the right split — a first sync into a project
  # would otherwise name 140 files into a session start.
  if [ "$DEFERRED" -eq 1 ]; then
    N_WAITING=$(( $(echo "$WROTE" | tr ' ' '\n' | grep -c .) + $(echo "$ADDED" | tr ' ' '\n' | grep -c .) ))
    [ "$N_WAITING" -gt 0 ] || exit 0
    tell "[deferred] a $IN_PROGRESS_OP is in progress, so this sync wrote NOTHING — not the files,"
    tell "           not the manifest, not the stamp. $N_WAITING file(s) are waiting."
    tell "           The stamp is unchanged, so the next session start syncs them for real."
    tell "           \`scripts/template-autosync.sh --ignore-in-progress\` to sync anyway."
  fi
  N_INTENTIONAL=$(echo "$INTENTIONAL" | tr ' ' '\n' | grep -c .)
  N_STALE=$(echo "$STALE" | tr ' ' '\n' | grep -c .)
  say "[check] template $TEMPLATE_SHA vs project $([ -n "$STAMP_SHA" ] && echo "$STAMP_SHA" || echo "never synced")"
  # `skip (locally edited):N` keeps its exact spelling — it is the string a reader's
  # eye is trained on, and silently redefining a counter is the same class of
  # mistake as the undirected wording this record replaced. It now counts
  # UNRECORDED differences; the recorded ones get counters of their own, printed
  # only when they have something to say.
  COUNTS="[check] would update:$(echo "$WROTE" | tr ' ' '\n' | grep -c .) · add:$(echo "$ADDED" | tr ' ' '\n' | grep -c .) · skip (locally edited):$(echo "$REPORTED" | tr ' ' '\n' | grep -c .)"
  [ "$N_INTENTIONAL" -gt 0 ] && COUNTS="$COUNTS · intentional:$N_INTENTIONAL"
  [ "$N_STALE" -gt 0 ] && COUNTS="$COUNTS · stale:$N_STALE"
  # Spec 007aw. New and standing together: --check answers "what is the state of this project",
  # not "what changed this run", and an orphan is equally real either way. The stamp is NOT
  # written on this path, so a check never consumes a discovery — the next real sync still reports
  # it as new.
  [ $((N_ORPHAN_NEW + N_ORPHAN_STANDING)) -gt 0 ] \
    && COUNTS="$COUNTS · orphaned:$((N_ORPHAN_NEW + N_ORPHAN_STANDING))"
  say "$COUNTS"
  if [ "$MODE_DRYRUN" -eq 1 ]; then
    for x in $WROTE;       do say "  update $x"; done
    for x in $ADDED;       do say "  add    $x"; done
    for x in $ADOPTED;     do say "  adopt  $x (older template copy, not a local edit)"; done
    for x in $INTENTIONAL; do say "  local  $x (intentional, unchanged since it was accepted)"; done
    for x in $LOCAL_MOVED; do say "  CHECK  $x (the local copy changed since it was accepted — merge, or re-run --accept-local)"; done
    for x in $TMPL_MOVED;  do say "  CHECK  $x (the template changed under an accepted local difference — merge, then --accept-local)"; done
    for x in $STALE;       do say "  stale  $x (recorded as an intentional difference, but no longer differs — drop the line)"; done
    for x in $ORPHAN_NEW      ; do say "  orphan $x (the template no longer ships this — nothing is deleted for you)"; done
    for x in $ORPHAN_STANDING ; do say "  orphan $x (the template no longer ships this — already recorded)"; done
    # No direction asserted: the sync knows these bytes differ and nothing else.
    # Claiming the project is behind is what 007w measured backwards.
    for x in $SKIPPED;     do say "  SKIP   $x (differs from the template — merge it with /project-update, or record it with --accept-local)"; done
  fi
  # Spec 007bf. --check and --dry-run are the modes a developer runs BEFORE anything happens, and
  # they are the ones that must not be missing a warning that is free here. Sibling row 007bg is
  # open because [owed] is built and rendered at two sites out of four and neither is this one;
  # this block ships with its check-mode rendering rather than needing a spec to add it later.
  #
  # 007be's deferral routes through this same block (it sets MODE_CHECK/MODE_DRYRUN and falls in
  # here), so a sync deferred mid-rebase in an already-stranded project reports both — which is the
  # right pair of sentences for that developer to read together.
  report_stranded "$(stranded_writes)"
  exit 0
fi

# No chmod pass here. A blanket `chmod +x` over everything written under scripts/ used to
# live at this point, narrowed to what the sync wrote so it would not flip the mode on the
# project's own scripts. The narrowing was the right answer to the wrong question: the sync
# has no basis for deciding a .sh must be executable, and the template had already decided
# by committing it 644 or 755. It shipped three CORE files non-executable — including this
# script — and the loop made all three 755 in every project it touched. atomic_copy now
# carries the template's mode (it always did, on its primary arm), and the wiring helpers
# copy with shutil.copy2, which preserves mode. Nothing needs a chmod here.

# ------------------------------------------------------------- self-update
# A project runs its OWN copy of this script, so the CORE_SCRIPTS list in memory
# is the one from the PREVIOUS template version. When the template adds a new
# enforcement script, this run copies the updated template-autosync.sh but has
# already decided (using the stale list) not to add the new script — so the
# project needs a second run to converge. Re-exec once with the freshly-written
# version instead. AUTOSYNC_REEXEC bounds it to exactly one hop: no matter what
# the new version does, it cannot re-exec again.
if [ "${AUTOSYNC_REEXEC:-0}" -eq 0 ]; then
  case " $WROTE " in
    *" scripts/template-autosync.sh "*)
      say "[self-update] template-autosync.sh changed — re-running once with the new version"
      # Carry this pass's file LISTS, not just counts. `git add -- $WROTE $ADDED`
      # in the second pass stages only what that pass touched, so carrying counts
      # alone leaves pass-1's files updated on disk but absent from the commit.
      AUTOSYNC_REEXEC=1
      AUTOSYNC_CARRY_WROTE="$WROTE"
      AUTOSYNC_CARRY_ADDED="$ADDED"
      # Spec 007az. Carried for the opposite reason to the two above: those would be LOST across
      # the re-exec, this one would be FABRICATED. Pass 2 cannot re-derive it, because by then
      # this pass has already written the file the question is about. Newline-separated, unlike
      # the space-separated lists, because that is what core_divergence emits and report_owed
      # consumes.
      AUTOSYNC_CARRY_OWED="$OWED"
      export AUTOSYNC_REEXEC AUTOSYNC_CARRY_WROTE AUTOSYNC_CARRY_ADDED AUTOSYNC_CARRY_OWED
      rm -f "$NEW_MANIFEST"
      exec bash "$PROJECT_ROOT/scripts/template-autosync.sh" $ORIG_ARGS --force
      ;;
  esac
fi

# ------------------------------------------------------- core-hook re-wiring
HOOKS_NOTE=""

# A project with .claude/ but no settings.json has the rules and the scripts and
# runs NONE of it — every hook lives in settings.json, so the whole deterministic
# layer is simply absent. The wiring helpers then fail with "project settings not
# found", which the block below used to report as a rollback, implying damage
# where there was nothing to roll back. Seed it from the template instead; this is
# what /project-update's settings.json merge prescribes for a file that does not
# exist yet ("File does NOT exist in this project → copy from template").
if [ ! -f "$PROJECT_ROOT/.claude/settings.json" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ]; then
  atomic_copy "$TEMPLATE_DIR/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json"
  record_add .claude/settings.json
  HOOKS_NOTE="settings.json seeded from template (project had none)"
  warn "[note] $PROJECT_ROOT had no .claude/settings.json — seeded from the template."
  warn "       Enforcement hooks are now ACTIVE here. If this project has source code"
  warn "       but no specs/INDEX.md, spec-register-guard will block source edits until"
  warn "       you create the register (the deny message explains how)."
fi
# -------------------------------------------------- outputStyle (add-if-absent)
# The hook helpers below rewire `hooks` and nothing else, so a settings key the
# template adopts reaches a project only through /project-update's prose merge --
# which most projects never run, because autosync exists precisely so they do not
# have to. outputStyle is the first such key, and it is worth carrying: a built-in
# output style modifies the SYSTEM PROMPT, where CLAUDE.md only adds a user message
# after it, so "Proactive" states the autonomy contract in .claude/rules/
# continuous-execution.md one layer above everything else that argues for it.
#
# Add-if-absent, never overwrite: a project that already names an outputStyle made
# a choice, and silently replacing someone's chosen voice is not a sync, it is a
# hijack. Idempotent, and a parse failure leaves the file untouched.
if [ -f "$PROJECT_ROOT/.claude/settings.json" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ] \
   && [ "$MODE_CHECK" -eq 0 ] && command -v python3 >/dev/null 2>&1; then
  if python3 - "$PROJECT_ROOT/.claude/settings.json" "$TEMPLATE_DIR/.claude/settings.json" <<'PYEOF'
import json, sys
proj, tmpl = sys.argv[1], sys.argv[2]
try:
    p = json.load(open(proj, encoding="utf-8"))
    t = json.load(open(tmpl, encoding="utf-8"))
except Exception:
    sys.exit(1)                      # unreadable: leave it alone
want = t.get("outputStyle")
if not want or p.get("outputStyle"):
    sys.exit(1)                      # nothing to add, or the project already chose
p["outputStyle"] = want
tmp = proj + ".outputstyle-tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(p, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
json.load(open(tmp, encoding="utf-8"))   # must still parse before it replaces anything
import os; os.replace(tmp, proj)
PYEOF
  then
    STYLE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["outputStyle"])' "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null)
    warn "[note] settings.json had no outputStyle — set to \"$STYLE\" from the template."
    record_write .claude/settings.json
  fi
fi

if [ -f "$PROJECT_ROOT/scripts/sync-core-hooks.py" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ] \
   && command -v python3 >/dev/null 2>&1; then
  cp "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.autosync-bak" 2>/dev/null
  if (cd "$PROJECT_ROOT" && python3 scripts/sync-core-hooks.py "$TEMPLATE_DIR/.claude/settings.json" >/dev/null 2>&1) \
     && python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    if cmp -s "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.autosync-bak"; then
      HOOKS_NOTE="hooks unchanged"
    else
      HOOKS_NOTE="hooks rewired"
      record_write .claude/settings.json
    fi
    rm -f "$PROJECT_ROOT/.claude/settings.json.autosync-bak"
  else
    mv "$PROJECT_ROOT/.claude/settings.json.autosync-bak" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
    HOOKS_NOTE="hook rewiring FAILED (settings.json restored)"
    warn "[warn] sync-core-hooks.py failed — settings.json rolled back"
  fi
fi

# ------------------------------------- fold in what the wiring helpers wrote
# sync-local-llm-hooks.py and sync-graphify-wiring.py mirror their own script
# families as a side effect of wiring, outside the copy loop above — so those
# writes do not enter $WROTE on their own and would escape the commit, leaving
# the repo permanently dirty with files identical to the template.
#
# Spec 007ar. This used to be inferred: a sweep of `git status --porcelain -- scripts`
# folded every dirty path matching the two families into $WROTE. That asks git WHAT IS
# DIRTY, not WHAT DID I WRITE, and the sync runs unattended at SessionStart — when a
# developer's tree is at its dirtiest. Measured, it committed an in-flight edit to a
# graphify script in a run that simultaneously reported the same file under `[manual]
# files that differ from the template and are left alone`, under a message crediting the
# template; and it committed an UNTRACKED project-only scratch file the template has
# never shipped, creating that file's entire git history. The copy loop's decision to
# keep its hands off a locally-edited file was undone three hundred lines later by a loop
# that never asked who wrote it.
#
# Both helpers already print exactly what they wrote — `  + name` per file copied,
# `  - name` per file deleted, basenames, sorted, silent when nothing moved — and that
# output was being discarded with `>/dev/null`. So: read the report, do not guess from
# the working tree.
#
# Deletions are folded in like copies. The graphify block below calls its helper with NO
# delete-guard (unlike the local-LLM one, which refuses to run when its delete set is
# non-empty), and `git add` on a vanished path stages its removal. Folding `+` alone
# would recreate the escaping-writes bug on the deletion side.
#
# The basename pattern is deliberately narrow — no `/`, no space. Both helpers glob
# scripts/<pattern> non-recursively and print `p.name`, so that is the only shape they
# can produce; anything else is drift and is dropped rather than word-split into
# `git add`, which is how the old sweep handed git a mangled argument for any path
# containing a space.
#
# fold_helper_writes <helper-name> <helper-stdout>
fold_helper_writes() {
  _helper="$1"; _out="$2"; _n=0
  for _name in $(printf '%s\n' "$_out" | sed -n 's/^  [+-] \([^/ ]*\)$/\1/p'); do
    _n=$((_n + 1))
    record_write "scripts/$_name"
  done

  # Cross-checked against the helper's own count. A format drift that parsed nothing would
  # leave the repository dirty with the helper's writes and say nothing — the exact bug this
  # fold exists to prevent, returning with no symptom. Same lesson as 007at: a sync that
  # reports success it did not verify.
  # head -1 before the arithmetic: a helper emitting two summary lines would otherwise make
  # the comparison below a `[: too many arguments` on stderr — a report about drift that
  # fails noisily on the very drift it was reporting. Summed with shell arithmetic rather
  # than an awk call, and only once there is something to sum, so the no-summary case never
  # reaches the sum at all.
  _counts=$(printf '%s\n' "$_out" \
    | sed -n 's/^scripts: copied \([0-9][0-9]*\), deleted \([0-9][0-9]*\)$/\1 \2/p' | head -1)
  if [ -n "$_counts" ]; then
    _claimed=$(( ${_counts%% *} + ${_counts##* } ))
    if [ "$_claimed" -ne "$_n" ]; then
      tell "[sync] $_helper reported $_claimed script write(s), $_n parsed — output format drift"
    fi
  fi
  # Explicit: this is the last statement in an `if` body at both call sites, and a
  # fall-through status from the test above would change that block's result.
  return 0
}

# The local-LLM hook family is owned by its own helper (core-hooks deliberately
# ignores it), so wiring changes there — e.g. adding `if` filters — do not
# propagate without this. The helper treats the template as source of truth and
# DELETES project local-llm scripts the template does not ship; unattended
# deletion is not something this sync promises, so run it only when the delete
# set is provably empty and report otherwise.
if [ -f "$PROJECT_ROOT/scripts/sync-local-llm-hooks.py" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ] \
   && command -v python3 >/dev/null 2>&1; then
  EXTRA=""
  for pf in "$PROJECT_ROOT"/scripts/local-llm-*-hook.sh; do
    [ -f "$pf" ] || continue
    [ -f "$TEMPLATE_DIR/scripts/$(basename "$pf")" ] || EXTRA="$EXTRA $(basename "$pf")"
  done
  if [ -n "$EXTRA" ]; then
    HOOKS_NOTE="$HOOKS_NOTE · local-LLM wiring skipped (project-only scripts would be deleted:$EXTRA)"
  else
    cp "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.autosync-bak" 2>/dev/null
    # stdout captured rather than discarded — it is the helper's report of the scripts it
    # mirrored (007ar). `$?` after a plain assignment from a command substitution is the
    # substitution's own status, so the condition below tests exactly what it tested before.
    # stderr keeps its `2>/dev/null`: the failure path writes there and the rollback branch
    # is what handles it.
    LLM_OUT=$( (cd "$PROJECT_ROOT" && python3 scripts/sync-local-llm-hooks.py "$TEMPLATE_DIR/.claude/settings.json" 2>/dev/null) )
    if [ $? -eq 0 ] && python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
      if ! cmp -s "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.autosync-bak"; then
        HOOKS_NOTE="$HOOKS_NOTE + local-LLM rewired"
        record_write .claude/settings.json
      fi
      # Outside the cmp test on purpose: a run can rewire nothing and still mirror a script.
      fold_helper_writes sync-local-llm-hooks.py "$LLM_OUT"
      rm -f "$PROJECT_ROOT/.claude/settings.json.autosync-bak"
    else
      mv "$PROJECT_ROOT/.claude/settings.json.autosync-bak" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
      HOOKS_NOTE="$HOOKS_NOTE · local-LLM rewiring FAILED (rolled back)"
    fi
  fi
fi

# ------------------------------------------- converge on the documented order
# Each wiring helper strips its own hook family and re-appends it, so whichever
# runs LAST decides where that family sits. This script ran core -> local-llm ->
# graphify; scripts/sync-prompt.md (which /project-update executes) runs
# local-llm -> core -> graphify. Same 76 hooks either way, different group order
# -- two valid fixed points, each internally idempotent, oscillating against each
# other. The practical cost: /project-update rewrote settings.json on a project
# this sync had just settled, and the next sync rewrote it back, so neither could
# ever be a no-op and a real settings change was invisible among the churn.
#
# Re-running core here puts its family last, matching the documented order.
# Cheaper and safer than moving the block: the core helper has its own rollback
# and, unlike the local-llm one, never deletes project-owned scripts.
if [ -f "$PROJECT_ROOT/scripts/sync-core-hooks.py" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ] \
   && command -v python3 >/dev/null 2>&1; then
  cp "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.order-bak" 2>/dev/null
  if (cd "$PROJECT_ROOT" && python3 scripts/sync-core-hooks.py "$TEMPLATE_DIR/.claude/settings.json" >/dev/null 2>&1) \
     && python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    cmp -s "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.order-bak" \
      || record_write .claude/settings.json
    rm -f "$PROJECT_ROOT/.claude/settings.json.order-bak"
  else
    mv "$PROJECT_ROOT/.claude/settings.json.order-bak" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
  fi
fi

# ...and graphify last, which this script never ran at all. /project-update does
# (sync-prompt.md Step 5d), so its family ended up in a different place than this
# sync left it — the other half of the same oscillation. The helper documents both
# of its entries as safe to inject unconditionally (the PreToolUse nudge guards on
# graphify-out/graph.json, the telemetry hook bails when the command does not
# match), and prune-dangling-hooks.py below unwires anything whose script is absent.
if [ -f "$PROJECT_ROOT/scripts/sync-graphify-wiring.py" ] && [ -f "$TEMPLATE_DIR/.claude/settings.json" ] \
   && command -v python3 >/dev/null 2>&1; then
  cp "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.order-bak" 2>/dev/null
  # Captured for the same reason as the local-LLM call above (007ar). This is also the block
  # that can DELETE — it has no delete-guard — so its `- name` lines are the ones that make
  # the deletion arm of fold_helper_writes load-bearing rather than defensive.
  GFY_OUT=$( (cd "$PROJECT_ROOT" && python3 scripts/sync-graphify-wiring.py "$TEMPLATE_DIR/.claude/settings.json" 2>/dev/null) )
  if [ $? -eq 0 ] && python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    cmp -s "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json.order-bak" \
      || record_write .claude/settings.json
    fold_helper_writes sync-graphify-wiring.py "$GFY_OUT"
    rm -f "$PROJECT_ROOT/.claude/settings.json.order-bak"
  else
    mv "$PROJECT_ROOT/.claude/settings.json.order-bak" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
  fi
fi

# --------------------------------------------------- prune dangling hook refs
# settings.json can reference scripts the project never received — the graphify
# and local-LLM families are owned by other helpers and are stack/opt-in gated,
# and a wholesale seed brings their wiring along regardless. A hook pointing at a
# missing script never errors; it silently does nothing while every "is it wired?"
# audit reports green. Unwire what is not there.
if [ -f "$PROJECT_ROOT/scripts/prune-dangling-hooks.py" ] && command -v python3 >/dev/null 2>&1; then
  PRUNED=$( (cd "$PROJECT_ROOT" && python3 scripts/prune-dangling-hooks.py 2>/dev/null) | tail -1)
  case "$PRUNED" in
    *"removed"*)
      HOOKS_NOTE="${HOOKS_NOTE:+$HOOKS_NOTE · }$PRUNED"
      record_write .claude/settings.json
      ;;
  esac
fi

# ------------------------------------------- spec-kit extension policy
# `specify init --force` re-enables the git extension every time it runs, and it
# runs outside this sync (via /project-update or by hand). Re-assert the policy
# here so a project cannot silently regain feature-branch + auto-commit skills
# that contradict spec-register.md. Idempotent and silent when already correct.
if [ -f "$PROJECT_ROOT/scripts/speckit-extension-policy.sh" ]; then
  POL=$(bash "$PROJECT_ROOT/scripts/speckit-extension-policy.sh" --repo "$PROJECT_ROOT" 2>/dev/null | head -1)
  if [ -n "$POL" ]; then
    say "[speckit] $POL"
    record_write .specify/extensions/.registry
  fi
fi

# ------------------------------------------------- stack marker (derive if absent)
# `.claude/.sync-stack` gates which testing docs this project receives. When it is
# missing the doc gate has nothing to go on and stamps BOTH the web and the mobile
# set, so the project carries instructions for a platform it does not ship. Derive
# it once, from the same detector the canary uses, and only when the answer is
# unambiguous (detect-stack.sh prints nothing when it cannot tell).
if [ ! -f "$PROJECT_ROOT/.claude/.sync-stack" ] && [ -f "$PROJECT_ROOT/scripts/detect-stack.sh" ]; then
  DETECTED=$(bash "$PROJECT_ROOT/scripts/detect-stack.sh" "$PROJECT_ROOT" 2>/dev/null | sed -n '1p')
  if [ -n "$DETECTED" ]; then
    printf 'testing=%s\n' "$DETECTED" > "$PROJECT_ROOT/.claude/.sync-stack"
    record_add .claude/.sync-stack
    say "[stack] no .sync-stack marker — derived testing=$DETECTED from the project's manifests"
  fi
fi

# ------------------------------------------------------------------ the stamp
# Spec 007ax. Composed into a sibling temp and moved into place only when it has something to say.
#
# The two statements this sits between used to disagree. The stamp was rewritten unconditionally
# here, and the commit gate below asked `[ $((N_WROTE + N_ADDED)) -gt 0 ]` — so a run that wrote no
# project file rewrote the stamp and then declined to commit it, ending with the one file the sync
# unambiguously owns left modified in the developer's tree. Measured (research.md M0), and it does
# not heal: the early exit at the top compares the template SHA against the ON-DISK stamp, which
# already carries the new one, so the run that dirtied the file is the last run that looks at it.
# Reverting is worse than useless — it restores the old SHA, so the next SessionStart rewrites it
# again, every session, indefinitely (M2).
#
# `synced=` is excluded from the comparison and `source=` is NOT, which is the whole decision:
#
#   - `synced=` changes on every run by construction and is read by NOTHING (M5 — `sha=` is read
#     twice in this script, `synced=` never). A run whose only change is a clock reading has
#     nothing to record, and committing one would be the emptiest true statement the sync could
#     make — the judgement the `numstat` comment below already records against a `+19/-20` about
#     the manifest. This is not hypothetical: `--force` against an up-to-date project produces
#     exactly that diff and left it dirty (M3).
#   - `source=` says whether these bytes came from a local clone or from GitHub. That is provenance
#     a reader of the stamp is entitled to, so a change in it is news.
#
# Everything else — `sha=`, the manifest body, the 007aw orphan lines — is news. The orphan case is
# the one that matters most and the one an obvious "only commit when the sha moves" fix would miss:
# when the template STOPS shipping a path, this block records the retraction and its first-seen
# date on a run that writes no file at all (M7), and the old gate left that record uncommitted.
#
# A sibling temp rather than mktemp: same directory means `mv -f` is a rename and not a
# cross-filesystem copy, which is the idiom atomic_copy already uses in this file. A /tmp temp
# would degrade silently to a non-atomic copy on a project whose repo is on another filesystem —
# precisely what an unattended SessionStart run is least able to notice.
STAMP_NEW="$STAMP.autosync-tmp.$$"
{
  printf 'sha=%s\n' "$TEMPLATE_SHA"
  printf 'synced=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'source=%s\n' "$([ -n "$TEMPLATE_TMP" ] && echo github || echo "$TEMPLATE_DIR")"
  printf '# manifest: sha256 of each file as written by the sync — a project file\n'
  printf '# whose hash no longer matches was edited locally and is never overwritten.\n'
  sort -k2 "$NEW_MANIFEST"
  # Spec 007aw. Paths this sync once wrote that the template no longer ships. Carried forward
  # EXPLICITLY, because this stamp is regenerated wholesale on every run — an orphan line survives
  # only because these four lines re-emit it, and it is dropped the moment its file leaves the
  # disk. Self-clearing by construction: there is no flag to unset and no line to hand-edit (a
  # hand-edit would not survive the next regeneration anyway).
  #
  # The leading `#` is load-bearing, not decoration. manifest_hash is `grep -F "  $1"` — TWO
  # spaces — so an unprefixed `orphan  <path>` would match it and hand back the literal string
  # `orphan` as that file's hash. Prefixed, the line carries one space before the path, four
  # fields, and a `#` first field, so it is invisible to manifest_hash and to every `NF == 2`
  # reader in this script. Asserted, not trusted: see the manifest-collision test.
  if [ -n "$ORPHAN_LINES" ]; then
    printf '# orphan: paths this sync once wrote that the template no longer ships. Nothing is\n'
    printf '# deleted for you; a line disappears when its file does.\n'
    printf '%s' "$ORPHAN_LINES"
  fi
} > "$STAMP_NEW"
rm -f "$NEW_MANIFEST"

# Everything except the clock. Compared against the file ON DISK rather than against HEAD: it needs
# no git, it works in a project with no commits, and it answers the question actually being asked —
# did THIS run change anything? A HEAD baseline would also read a developer's uncommitted stamp as
# news on every subsequent run, which is the loop this spec exists to end.
stamp_news() { grep -v '^synced=' "$1" 2>/dev/null; }

if [ -f "$STAMP" ] && [ "$(stamp_news "$STAMP_NEW")" = "$(stamp_news "$STAMP")" ]; then
  # Nothing to say. Leave the stamp exactly as found — an untouched file is a clean tree, and a
  # clean tree needs no commit and no cleanup. A missing stamp is news by construction, which is
  # what the -f test buys: the first sync into a project always writes.
  rm -f "$STAMP_NEW"
else
  mv -f "$STAMP_NEW" "$STAMP" 2>/dev/null || cp "$STAMP_NEW" "$STAMP"
  rm -f "$STAMP_NEW"
  STAMP_REWRITTEN=1
fi

# Merge in whatever the pre-re-exec pass wrote, de-duplicated, so both the
# commit and the summary cover the entire sync and not just the second pass.
#
# Spec 007ay. These used to dedup each list against ITSELF, which let a path pass 1
# recorded in $ADDED enter $WROTE again here if pass 2 also touched it — the same
# double-render the union helpers exist to stop, on the re-exec path. Measured (M3):
# a settings.json seeded by pass 1 and rewired by pass 2 rendered as both `add` and
# `update`. The staged set is unaffected either way — `git add` receives $WROTE and
# $ADDED together — so this is a reporting fix, like the rest of the spec.
#
# One known imprecision, accepted rather than engineered around: when pass 1 CREATED a
# file and pass 2 UPDATED it, pass 2's record_write wins the union and the file renders
# as `update` though the sync as a whole created it. One line with the less precise
# verb beats two lines with contradictory ones, and promoting the path between lists to
# recover the verb is more machinery than a re-exec-only cosmetic warrants.
for _c in ${AUTOSYNC_CARRY_WROTE:-}; do record_write "$_c"; done
for _c in ${AUTOSYNC_CARRY_ADDED:-}; do record_add   "$_c"; done

N_WROTE=$(echo "$WROTE" | tr ' ' '\n' | grep -c .)
N_ADDED=$(echo "$ADDED" | tr ' ' '\n' | grep -c .)
N_SKIP=$(echo "$REPORTED" | tr ' ' '\n' | grep -c .)

# ------------------------------------------- what was WRITTEN vs what was RECORDED
# Spec 007an. $WROTE and $ADDED are this script's record of its own activity against
# the WORKING TREE. That is not what changed in the repository, and the two part
# company in two measured ways: a write can land on bytes identical to HEAD (the
# hook helpers rewrite .claude/settings.json in sequence and it comes back where it
# started), and a write can land on a path git ignores (`git add` skips those
# silently, exit 0). Across msroute's history 11 of 17 auto-messaged sync commits
# claimed more than they carried, and never fewer.
#
# STAGED_COUNT_IS_THE_HEADLINE — the marker scripts/test-sync-count-honesty.sh
# --history looks for to decide whether a given commit was made by a fixed script.
# Deliberately a behavioural marker and not a version number: a number has to be
# remembered and bumped by hand, and drifts from the behaviour it claims to mark.
#
# So the headline reports what the REPOSITORY recorded — the number a developer can
# check against the commit — and $WROTE/$ADDED are kept as the cross-check. Keeping
# both is the point: on 2026-08-08 the self-update re-exec dropped its file list and
# committed 1 of 14 written files, and the write count is the only number that would
# have shown it. A headline that only counted the commit would have called that run
# a healthy one-file sync.
# ($STAMP_REL was declared beside $STAMP — spec 007bf needed it ~1000 lines earlier.)

# Everything the sync believes it wrote, de-duplicated.
WRITTEN_ALL=$(printf '%s %s' "$WROTE" "$ADDED" | tr ' ' '\n' | grep -v '^$' | sort -u)

# Why did a written file leave no trace? Asked in this order on purpose: an ignored
# file has no HEAD blob, so testing for HEAD-identity first would label every .pyc
# as the mysterious third case. The third case is not dead code — it is what will
# surface the next cause nobody has met yet, and per the project's conservative-
# under-uncertainty principle it says less rather than guessing.
unrecorded_reason() {
  _p="$1"
  if git -C "$PROJECT_ROOT" check-ignore -q -- "$_p" 2>/dev/null; then
    printf 'ignored by git'; return
  fi
  # An untracked path has no HEAD blob, and a vanished file hashes to nothing —
  # both leave _h empty, so the emptiness test has to come first or "" = "" would
  # read as a match and label them a round-trip.
  _h=$(git -C "$PROJECT_ROOT" rev-parse "HEAD:$_p" 2>/dev/null)
  if [ -n "$_h" ] && [ "$_h" = "$(git -C "$PROJECT_ROOT" hash-object -- "$PROJECT_ROOT/$_p" 2>/dev/null)" ]; then
    printf 'rewritten, bytes identical to HEAD'
  else
    printf 'not recorded'
  fi
}

# Count what git holds staged, split by git's own status letters rather than by
# which of this script's two lists a path sat in. Commit 0a30a77 had the total
# right and the split wrong; one source for both makes that impossible instead of
# merely unlikely.
staged_names() {   # $1 = M, A or D
  git -C "$PROJECT_ROOT" diff --cached --name-only --diff-filter="$1" 2>/dev/null \
    | grep -v -x -F "$STAMP_REL"
}

# Spec 007bb. The index is not this sync's to describe. `git add` is handed a precise argument list
# and `git commit` used to be handed none, so what the commit recorded was that list PLUS whatever
# the developer already had staged — and the sync runs at SessionStart, which is exactly when that
# is most likely. Measured (research.md M0): a staged `devwork.txt` went into the commit, was
# counted as one of `0 updated, 2 added` under a template SHA, was named in the 007at verification
# obligation, and was pushed. It has happened here already: 10f9e1b carried a staged deletion of
# .claude/graphify-fire.log.errors under `19 updated, 0 added` (M3).
#
# So every question this script asks the index is narrowed to the paths the sync itself wrote.
# BOTH halves are needed and neither is sufficient:
#
#   git's list alone  — includes strangers (the defect).
#   $WROTE/$ADDED alone — includes paths git will NOT take. 007av's complaint class is precisely a
#                       healthy run holding one (git add exits 1, stages everything else), and
#                       `git commit -- <such a path>` is FATAL (M4c/M4d). Building the commit's
#                       pathspec from the script's own list would turn that healthy run into a
#                       failed commit.
#
# The intersection is what makes the pathspec safe: every element came out of `git diff --cached`,
# so every element is a path git has already accepted.
#
# The lookup keeps the leading AND trailing space of the `record_write` idiom, and for the identical
# reason: without it `scripts/graphify-a.sh` matches `scripts/graphify-ab.sh`. Getting that wrong
# here does not merely mis-report — it drops a file from a commit. Safe on the delimiter because
# every path reaching $WROTE came through the sync's own basename rule (no `/`, no space) or a
# template-relative path that has neither.
#
# Both directions live in one function rather than in two, and the argument is not a convenience:
# the delicate part is the two spaces in the pattern, and a second hand-written copy of that idiom
# is exactly what spec 007ay was opened to remove from this file. It also has to be a FUNCTION
# defined at top level — bash 3.2 (which `#!/bin/bash` still selects on macOS) cannot parse a
# `case` inside a `$( )`, which the [held] block below needs. Measured: a syntax error at parse
# time, taking the whole script down rather than one block.
owned_by_sync() {   # $1 = "keep" (default) — emit the sync's own paths; "drop" — emit everything else
  _keep="${1:-keep}"
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    case " $WROTE $ADDED " in
      *" $_p "*) [ "$_keep" = keep ] && printf '%s\n' "$_p" ;;
      *)         [ "$_keep" = keep ] || printf '%s\n' "$_p" ;;
    esac
  done
  # Explicit: the last `[ ]` in a case arm decides the loop's status, and a caller reading it would
  # be reading which branch the final path happened to take.
  return 0
}

# Spec 007au. The same index, asked which WAY the lines moved. `--numstat` measured at 13 ms
# against this project, identical to the `--name-only` above it — so the number the headline
# was missing costs nothing to fetch, and there was never a budget argument for going without.
#
# Taken here rather than at the point of use so it is captured at the same instant, from the
# same index, as the counts it sits beside: a movement figure that could disagree with its own
# file counts would be spec 007an's defect wearing a plus sign.
#
# The stamp is dropped once, here, so every consumer inherits that rather than re-deriving it.
# A stamp advance is a SHA moving over bytes the project already had — no code changed, and a
# `+19/-20` about the manifest would be the emptiest true statement the sync could make.
# Takes the diff selector, so the staged question and the working-tree question share one
# definition of "which rows count". They differed by a `--cached` and nothing else, and spec 007ay
# is an open row about precisely this shape of duplication in precisely this file.
numstat() {   # $@ = extra git-diff arguments (--cached for the index, nothing for the worktree)
  # Spec 007bb. Narrowed to the sync's own paths on the same terms as owned_by_sync above, in this
  # awk rather than in a second pass. Without it the `+N/-M lines` figure counted the developer's
  # lines and credited them to a template SHA — measured at `+1/-0` for a run that wrote nothing at
  # all (research.md M1). Both call sites need it: the staged one feeds the headline beside the
  # counts, and the worktree one (the --no-commit / --dry-run arm) is measured over a tree that is
  # dirty for reasons of its own.
  #
  # A rename renders `old => new` in field 3 and so matches nothing and is dropped. The sync does
  # not rename, and the direction of the error is the safe one: it under-reports our own movement
  # rather than crediting a stranger's.
  git -C "$PROJECT_ROOT" diff --numstat "$@" 2>/dev/null \
    | awk -F'\t' -v stamp="$STAMP_REL" -v own=" $WROTE $ADDED " \
        'NF >= 3 && $3 != stamp && index(own, " " $3 " ") > 0'
}

# Binary files render as `-<TAB>-<TAB>path`, and a rename renders `old => new` in field 3.
# Neither is arithmetic: the `-` would make `n += $1` a silent no-op in awk but `$((...))` a
# hard error in shell, so the numeric guard is explicit rather than trusted to a coercion.
sum_numstat() {   # $1 = numstat text, $2 = field (1 = insertions, 2 = deletions)
  printf '%s\n' "$1" | awk -F'\t' -v f="$2" '$f ~ /^[0-9]+$/ { n += $f } END { print n + 0 }'
}

N_UPD=0; N_NEW=0; STAGED_ALL=""; RECONCILED=0
STAGED_NUMSTAT=""; MOVED_INS=0; MOVED_DEL=0
# STAGED_DEL is read by the [changed] block ~200 lines below, which runs on every path
# including the ones where recount_staged never does (--no-commit, --dry-run, a run with
# nothing to stage). Under `set -u` an unset read there is not an empty string, it is a fatal
# error in the reporting tail of a sync that has already committed and pushed.
STAGED_DEL=""
# Spec 007bb, read by the commit below and initialised here for the same `set -u` reason.
STAGED_STAMP=""; COMMIT_PATHS=""
recount_staged() {
  # Spec 007bb. Filtered at the source, so every consumer inherits the narrowing rather than each
  # re-deriving it — the same judgement the numstat capture above records. This does NOT walk back
  # spec 007an: git is still the authority on whether a change was RECORDED, which is the whole of
  # that finding and of the STAGED_COUNT_IS_THE_HEADLINE marker. What changes is which paths the
  # question is asked about. Counting a file the sync never wrote as `1 added` under a template SHA
  # was never a measurement of the repository — it was a measurement of somebody else's index.
  STAGED_UPD=$(staged_names M | owned_by_sync)
  STAGED_NEW=$(staged_names A | owned_by_sync)
  STAGED_DEL=$(staged_names D | owned_by_sync)
  N_UPD=$(printf '%s\n' "$STAGED_UPD" | grep -c . 2>/dev/null); N_UPD=${N_UPD:-0}
  N_NEW=$(printf '%s\n' "$STAGED_NEW" | grep -c . 2>/dev/null); N_NEW=${N_NEW:-0}
  # Deletions join STAGED_ALL but NOT the two counters. STAGED_ALL answers "did this written
  # path leave a trace in the index?", and a staged deletion plainly did — without this, a
  # file the graphify helper removes is reported under `[written] ... not recorded`, which is
  # a false accusation about a change git recorded correctly. The counters are a separate
  # question ("N updated, M created"); spec 007au gives deletions their own verb in the
  # [changed] block instead, driven by STAGED_DEL below rather than by $WROTE — which folds
  # both directions into one list and so cannot answer.
  STAGED_ALL=$(printf '%s\n%s\n%s\n' "$STAGED_UPD" "$STAGED_NEW" "$STAGED_DEL" | grep -v '^$' | sort -u)
  STAGED_NUMSTAT=$(numstat --cached)
  MOVED_INS=$(sum_numstat "$STAGED_NUMSTAT" 1)
  MOVED_DEL=$(sum_numstat "$STAGED_NUMSTAT" 2)

  # The stamp is excluded from STAGED_ALL and from the counts everywhere else, so it has to be
  # asked for separately — and it is asked HERE rather than in the commit block that used to ask,
  # so the pathspec and the counts are read from the same index at the same instant. A stamp that
  # was staged when the arm was chosen and absent when the commit was built would be spec 007an's
  # defect wearing a pathspec.
  STAGED_STAMP=$(git -C "$PROJECT_ROOT" diff --cached --name-only -- "$STAMP_REL" 2>/dev/null)

  # What the commit is allowed to record. Every element came out of `git diff --cached`, which is
  # what keeps 007av's complaint class from becoming a fatal commit (owned_by_sync's comment).
  COMMIT_PATHS=$(printf '%s\n%s\n' "$STAGED_ALL" "$STAGED_STAMP" | grep -v '^$' | sort -u)
  RECONCILED=1
}

# ------------------------------------------------------------------ staging (spec 007av)
# `git add` was issued twice below and read back neither way: not `$?`, not the advice
# `2>/dev/null` swallowed. The next statement was recount_staged, which asks the index what it
# holds and never asks whether git put it there.
#
# It has THREE outcomes, and two of them are opposites (research.md M0, git 2.53.0):
#
#   0    every pathspec legal            everything staged
#   1    a pathspec git ignores          EVERYTHING ELSE STAGED — the job finished, with a complaint
#   >=2  index.lock held, or a pathspec  NOTHING STAGED — the index is untouched
#        matching no file
#
# So a boolean test on `$?` is wrong in one direction or the other: it either refuses a run that
# worked or waves through a run that did nothing. Hence three classes, not two.
#
# What the unread fatal cost, reproduced end to end (M3): a developer has work staged, one path in
# $WROTE matches no file (fold_helper_writes folds helper DELETIONS into it on purpose, which is
# right for a tracked path and fatal for one this project never committed), git stages nothing,
# recount_staged counts the DEVELOPER's index, and the sync commits and pushes it under
# `chore(sync): template abc — 0 updated, 1 added` while the file it actually wrote is absent from
# the commit. Same family as 007ad, 007ai and 007at: reporting a success nothing verified.
#
# Both routes are live. The sync runs from SessionStart, which is exactly when another git process
# is most likely to be mid-index-write, and losing that race is the fatal class.
#
# recount_staged is deliberately NOT called on the fatal class. There is nothing new in the index,
# and re-reading it would only re-measure somebody else's staging as if it were this sync's —
# which is the defect, not the diagnosis. Leaving RECONCILED at 0 also drops the headline into its
# existing write-count arm, whose "written/created" wording is already the true sentence for a run
# that recorded nothing.
STAGE_RC=0; STAGE_ERR=""
stage_all() {
  # Captured, not discarded — the exit code says WHICH class, git's own text says why (a held
  # lock reads differently from an unmatched path, and the sync cannot tell them apart alone).
  # Assigned on its own line so `$?` is git's status: inside `if OUT=$(...)` it would be the
  # substitution's, which is the trap the LLM_OUT/GFY_OUT comments above already record.
  #
  # $WROTE and $ADDED stay unquoted — the word-splitting is what makes them an argument list, and
  # the sync's basename rule is what makes that safe. A spaced path would land in the fatal class
  # (measured under bash) and now gets reported instead of silently mangled.
  STAGE_ERR=$( { git -C "$PROJECT_ROOT" add -- $WROTE $ADDED "$STAMP_REL" 2>&1 >/dev/null; } )
  STAGE_RC=$?
  # First line only. git writes a paragraph for a held lock, and this text is forwarded verbatim
  # into a session start — the same bound the 007at marker's `tail` lines carry.
  STAGE_ERR=$(printf '%s\n' "$STAGE_ERR" | sed -n '1p')
  [ "$STAGE_RC" -ge 2 ] || recount_staged
}

# ---------------------------------------------------------------- commit/push
COMMIT_NOTE="not committed"
SYNC_COMMIT=""; SYNC_PUSHED=no
# Spec 007bd. Read by the [held] gate and the [mid-rebase] block ~180 lines below, both of which run
# on every path including the ones that never reach the commit block at all (--dry-run, --no-commit,
# a run with nothing to do). Initialised here for the reason STAGED_DEL is: under `set -u` an unset
# read down there is not an empty string, it is a fatal error in the reporting tail of a sync that
# has already written every file it was asked to.
IN_PROGRESS_ARM=0
# Spec 007ax. The stamp is the second way this sync has something of its own to commit, and it used
# to be the missing one. `$STAMP_REWRITTEN` is 1 only when the stamp gained news (see the stamp
# block above), so a `--force` run that changed nothing still falls through here exactly as before.
#
# Nothing INSIDE this block needed changing to accept the new case, which is the sign the case was
# always meant to be here: stage_all already passes "$STAMP_REL" to `git add` unconditionally,
# recount_staged already excludes the stamp from N_UPD/N_NEW, and the `(stamp advance)` arm below
# already tests `git diff --cached` for the stamp before committing. That arm has produced three
# commits in this project's history and was simply unreachable for a run that wrote no file.
if [ "$DO_COMMIT" -eq 1 ] && { [ $((N_WROTE + N_ADDED)) -gt 0 ] || [ "$STAMP_REWRITTEN" -eq 1 ]; }; then
  # Spec 007be. Reached only under --ignore-in-progress now: without it the gate above the copy
  # loop turned this run into a report and exited long before here. The arm and everything 007bd
  # built on it are unchanged — the flag is what reaches them.
  if operation_in_progress; then
    # Spec 007bd. This arm no longer stages, and that reverses spec 007ax's FR-007ax-08, which
    # staged deliberately so that "the developer finishes the rebase and finds the stamp already in
    # the index". Measured (007bd research.md M1), they do not. What they find depends on which kind
    # of stop they are in, and the two answers are opposites:
    #
    #   conflict stop, resolved   `git rebase --continue` exits 0 and COMMITS the sync's staged
    #   (the common one)          files into the DEVELOPER's commit, under the DEVELOPER's message
    #                             — pushed under their name where there is an upstream. Measured on
    #                             rebase, on `merge --continue`, and on `cherry-pick --continue`,
    #                             which put a template file straight onto main.
    #
    #   --exec / edit / break     exits 1, "you have staged changes in your working tree", and the
    #                             rebase does not advance. git's own advice then points at
    #                             `git commit --amend` — i.e. at the case above.
    #
    # So staging here was never the favour it reads as. It is spec 007bb's defect mirrored: there
    # the sync's commit carried the developer's work, here the developer's commit carries the sync's.
    #
    # And not staging costs nothing new (M2/M3). A tracked file this sync rewrites blocks
    # `--continue` whether or not it is staged, because the WRITE blocks it and the write happens on
    # this arm either way — the control measured that any dirty tracked file does the same with no
    # sync involved at all. Staging does not remove that block. It removes the visibility of it, by
    # turning a stopped rebase into a silent absorption in exactly the case where the developer is
    # least likely to be watching their index.
    #
    # One note now, not two, because there is one outcome: the two branches that were here existed
    # only to report which class `stage_all` had landed in, and nothing is staged to land.
    IN_PROGRESS_ARM=1
    COMMIT_NOTE="commit skipped (rebase/merge in progress) — nothing staged, nothing committed"
  else
    stage_all

    # Spec 007av. The fatal class first, because everything below it reads an index this run did
    # not build. Refusing the COMMIT is not refusing the sync: every file is written, the report
    # still prints, the script still exits 0, and the SessionStart hook's contract — a template
    # problem never stops a session starting — is untouched.
    #
    # This is the one place in the script where a refusal genuinely prevents damage rather than
    # hiding it. 007au's revert block reports instead of refusing precisely because by the time it
    # runs the overwrite is already on disk. Here the commit IS the damage: it takes an index
    # somebody else staged, names it a sync, and pushes it.
    #
    # SYNC_COMMIT stays empty, which is what already gates the 007at verification obligation (no
    # commit, nothing to verify) and what keeps the 007au revert block's range at HEAD, correctly,
    # since HEAD did not move. Both fall out with no code of their own.
    if [ "$STAGE_RC" -ge 2 ]; then
      COMMIT_NOTE="NOT committed — git staged nothing"
      MSG=""
    # Three outcomes, decided by what git recorded rather than by what was written.
    elif [ $((N_UPD + N_NEW)) -eq 0 ]; then
      # Nothing but possibly the stamp. Committing the stamp alone is still right
      # when the template SHA moved — a stale stamp makes the next run re-sync from
      # scratch — but it is a SHA advance, not a file count. This is what 7c4a6a9
      # and 9b72263 are, and they both claim "1 updated" over an empty diff.
      if [ -n "$STAGED_STAMP" ]; then
        MSG="chore(sync): template $TEMPLATE_SHA — 0 updated, 0 added (stamp advance)"
      else
        COMMIT_NOTE="nothing to commit — no file changed"
        MSG=""
      fi
    else
      MSG="chore(sync): template $TEMPLATE_SHA — $N_UPD updated, $N_NEW added"
    fi
    # Spec 007bb. The pathspec. `git commit` with none of it records the INDEX, which is the sync's
    # staging plus whatever the developer left there — see owned_by_sync. $COMMIT_PATHS is
    # word-split deliberately, exactly like the `git add` above it and safe on the same guarantee.
    #
    # The emptiness test is not defensive padding: an empty pathspec is not "commit nothing", it is
    # `git commit` with no pathspec at all — the defect, reached by accident. Whenever $MSG is
    # non-empty one of $STAGED_ALL or $STAGED_STAMP is too, so this can only fire if that ever
    # stops being true, and then it refuses instead of committing a stranger.
    if [ -n "$MSG" ] && [ -n "$COMMIT_PATHS" ] \
       && git -C "$PROJECT_ROOT" commit -q -m "$MSG" -m "Deterministic template sync (scripts/rules/docs/agents + core-hook wiring).
Locally-modified files skipped: $N_SKIP. CLAUDE.md and project-specific settings untouched — run /project-update for those." -- $COMMIT_PATHS 2>/dev/null; then
      SHORT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)
      COMMIT_NOTE="committed $SHORT"
      SYNC_COMMIT="$SHORT"
      BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
      if git -C "$PROJECT_ROOT" rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
        if git -C "$PROJECT_ROOT" push -q origin "$BRANCH" 2>/dev/null; then
          COMMIT_NOTE="$COMMIT_NOTE, pushed to $BRANCH"
          SYNC_PUSHED=yes
        else
          COMMIT_NOTE="$COMMIT_NOTE, push FAILED (offline or rejected)"
        fi
      else
        COMMIT_NOTE="$COMMIT_NOTE (no upstream — not pushed)"
      fi
    elif [ -n "$MSG" ]; then
      COMMIT_NOTE="commit failed — files left staged"
    fi
  fi
fi

# The headline is what the repository recorded. When nothing was staged (--no-commit,
# or a run with nothing to do) there is no index to read, so fall back to the write
# counts and say plainly that they describe writes — an unlabelled number is exactly
# the ambiguity this spec exists to remove.
if [ "$RECONCILED" -eq 1 ]; then
  SUMMARY="template $TEMPLATE_SHA → $N_UPD updated, $N_NEW added, $N_SKIP skipped (locally modified)"
else
  SUMMARY="template $TEMPLATE_SHA → $N_WROTE written, $N_ADDED created, $N_SKIP skipped (locally modified)"
  # Nothing was staged, so there is no index to measure. The files are on disk either way and
  # the working tree answers the same question — labelled by the "written/created" wording this
  # arm already carries, which is what keeps it from claiming the repository recorded anything.
  UNSTAGED_NUMSTAT=$(numstat)
  MOVED_INS=$(sum_numstat "$UNSTAGED_NUMSTAT" 1)
  MOVED_DEL=$(sum_numstat "$UNSTAGED_NUMSTAT" 2)
fi
# Spec 007au. `2 updated, 0 added` was the whole truth about commit 5f376d6, and the whole
# truth was that it removed 59 lines from this file and added none. The counts answer "how
# many", never "which way", and the difference between those two questions is the difference
# between a template release and an amputation.
#
# Silent at zero rather than `+0/-0`: a stamp advance and a no-op run both land here, and a
# movement figure over an empty diff is the kind of true-but-empty line readers learn to skip.
if [ "$((MOVED_INS + MOVED_DEL))" -gt 0 ]; then
  SUMMARY="$SUMMARY · +$MOVED_INS/-$MOVED_DEL lines"
fi
[ -n "$HOOKS_NOTE" ] && SUMMARY="$SUMMARY · $HOOKS_NOTE"
SUMMARY="$SUMMARY · $COMMIT_NOTE"
tell "[synced] $SUMMARY"

# ------------------------------------------------------- what git made of the staging (spec 007av)
# Silent on exit 0, which is the overwhelmingly common case and the whole discipline of this
# reporting tail: the text is forwarded verbatim into every session start, so a block that speaks
# when there is nothing to report is a regression of its own.
#
# Two very different sentences, because the two non-zero classes are opposites (M0). Collapsing
# them into one "git add failed" line would be the same mistake as testing `$?` as a boolean, just
# moved into the prose.
#
# git's own text is passed through and never parsed. It is LOCALIZED — on the machine this was
# measured on it arrives in Swedish (M1) — so a branch reading it would make the sync behave
# differently depending on the developer's locale. The exit code decides; the sentence informs.
#
# This does not restate the 007an [written] block. That one answers "which written paths left no
# trace in the index"; this answers "did git accept the staging at all". On a fatal both fire and
# they say different things — [written] can only reach its deliberately-vague `not recorded`
# bucket, which is exactly the answer the exit code makes precise.
if [ "$STAGE_RC" -eq 1 ]; then
  tell "[stage] git refused a path but staged everything else — the commit above is complete."
  [ -n "$STAGE_ERR" ] && tell "        git said: $STAGE_ERR"
  tell "        A path the template ships that this project's .gitignore covers. Fix it in the"
  tell "        template — forcing it past the ignore rule would commit what the project declined."
elif [ "$STAGE_RC" -ge 2 ]; then
  tell "[stage] git staged NOTHING (exit $STAGE_RC) — no commit was made and nothing was pushed."
  [ -n "$STAGE_ERR" ] && tell "        git said: $STAGE_ERR"
  tell "        The files this sync wrote are on disk and uncommitted; the index was left as found."
  tell "        Usually a held .git/index.lock, or a path that matches no file. Check \`git status\`"
  tell "        and commit by hand. This sync will not: the index it would have committed is not"
  tell "        one it built."
fi

# The bound shared by every block below that renders file names — [held] here, [changed] further
# down. Hoisted out of [changed] by spec 007bb, which added the earlier consumer; sanitised once
# rather than at each, because a fat-fingered override must not become `[: xyz: integer expression
# expected` inside the very message the bound exists to make readable. 0 is a real answer — a
# project that wants the old counts-only message sets it and gets exactly that.
NAME_LIMIT="${TEMPLATE_AUTOSYNC_NAME_LIMIT:-20}"
case "$NAME_LIMIT" in ''|*[!0-9]*) NAME_LIMIT=20 ;; esac

# ------------------------------------------ what the commit deliberately left (spec 007bb)
# The other half of the pathspec. A sync that quietly declines to carry something is one step from
# a sync that quietly loses it, so the paths the commit walked past are named rather than merely
# not-committed.
#
# Two arms, and they reach the same sentence from opposite directions. After a commit, every path
# the sync owned has just left the index, so what remains is the strangers. On spec 007bd's
# rebase/merge arm the sync staged nothing at all, so what is in the index is the strangers because
# nothing else was ever put there. Either way the block's claim — already staged, not this sync's,
# left untouched — is literally true, which is why it needed a wider gate rather than new wording.
#
# Not the other two arms, and the reason differs for each. On --no-commit the developer has asked
# this script to leave git alone, and a block reporting on their index is the script not doing that.
# On 007av's fatal class [stage] already says "the index was left as found"; a second block would
# restate it one paragraph later, and this text is forwarded verbatim into every session start.
#
# The index is read AND subtracted from, not merely read — and on BOTH arms the subtraction is a
# no-op, for opposite reasons: after a commit the sync's paths have already left the index, and on
# the rebase arm they were never put in it. That is the point rather than an argument for dropping
# it: the block is correct because of what it asks, not because of where it sits, which is what let
# spec 007bd reuse it by widening one gate. A block that is right for the wrong reason stops being
# right the first time somebody moves it — and this one has now been moved.
#
# The wording is deliberate. NOT "skipped", NOT "ignored" — both read as loss, and nothing was
# lost: the paths are exactly where the developer put them. And no instruction, because staging
# something and leaving it there is a thing developers do on purpose.
if [ -n "$SYNC_COMMIT" ] || [ "$IN_PROGRESS_ARM" -eq 1 ]; then
  HELD=$(git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null \
    | grep -v -x -F "$STAMP_REL" | owned_by_sync drop)
  N_HELD=$(printf '%s\n' "$HELD" | grep -c .)
  if [ "$N_HELD" -gt 0 ]; then
    tell "[held] $N_HELD path(s) were already staged and are not this sync's — left staged, untouched:"
    printf '%s\n' "$HELD" | head -n "$NAME_LIMIT" | while IFS= read -r _h; do
      tell "       $_h"
    done
    # Counted from the rendered list and naming the cap, for the reason the [changed] block records:
    # the bound is the whole point of the line, and it is true at any limit.
    if [ "$N_HELD" -gt "$NAME_LIMIT" ]; then
      tell "       … and $((N_HELD - NAME_LIMIT)) more, not named — capped at $NAME_LIMIT (TEMPLATE_AUTOSYNC_NAME_LIMIT)"
    fi
  fi
fi

# ------------------------------------ where this sync's own work went instead (spec 007bd)
# [held] above says what the sync did not touch. This says where its own writes are, and it exists
# because the arm's behaviour CHANGED: a developer who knew the old one finds nothing staged and has
# no way to tell a deliberate decision from a regression. Silence is the wrong answer to a reversal.
#
# No count and no file list. [changed] already names every path this sync wrote, and repeating them
# is the same text twice in a message that goes into every session start — and a stamp-advance run
# mid-rebase writes no file at all, so a list here would render empty on precisely the arm that most
# needs the explanation.
#
# The instruction is deliberate, and it is the opposite call from [held]'s — which correctly offers
# none, because those paths are the developer's own deliberate act and need no advice. These are the
# sync's, and they can block the developer's own `git rebase --continue`. Telling them the one
# command that clears it (verified mid-rebase and mid-conflict, research.md M4) is this script
# cleaning up after itself in words, which is the only way it is allowed to clean up here at all.
if [ "$IN_PROGRESS_ARM" -eq 1 ]; then
  tell "[mid-rebase] a rebase/merge is in progress, so this sync staged nothing and committed nothing."
  tell "       Its files are written to the working tree only — \`git status\` shows them."
  tell "       Staging them would fold them into your next \`git rebase --continue\` commit, which is"
  tell "       not this script's call to make. \`git stash push -- <path>\` if a dirty tree blocks it."
fi

# ------------------------------------------ the obligation this sync leaves (spec 007at)
# What the sync just did is rewrite this project's enforcement machinery, commit it and
# push it, on the strength of an exit code that means "the copy loop finished". Twice in
# two days that shipped a red main: 0a30a77 took seven of spec 007ak's tests down and the
# next spec ran a full pipeline on top of them and reported green, and 5d9234b reverted
# spec 007as under the message "3 updated, 0 added".
#
# It cannot check. The bound is 120 s from a hook whose contract is that a template
# problem never stops a session starting, and a real suite is tens of seconds warm and a
# build cold. And it must not: the declared command is a string in a repository file, and
# running one unattended is a trust boundary this deliberately does not cross
# (scripts/template-sync-verify.sh is the only thing that executes it, on a human's
# explicit invocation).
#
# So it records what it has not checked, and scripts/template-sync-verify-hook.sh says so
# at every session start until somebody discharges it.
#
# In .git/ rather than under .claude/, because .gitignore is not in the synced set: a
# .claude/ marker would be ignored in the one project whose ignore file was edited and
# untracked forever in the other thirty-odd.
#
# A stamp advance is not a rewrite. When the template SHA moves over bytes the project
# already had, the commit carries `.claude/.template-sync` and nothing else — there is no
# code to verify, and an obligation raised over one is exactly the line readers learn to
# skip. Asked of git rather than of $WROTE and $ADDED, for spec 007an's reason: those are
# the sync's record of its own activity, not of what the repository recorded.
VERIFY_CARRIED=""
if [ -n "$SYNC_COMMIT" ]; then
  VERIFY_CARRIED=$(git -C "$PROJECT_ROOT" diff-tree --no-commit-id --name-only -r --root HEAD 2>/dev/null \
    | grep -v -x -F "$STAMP_REL")
  [ -n "$VERIFY_CARRIED" ] || SYNC_COMMIT=""
fi

if [ -n "$SYNC_COMMIT" ]; then
  VERIFY_MARKER="$PROJECT_ROOT/.git/template-sync-unverified"

  # Supersede, never stack. One marker, newest SHA first, so "how many are outstanding" is
  # a read rather than a parse — and so a `result=failed` recorded against bytes this run
  # has just rewritten is dropped rather than carried forward as a failure nobody can
  # reproduce.
  PREV_COMMITS=""
  [ -r "$VERIFY_MARKER" ] && PREV_COMMITS=$(sed -n 's/^commits=//p' "$VERIFY_MARKER" 2>/dev/null | head -1)
  ALL_COMMITS="$SYNC_COMMIT"
  for _c in $PREV_COMMITS; do
    case " $ALL_COMMITS " in *" $_c "*) ;; *) ALL_COMMITS="$ALL_COMMITS $_c" ;; esac
  done

  # Asked of git rather than assembled from $WROTE and $ADDED. Spec 007an's whole finding
  # is that those two are the sync's record of its own activity and not what the
  # repository recorded, and a reminder built from the wrong one would name files the
  # commit does not contain.
  {
    printf '# Template sync commits this branch has not been verified against (spec 007at).\n'
    printf '# Written by scripts/template-autosync.sh · discharged by scripts/template-sync-verify.sh\n'
    printf 'commit=%s\n' "$SYNC_COMMIT"
    printf 'commits=%s\n' "$ALL_COMMITS"
    printf 'template=%s\n' "$TEMPLATE_SHA"
    printf 'synced=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'pushed=%s\n' "$SYNC_PUSHED"
    printf 'result=pending\n'
    # --root (in VERIFY_CARRIED above), because a project's FIRST sync commit can be the
    # repository's root commit and diff-tree says nothing at all about one without it —
    # silently, on exactly the run that seeds a project and where knowing what arrived
    # matters most. The stamp is filtered out there too: it is in every sync commit and
    # tells a reader nothing.
    printf '%s\n' "$VERIFY_CARRIED" | sed 's/^/file /'
  } > "$VERIFY_MARKER.tmp" 2>/dev/null \
    && mv -f "$VERIFY_MARKER.tmp" "$VERIFY_MARKER" 2>/dev/null \
    || rm -f "$VERIFY_MARKER.tmp" 2>/dev/null   # an unwritable .git/ is not worth a word: the
                                                # sync's own work succeeded, and bookkeeping
                                                # about it must not make a session worse.

  VERIFY_CMD=""
  VERIFY_DECL="$PROJECT_ROOT/.claude/.template-sync-verify"
  [ -r "$VERIFY_DECL" ] && VERIFY_CMD=$(grep -v '^[[:space:]]*#' "$VERIFY_DECL" 2>/dev/null \
    | grep -v '^[[:space:]]*$' | head -1)

  tell "[verify] $SYNC_COMMIT is unverified — nothing has checked this project since."
  if [ -n "$VERIFY_CMD" ]; then
    tell "         run scripts/template-sync-verify.sh   ($VERIFY_CMD)"
  else
    # Spec 007ba. "Declare a command" was the whole message here, and 41 of the 42 projects
    # carrying this obligation could not answer it — so it was a line to skip, at every session
    # start, forever. Derive one from the project's own manifests instead, and when that is not
    # possible say what WAS found, so the chore is a copy-paste rather than an investigation.
    #
    # Derived, never written: .claude/.template-sync-verify keeps its single meaning — a human
    # chose this. See detect-verify-command.sh's header.
    VERIFY_DERIVED=""
    VERIFY_FROM=""
    if [ -f "$PROJECT_ROOT/scripts/detect-verify-command.sh" ]; then
      # Once, then sliced — the search is not cheap enough to run twice for two strings.
      VERIFY_DETECTED=$(bash "$PROJECT_ROOT/scripts/detect-verify-command.sh" "$PROJECT_ROOT" 2>/dev/null)
      VERIFY_DERIVED=$(printf '%s\n' "$VERIFY_DETECTED" | sed -n '1p')
      VERIFY_FROM=$(printf '%s\n' "$VERIFY_DETECTED" | sed -n '2p')
    fi

    if [ -n "$VERIFY_DERIVED" ]; then
      tell "         no declaration — derived from this project: $VERIFY_DERIVED"
      [ -n "$VERIFY_FROM" ] && tell "         ($VERIFY_FROM)"
      tell "         run scripts/template-sync-verify.sh, or declare your own in"
      tell "         .claude/.template-sync-verify"
    else
      VERIFY_CANDIDATES=""
      [ -f "$PROJECT_ROOT/scripts/detect-verify-command.sh" ] && VERIFY_CANDIDATES=$(bash \
        "$PROJECT_ROOT/scripts/detect-verify-command.sh" "$PROJECT_ROOT" --candidates 2>/dev/null | head -5)
      if [ -n "$VERIFY_CANDIDATES" ]; then
        tell "         no declaration, and more than one thing this could mean:"
        printf '%s\n' "$VERIFY_CANDIDATES" | while IFS= read -r _c; do
          [ -n "$_c" ] && tell "           $_c"
        done
        tell "         put the one you mean in .claude/.template-sync-verify"
      else
        tell "         no declaration, and no test project or test script was found."
        tell "         Put the command that proves this project works in"
        tell "         .claude/.template-sync-verify"
      fi
    fi
  fi
fi

# ------------------------------------------------------- what moved (spec 007ak)
# The counts above answer "did anything move". They cannot answer "which of MY rules
# and guards moved", which is the question a session that just had its enforcement
# layer rewritten underneath it actually has — and until this block that answer was
# recoverable nowhere. A writing run printed no per-file line in ANY mode: the only
# per-file listing lives inside --check --dry-run, which exits before the copy loop
# touches anything, so dropping --quiet from the SessionStart hook would have bought
# three lines of machinery chatter and zero names (007ak research.md M0, M2). The
# fallback of pointing at this sync's own commit is worse than it looks: five of this
# project's nine sync commits do not contain a file for every unit they counted, and
# the most recent one counted `scripts/spec_active.py` — which all three BLOCKING
# guards resolve the active spec through — while the commit shows only a stamp,
# because the template had caught up with bytes the project already had (M6).
#
# Bounded, because a first sync is 93 files / 4.5 KB against a largest-ever release of
# 19 (M4, M5) and this text is forwarded verbatim into a session's context. Ordered by
# what changed the session's own behaviour, because under a bound the order is what
# decides which names survive.

if [ "$NAME_LIMIT" -gt 0 ]; then
  # Spec 007au, the half 007ar left open. `fold_helper_writes` folds the helpers' `+ name` AND
  # `- name` lines into $WROTE — correctly, because `git add` must see a vanished path to stage
  # its removal — so $WROTE carries no direction and this block used to call every one of them
  # an `update`, deletions included. The truth is in STAGED_DEL, which recount_staged already
  # computes and until now spent only on STAGED_ALL.
  #
  # When nothing was staged (--no-commit, --dry-run) STAGED_DEL is empty, no row can match, and
  # every path keeps `update`. That is the right answer rather than a missing branch — the
  # direction genuinely is not knowable there, and guessing it from $WROTE is the defect.
  #
  # Space-delimited with a leading AND trailing space, so `index()` below cannot let
  # `scripts/graphify-a.sh` match `scripts/graphify-ab.sh` — the same idiom, and the same trap,
  # as the eight $WROTE-append sites. Safe on the delimiter because every path reaching $WROTE
  # came through the sync's own deliberately narrow basename rule (no `/`, no space) or a
  # template-relative path that has neither.
  #
  # The verb is decided in awk rather than in the shell loop for a hard reason: bash 3.2 — which
  # `#!/bin/bash` still selects on macOS — cannot parse a `case` whose pattern begins with a
  # quote when it sits inside `$( )`, and fails at parse time, which would take the whole script
  # down rather than one block. The [written] reconciliation below uses the shell `case` idiom
  # safely only because it is NOT inside a command substitution.
  DELETED_LOOKUP=" $(printf '%s' "$STAGED_DEL" | tr '\n' ' ') "
  MOVED=$(
    { for _f in $WROTE; do printf 'update\t%s\n' "$_f"; done
      for _f in $ADDED;  do printf 'add\t%s\n'    "$_f"; done
    } | awk -F'\t' -v deleted="$DELETED_LOOKUP" '{
          p = $2
          if ($1 == "update" && index(deleted, " " p " ") > 0) $1 = "delete"
          if (p == ".claude/settings.json")  r = 0   # the hook wiring itself
          else if (p ~ /^\.claude\/rules\//) r = 1   # the BLOCKING rules
          else if (p ~ /^scripts\//)          r = 2   # the guards those rules cite
          else                                r = 3
          printf "%d\t%s\t%s\n", r, p, $1
        }' \
      | LC_ALL=C sort -t"$(printf '\t')" -k1,1n -k2,2 \
      | awk -F'\t' '{ printf "%-7s%s\n", $3, $2 }'
  )
  # LC_ALL=C so the alphabetical half of the order does not depend on whose machine
  # ran the sync; %-7s reproduces the two column widths --check --dry-run prints,
  # rather than spelling either verb twice.
  MOVED_N=$(printf '%s\n' "$MOVED" | grep -c .)
  if [ "$MOVED_N" -gt 0 ]; then
    tell "[changed] files this sync wrote, enforcement first:"
    printf '%s\n' "$MOVED" | head -n "$NAME_LIMIT" | while IFS= read -r _line; do
      tell "          $_line"
    done
    # The remainder is counted from the RENDERED list, never from N_WROTE + N_ADDED:
    # those two agreeing is exactly what M6 shows cannot be assumed. It names the cap
    # rather than an artefact — the cap is the whole reason the line exists, and it is
    # true at any limit, where "this is a bulk sync" would be a guess once somebody
    # lowers the bound.
    if [ "$MOVED_N" -gt "$NAME_LIMIT" ]; then
      tell "          … and $((MOVED_N - NAME_LIMIT)) more, not named — capped at $NAME_LIMIT (TEMPLATE_AUTOSYNC_NAME_LIMIT)"
    fi
  fi
fi

# ------------------------------------------------------- CORE going backwards (spec 007au)
# [changed] says what moved. This says which of it moved BACKWARDS, and only for the files
# the template owns outright.
#
# Where the line sits was the open question on the register row, and it is settled by
# measurement rather than by taste (research.md M3/M4). Across every sync commit this project
# has, "net-negative on a CORE file" fires seven times and is right twice — 33%. Magnitude
# does not save it: the largest false positive is -41, bigger than the -35 true positive.
# Ratio does not save it either, and is in fact inverted — the true positive 5d9234b is
# +10/-45 (0.22) while the false positive 65228d9 is +9/-50 (0.18), so every threshold that
# catches the regression catches the refactor first. A 33%-precision warning shipped into
# ~34 projects at every session start is the line readers learn to skip.
#
# What DOES separate them: a template release writes content the project has never held; a
# revert writes content it held before. Tested against all seven events, that flags both
# regressions, names the commit being restored to, and goes silent on all three legitimate
# refactors. Zero false positives.
#
# Two stages, in this order because the precise test costs 68 ms per file and must not run
# nineteen times on a bulk sync. Net-negative is a poor verdict but a perfect pre-filter — it
# has full recall over what stage 2 cares about and costs nothing, being read out of a
# --numstat already taken. On 15 of 17 measured syncs stage 2 never runs at all.
#
# Reports. Does not refuse, does not revert, does not touch the exit code. By the time this
# line is reached the overwrite is on disk AND committed, so a refusal here would not prevent
# the damage — it would only hide it, and leave a dirty CORE file behind, which is the state
# spec 007ao exists to keep everyone out of. The commit is what makes it revertable; this
# block is what makes it noticed.
# This block renders AFTER the commit block, so when the sync committed, HEAD *is* the sync's own
# commit and its post-image is the very content being asked about — the search would match itself
# on its first line and name the sync as the thing being reverted to. Measured on a fixture: it
# reported `chore(sync): template e59ebd34e2d5`, i.e. itself, which is useless and confidently
# phrased. So the history searched is the history predating this commit.
#
# An empty range means the sync's commit is the repository's root: no earlier content exists for
# anything to be restored to, so the question does not arise and the block is skipped whole.
REVERT_RANGE="HEAD"
if [ -n "$SYNC_COMMIT" ]; then
  if git -C "$PROJECT_ROOT" rev-parse -q --verify "$SYNC_COMMIT^" >/dev/null 2>&1; then
    REVERT_RANGE="$SYNC_COMMIT^"
  else
    REVERT_RANGE=""
  fi
fi

if [ "$RECONCILED" -eq 1 ] && [ -n "$STAGED_NUMSTAT" ] && [ -n "$REVERT_RANGE" ]; then
  REVERTED=""
  # Stage 1. Field 3 is the path; a rename renders `old => new` there and is dropped by the
  # basename split below rather than being asked about, which is correct — the sync does not
  # rename, so anything of that shape is drift and not a revert.
  CANDIDATES=$(printf '%s\n' "$STAGED_NUMSTAT" \
    | awk -F'\t' '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && ($1 - $2) < 0 { print $3 }')
  for _p in $CANDIDATES; do
    # The same classification --is-core uses, asked of the same lists, including its refusal
    # of nested paths. A second definition of CORE living here would drift from that one the
    # first time either changed — and it nearly did: `.claude/settings.json` is overwritten by
    # this sync but is NOT in either CORE list, so an earlier draft that special-cased it here
    # would have been inventing membership the rest of the script disagrees with.
    case "$_p" in
      scripts/*/*|.claude/rules/*/*) continue ;;
      scripts/*)                     _class=scripts ;;
      .claude/rules/*)               _class=rules ;;
      *)                             continue ;;
    esac
    is_core "${_p##*/}" "$_class" || continue

    # Stage 2. The blob the sync is about to commit, against every blob this path has held.
    _new=$(git -C "$PROJECT_ROOT" rev-parse ":$_p" 2>/dev/null) || continue
    [ -n "$_new" ] || continue

    # One process for the whole history of one path. Field 4 of a --raw line is the POST-image
    # blob — the content the path HELD AS OF that commit, which is exactly what "restored to"
    # has to name. Field 3, the pre-image, is the content it held going *into* the commit, so
    # matching on it reports the commit that DESTROYED that content rather than the one that
    # had it: a smoke test on a two-commit fixture named "project v2 (the local fix)", the
    # version being amputated, as the thing being restored to. Exactly backwards, and it reads
    # plausibly enough to ship.
    #
    # This cannot false-positive on a healthy file: _new is the STAGED blob, which by
    # construction differs from HEAD's (git staged a change), so the current content cannot
    # match itself.
    _hit=$(git -C "$PROJECT_ROOT" log --format='commit %H' --raw --no-abbrev "$REVERT_RANGE" -- "$_p" 2>/dev/null \
      | awk -v want="$_new" '
          /^commit / { c = $2; next }
          /^:/       { if ($4 == want) { print c; exit } }')
    [ -n "$_hit" ] || continue

    _mv=$(printf '%s\n' "$STAGED_NUMSTAT" | awk -F'\t' -v p="$_p" '$3 == p { printf "+%s/-%s", $1, $2; exit }')
    _sub=$(git -C "$PROJECT_ROOT" log -1 --format='%s' "$_hit" 2>/dev/null | cut -c1-60)
    _short=$(git -C "$PROJECT_ROOT" rev-parse --short "$_hit" 2>/dev/null)
    REVERTED="$REVERTED$_p — $_mv lines, restored to $_short (\"$_sub\")
"
  done

  # Silent when nothing matched, which is the common case and the whole point: this text is
  # forwarded verbatim into every session start.
  if [ -n "$REVERTED" ]; then
    tell "[reverted] CORE file(s) given content this project already had — the template may be undoing local work:"
    printf '%s' "$REVERTED" | while IFS= read -r _line; do
      [ -n "$_line" ] && tell "           $_line"
    done
    tell "           Check before building on it: \`git show HEAD -- <path>\`, and land the fix in the template, not here."
  fi
fi

# Spec 007az. After [reverted], not before: that block says what this sync DESTROYED, this one
# says what the project still owes the template, and destroyed-then-owed is the order the
# developer has to act in.
#
# They overlap on exactly one shape — a net-negative CORE overwrite whose prior blob is in the
# project's history — and there the two lines say different things about the same file: one names
# the commit to recover from, the other names where the fix has to go.
#
# Everywhere else this block is carrying cases [reverted] cannot reach, and the boundary is not
# where it first looks. That block's stage 1 keeps only overwrites that are NET-NEGATIVE in lines,
# which is the local-change-ADDED-lines case. The two it drops before stage 2 ever runs are the
# local change that REMOVED lines (restoring them is net-positive) and the one that REPLACED them
# 1:1 (net zero). Both measured: [reverted] silent, this block fires (spec 007az research.md M7).
report_owed "$OWED"

# Spec 007an. The gap between what this sync wrote and what the repository recorded
# is not a presentation problem to be smoothed over by picking the nicer number —
# it is the signal. Silence when they agree: this text is forwarded verbatim into
# every session start, and a block that fires when there is nothing to report is a
# regression of its own.
if [ "$RECONCILED" -eq 1 ] && [ -n "$WRITTEN_ALL" ]; then
  UNRECORDED=""
  for _w in $WRITTEN_ALL; do
    case "
$STAGED_ALL
" in *"
$_w
"*) ;; *) UNRECORDED="$UNRECORDED $_w" ;; esac
  done
  N_UNREC=$(printf '%s' "$UNRECORDED" | tr ' ' '\n' | grep -c .)
  if [ "$N_UNREC" -gt 0 ]; then
    tell "[written] $N_UNREC file(s) were written but the repository recorded no change:"
    for _w in $UNRECORDED; do tell "          $_w — $(unrecorded_reason "$_w")"; done
  fi
fi
# ------------------------------------------ the template's third verb (spec 007aw)
# Placed here, beside [manual], because these are the two blocks about what the sync deliberately
# did NOT touch — everything above them reports what it did.
#
# Called [orphaned] and not [retracted] on purpose: [reverted] already exists three blocks up and
# means something else entirely (a CORE file given content this project already had). Two tags one
# letter apart, in the same screen of session-start text, describing different conditions, is a
# readability defect shipped deliberately. [orphaned] also names the right subject — the state of
# the file sitting in this project, rather than the template's action.
#
# LOUD ONCE, QUIET AFTER, NEVER SILENT. The full block fires on the run where there is genuinely
# news; a standing orphan costs one line. Both halves of that are deliberate. Silence is what let
# the .pyc run for months, and a full block repeating every session across ~34 projects is how a
# reader learns to skip the place the next real finding will appear — the failure 007au measured
# and rejected by name at this very same 33% precision.
if [ "$N_ORPHAN_NEW" -gt 0 ]; then
  tell "[orphaned] $N_ORPHAN_NEW file(s) this sync once wrote that the template no longer ships:"
  for _o in $ORPHAN_NEW; do tell "           $_o"; done
  tell "           Nothing was deleted. Remove what this project does not need; each line clears"
  tell "           itself when its file goes. Recorded in .claude/.template-sync."
fi
if [ "$N_ORPHAN_STANDING" -gt 0 ]; then
  tell "[orphaned] $N_ORPHAN_STANDING standing orphan(s) from earlier syncs — named in .claude/.template-sync"
fi

# Everything here is forwarded verbatim into a session by template-autosync-hook.sh,
# which is why a file that is SUPPOSED to differ must not appear: the false line
# would arrive bundled with the real news, on the one occasion somebody is reading.
if [ "$N_SKIP" -gt 0 ]; then
  tell "[manual] files that differ from the template and are left alone:"
  for x in $SKIPPED;     do tell "         $x — merge with /project-update, or record it with --accept-local"; done
  for x in $LOCAL_MOVED; do tell "         $x — the local copy changed since it was accepted as intentional"; done
  for x in $TMPL_MOVED;  do tell "         $x — the template changed under an accepted local difference"; done
fi

# Spec 007bf. Last, and after the commit block, which is what makes it a self-check rather than
# another opinion: on a healthy sync the files were just committed, so the detector re-reads HEAD,
# finds nothing, and this is silent by construction. When it is NOT silent here, the run that
# stranded the files is the run that says so — instead of the developer learning it never, or once,
# from 007av's [stage] block scrolling past in a session they were not reading.
report_stranded "$(stranded_writes)"
exit 0
