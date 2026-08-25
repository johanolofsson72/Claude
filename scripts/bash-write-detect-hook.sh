#!/usr/bin/env bash
# PostToolUse detector on Bash: reports source-file writes the pipeline guard would have denied, no matter
# how the command spelled them (row H7b).
#
# WHY A SECOND LAYER
# ------------------
# scripts/bash-write-guard-hook.sh reads the command string, and a string parser has a hard ceiling: it
# cannot see a write performed inside `python3 - <<PY`, behind `eval`, through `xargs`, or via a path built
# from a variable at runtime. Shipping only that layer would be partial coverage that LOOKS complete —
# which is the failure class this register row was carved out of.
#
# This layer does not read the command. It compares the filesystem against a marker stamped before the
# command ran, and asks the three pipeline guards about whatever actually changed. How the write was
# spelled is then irrelevant, which is the whole point.
#
# PREVENTION vs DETECTION — stated plainly
# ----------------------------------------
# This runs AFTER the tool. It cannot stop the write; it makes the write impossible to make silently. That
# is a real downgrade from the pre-layer and it is why both exist: the pre-layer prevents the common
# shapes, this one guarantees nothing gets through unnoticed.
#
# THE ESCAPE HATCH (FR-008)
# -------------------------
# A hook with no escape converts a helpful gate into a hostage situation, and the rational response to that
# is to delete the hook — which costs the whole feature (the run-gates-stop-hook.sh lesson). So: it blocks
# ONCE per distinct finding. .claude/.bash-write-blocked holds the file set of the last block; the same set
# again is silent, a different set arms it again.
#
# Note the deliberate separation from .bash-write-marker: the marker is a TIMESTAMP that is re-stamped on
# every single Bash call, so an escape hatch that lived in it would forget it had ever blocked. Two facts,
# two files.
#
# EXEMPTIONS (FR-009) — argued, never silent. Same idiom as EXCLUDED in scripts/run-gates.sh: a reason a
# reviewer can contest is fine, an unexplained omission is not.
#
#   git checkout|switch|restore|stash|reset|clean|pull|merge|rebase
#       These move the tree between states that were already authored, and every state they can move to was
#       authored under this gate. Gating them would mean a branch switch reports every file it touched.
#
#   NOT exempt: git apply | git am | git cherry-pick | git revert
#       These introduce content that may never have passed the gate at all. `git apply` in particular is
#       "write these files" wearing a git verb.
#
# SECRETS (FR-015): the command string is never echoed. Only derived file paths appear in output.
#
# HOW IT REPORTS (FR-016) — to the developer, not only to the model
# ------------------------------------------------------------------
# It emits JSON with BOTH `decision: block` + `reason` (which the model must answer) and
# `systemMessage` (which the developer sees in the terminal). The first draft used `exit 2`, whose stderr
# reaches the model alone — and a detection only the model sees is a detection that can be summarised
# away, which is the same silence this row was carved out of, one layer up.
#
# Exit: always 0. The verdict is the JSON on stdout, per the PostToolUse contract.
#
# Covers: SC-1438 SC-1439 SC-1440 SC-1441 SC-1442

set -u

MAX_GROUPS=25   # detection runs after the command, so it can afford more than the pre-layer's 8

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

ROOT=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}/.git" ]; then
  ROOT="$CLAUDE_PROJECT_DIR"
elif [ -n "$CWD" ]; then
  ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || ROOT=""
fi
[ -z "$ROOT" ] && exit 0

MARKER="$ROOT/.claude/.bash-write-marker"
BLOCKED="$ROOT/.claude/.bash-write-blocked"

# No before-time means nothing can be said about what this command changed, and inventing a finding is
# worse than missing one. (The pre-layer stamps the marker on every Bash call, so this is the
# first-command-of-a-session case, or a session where the pre-layer is not wired.)
[ -f "$MARKER" ] || exit 0

# Consume the marker whatever happens below, so the next command starts from its own before-time.
cleanup() { rm -f "$MARKER" 2>/dev/null || true; }

# Exemptions, checked before any work.
case "$CMD" in
  *"git checkout"*|*"git switch"*|*"git restore"*|*"git stash"*|*"git reset"*|*"git clean"*|\
  *"git pull"*|*"git merge"*|*"git rebase"*)
    cleanup; exit 0 ;;
esac

# Everything that changed since the marker. Pruned to what a gate could ever care about: .git and build
# output are noise, .claude/worktrees holds stale whole copies of the repo, and graphify-out is generated.
# Measured at 23 ms over 802 .cs files on this tree — cheap enough to run after every shell command.
CHANGED=$(find "$ROOT" \
  -type d \( -name .git -o -name node_modules -o -name bin -o -name obj -o -name graphify-out \
             -o -name StrykerOutput -o -name TestResults -o -name worktrees -o -name .venv \) -prune -o \
  -type f -newer "$MARKER" -print 2>/dev/null)

if [ -z "$CHANGED" ]; then
  cleanup; exit 0
fi

# One representative per (directory, extension): all three guards decide from the path alone, so files
# sharing both get identical verdicts. Exact, not a sample — which is what lets the cap below be honest.
REPS=$(printf '%s\n' "$CHANGED" | python3 "$HOOK_DIR/bash_write_targets.py" --group 2>/dev/null)
[ -z "$REPS" ] && { cleanup; exit 0; }

GROUP_COUNT=$(printf '%s\n' "$REPS" | grep -c '')
TRUNCATED=""
if [ "$GROUP_COUNT" -gt "$MAX_GROUPS" ]; then
  # No silent caps (scripts/run-gates.sh's rule): say what was dropped, or the report reads as coverage it
  # does not have.
  TRUNCATED="
NOTE: ${GROUP_COUNT} directory/extension groups changed; only the first ${MAX_GROUPS} were checked. The rest are UNCHECKED, not cleared."
  REPS=$(printf '%s\n' "$REPS" | sed -n "1,${MAX_GROUPS}p")
fi

FINDINGS=""
FIRST_REASON=""
while IFS= read -r target; do
  [ -z "$target" ] && continue
  for guard in spec-register-guard-hook.sh pipeline-state-guard-hook.sh spec-interview-guard-hook.sh; do
    [ -f "$HOOK_DIR/$guard" ] || continue
    OUT=$(printf '{"tool_input":{"file_path":%s}}' "$(jq -Rn --arg p "$target" '$p')" \
            | bash "$HOOK_DIR/$guard" 2>/dev/null)
    [ -z "$OUT" ] && continue
    INNER=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
    [ -z "$INNER" ] && continue
    FINDINGS="${FINDINGS}${target}
"
    [ -z "$FIRST_REASON" ] && FIRST_REASON="$INNER"
    break
  done
done <<EOF
$REPS
EOF

if [ -z "$FINDINGS" ]; then
  cleanup; exit 0
fi

# The escape hatch: same finding as last time → stay quiet.
FINGERPRINT=$(printf '%s' "$FINDINGS" | sort | tr -d '\n')
if [ -f "$BLOCKED" ]; then
  PREV=$(cat "$BLOCKED" 2>/dev/null || true)
  if [ "$PREV" = "$FINGERPRINT" ]; then
    cleanup; exit 0
  fi
fi
printf '%s' "$FINGERPRINT" > "$BLOCKED" 2>/dev/null || true
cleanup

REASON="A shell command wrote to source files the pipeline guard denies.

Files changed:
${FINDINGS}${TRUNCATED}
This was detected AFTER the fact, on the filesystem — the write had already happened. Before row H7b it
would not have been detected at all: the three pipeline guards are wired to Edit/Write/MultiEdit, so a
write made through the shell met no gate, and 56 register rows shipped that way.

Either finish the active spec's pipeline phases, or revert these files. The guard's reason follows.

────────────────────────────────────────────────────────────
${FIRST_REASON}

(This blocks once for this set of files. Changing something else arms it again.)"

SUMMARY="ConsultPilot pipeline guard: a shell command wrote to $(printf '%s' "$FINDINGS" | grep -c '') source file(s) the guard denies. See the block reason for the file list and the guard's own explanation."

jq -n --arg r "$REASON" --arg s "$SUMMARY" \
  '{decision: "block", reason: $r, systemMessage: $s}'
exit 0
