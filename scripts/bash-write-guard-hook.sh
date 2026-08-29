#!/usr/bin/env bash
# PreToolUse guard on Bash: applies the SAME pipeline gate to writes made through the shell that
# Edit/Write/MultiEdit have had all along (row H7b).
#
# WHY THIS EXISTS
# ---------------
# The three pipeline guards (spec-register, pipeline-state, spec-interview) are wired to the matcher
# "Edit|Write|MultiEdit". Nothing was wired to Bash. So the enforcement answer depended on which tool the
# agent happened to pick: `Edit src/App.cs` was denied, `sed -i '' 's/x/y/' src/App.cs` was not. Measured at
# H7b: 56 register rows shipped in a tree where all three guards denied every Edit — through the shell.
#
# A guard whose enforcement depends on the tool is not a guard.
#
# IT DELEGATES — IT DOES NOT DECIDE
# ---------------------------------
# This hook extracts candidate write targets and then feeds each one to the four EXISTING guards as a
# synthetic {"tool_input":{"file_path": ...}}. The path allowlist, the extension list, the .git walk, the
# language-marker check and the register resolution are all inherited, not copied. Spec 007m's regression
# survived ten days precisely because each guard carried its own copy of the register parser; a fourth copy
# of the policy here would rebuild that trap. If a verdict is wrong, it is wrong identically in both paths,
# which is the property that makes it findable.
#
# DECLARED COVERAGE BOUND (FR-010) — read this before trusting it
# ---------------------------------------------------------------
# Six shell forms are detected: redirection `>` / `>>` (which is also how a heredoc writes), `sed -i`,
# `tee`, `cp`, `mv`. That is a string parser, and a string parser CANNOT see:
#
#   * a write performed by an interpreter it does not read into:
#       python3 - <<'PY' ... open('src/App.cs','w') ... PY
#   * `eval`, `bash -c "$(...)"`, or any path assembled at runtime from a variable
#   * `xargs sed -i`, `find -exec`, a Makefile target, a script that writes files
#   * `install`, `dd of=`, `truncate`, `patch` — deliberately NOT claimed here, because a form named in a
#     requirement with no fixture behind it is a coverage number with no coverage
#
# Every one of those is caught by the OTHER layer, scripts/bash-write-detect-hook.sh, which watches the
# filesystem instead of the command string and therefore does not care how the write was spelled. This hook
# is prevention for the common shapes; that one is detection for everything. Neither alone is honest.
#
# THE FOURTH DELEGATE — CORE OWNERSHIP (row H7t)
# ---------------------------------------------
# scripts/core-machinery-guard-hook.sh answers a different question from the three above: not "has this
# spec's pipeline run?" but "whose file is this?" — over the CORE set that scripts/template-autosync.sh
# overwrites unconditionally. It was wired to Edit|Write|MultiEdit only, so the same defect this hook was
# built to remove existed one floor up: `Edit scripts/template-autosync.sh` was denied and
# `sed -i '' s/x/y/ scripts/template-autosync.sh` was silent. Measured 2026-08-25, and not hypothetically —
# a session told to prefer Bash for file edits takes the silent route by default.
#
# It is asked FIRST and it cannot collide with the other three: they all exit early on */scripts/* and
# */.claude/* by design (a guard that blocks its own repair path cannot be repaired), and core-machinery is
# silent everywhere EXCEPT <root>/scripts/ and <root>/.claude/rules/. Disjoint sets, so the order changes
# which text arrives first only in a case that cannot occur — first is chosen so the reading order matches
# the Edit path.
#
# Its fail-open, its ALLOW_CORE_MACHINERY_EDIT=1 override and its template-repo self-exemption are all
# inherited unmodified. With the override set it answers with additionalContext rather than a deny, so INNER
# comes back empty and the loop simply continues — the override works on this route without a line of code
# here, and there is a fixture pinning that rather than a comment claiming it.
#
# SECRETS (FR-015)
# ----------------
# The command string is NEVER echoed — not in the deny reason, not in a log, not in an error. A shell
# command can carry a credential (`op read`, `--password`, a heredoc holding a key) and CLAUDE.md §Secrets
# forbids values reaching logs or error output. Only DERIVED file paths appear in output.
#
# Exit: always 0. A deny is expressed as permissionDecision JSON on stdout, per the hook contract.
#
# Covers: SC-1437 SC-1439 SC-1442 SC-1678 SC-1679 SC-1680 SC-1681

set -u

MAX_GROUPS=8   # FR-006a — see the cap note below

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# ---------------------------------------------------------------------------
# 1) Stamp the "before" marker for the PostToolUse layer.
#
# Unconditional and first: the detect layer needs a before-time for EVERY Bash call, including the ones
# this layer skips in a millisecond — those are exactly the calls whose writes it cannot see.
# ---------------------------------------------------------------------------
ROOT=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}/.git" ]; then
  ROOT="$CLAUDE_PROJECT_DIR"
elif [ -n "$CWD" ]; then
  ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || ROOT=""
fi
if [ -n "$ROOT" ] && [ -d "$ROOT/.claude" ]; then
  : > "$ROOT/.claude/.bash-write-marker" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2) Fast reject. This hook is on the Bash hot path, so a command that cannot contain any of the six forms
#    must not pay for a python start (~50 ms on this machine). Deliberately over-inclusive: it costs a
#    wasted extraction, never a missed one.
# ---------------------------------------------------------------------------
case "$CMD" in
  *">"*|*sed*|*tee*|*cp*|*mv*) ;;
  *) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# 3) Extract candidate write targets and make them absolute.
# ---------------------------------------------------------------------------
TARGETS=$(CMD_TEXT="$CMD" CWD_PATH="${CWD:-$PWD}" python3 "$HOOK_DIR/bash_write_targets.py" 2>/dev/null) || exit 0

[ -z "$TARGETS" ] && exit 0

TOTAL=$(printf '%s\n' "$TARGETS" | sed -n '1p')
REPS=$(printf '%s\n' "$TARGETS" | sed '1d' | sed '/^$/d')
[ -z "$REPS" ] && exit 0

GROUP_COUNT=$(printf '%s\n' "$REPS" | grep -c '' )

# FR-006a — bounded. Each representative costs three guard processes with a python start apiece, and an
# unbounded layer on the Bash hot path is a layer that gets deleted. Past the cap this DENIES rather than
# waves through: an unmeasured allow is the failure this whole row is about.
if [ "$GROUP_COUNT" -gt "$MAX_GROUPS" ]; then
  REASON="BLOCKED — this shell command writes to more distinct places than the pipeline guard will check unverified (${GROUP_COUNT} directory/extension groups, cap ${MAX_GROUPS}; ${TOTAL} target paths).

The guard checks one representative per (directory, extension) group, because all three pipeline guards decide from the path alone — so files sharing both get the same verdict. Past the cap it stops rather than guessing: waving a write through unmeasured is the exact failure this guard exists to remove.

Split the command into smaller writes, or make the edits with the Edit tool, which is gated the same way one file at a time."
  jq -n --arg r "$REASON" '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
fi

# ---------------------------------------------------------------------------
# 4) Delegate. First deny wins; its reason is passed through verbatim with one line of provenance.
# ---------------------------------------------------------------------------
while IFS= read -r target; do
  [ -z "$target" ] && continue
  for guard in core-machinery-guard-hook.sh core-owed-tick-guard-hook.sh spec-register-guard-hook.sh pipeline-state-guard-hook.sh spec-interview-guard-hook.sh; do
    [ -f "$HOOK_DIR/$guard" ] || continue
    OUT=$(printf '{"tool_input":{"file_path":%s}}' "$(jq -Rn --arg p "$target" '$p')" \
            | bash "$HOOK_DIR/$guard" 2>/dev/null)
    [ -z "$OUT" ] && continue
    INNER=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
    [ -z "$INNER" ] && continue
    # The provenance line has to be true, and there are two different truths here. The pipeline guards
    # answer "has this spec's pipeline run?" about a SOURCE file; core-machinery answers "whose file is
    # this?" about a file under scripts/ or .claude/rules/ that the template owns. Calling the second one
    # "a source file the pipeline guard denies" would be false in both halves, and a header that lies
    # about which gate spoke sends the reader to the wrong repair (row H7t). The delegate's own reason is
    # passed through verbatim in both arms — only the one line above it changes.
    case "$guard" in
      core-owed-tick-guard-hook.sh)
        REASON="BLOCKED — a shell command was about to tick a register row while this project owes the template CORE work.

Target: ${target}
Guard:  scripts/${guard}

Its own reason follows. Note the coverage bound it states: this route hands it a path and no bytes, so unlike the Edit route it cannot tell a tick from any other write to specs/INDEX.md. Answering about the file is the conservative half of that trade — the alternative is that \`sed -i\` is the silent way past a gate the Edit tool enforces, which is the defect row H7b exists to remove.

────────────────────────────────────────────────────────────
${INNER}"
        ;;
      core-machinery-guard-hook.sh)
        REASON="BLOCKED — a shell command was about to write to a file the TEMPLATE owns.

Target: ${target}
Guard:  scripts/${guard}

This is the same answer the Edit tool has given since spec 007ao. Until row H7t it was wired to Edit/Write/MultiEdit only, so \`sed -i\`, a redirect or a heredoc against CORE machinery met no gate at all — and a guard whose verdict depends on which tool you picked is not a guard. The guard's own reason follows.

────────────────────────────────────────────────────────────
${INNER}"
        ;;
      *)
        REASON="BLOCKED — a shell command was about to write to a source file the pipeline guard denies.

Target: ${target}
Guard:  scripts/${guard}

The gate is the same one Edit/Write/MultiEdit have always passed through; before row H7b it simply was not wired to Bash, so which tool you picked decided whether the rule applied. It no longer does. The guard's own reason follows.

────────────────────────────────────────────────────────────
${INNER}"
        ;;
    esac
    jq -n --arg r "$REASON" '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  done
done <<EOF
$REPS
EOF

exit 0
