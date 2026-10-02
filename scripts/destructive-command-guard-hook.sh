#!/bin/bash
# PreToolUse guard on Bash: the destructive deny list, by spelling rather than by prefix (spec 083, R9).
#
# WHY THIS EXISTS
# ---------------
# .claude/settings.json denies `Bash(rm -rf *)`, `Bash(git push --force*)`, `Bash(sudo *)` and the rest.
# Those rules match the command TEXT by prefix. With `defaultMode: bypassPermissions` and `allow: Bash`
# — this template's settings — every other spelling of the same command ran: `rm -r -f`, `/bin/rm -rf`,
# `command rm -rf`, `git -C . push -f`, `git push origin +main`, `git clean -fd` (H1 adversarial #3,
# F038). A deny list that the first synonym walks past is advice.
#
# This hook asks scripts/destructive_command.py, which splits the command the way a shell does and
# resolves the command word through the wrappers that only run another command (sudo, env, xargs,
# nohup, timeout, command, exec, nice, time). It denies:
#
#   rm   with a recursive AND a force flag, in any spelling or order
#   sudo, doas, su, pkexec as a command word
#   git  push --force / -f / a cluster with f / --force-with-lease / --force-if-includes / +refspec;
#        push --delete / -d / --prune / a `:ref` refspec, and push --mirror, also through send-pack, a
#        `-c remote.<x>.mirror|push=…` or a `git config` of those keys (spec 090 R5, developer O3);
#        reset --hard; clean -f / --force (global options before the subcommand are skipped)
#   find with -delete, or -exec/-execdir/-ok running rm  (the developer's choice, spec 083 O2)
#
# The settings deny list stays: it is the first layer, and the CLI applies it before any hook runs.
#
# THE DECLARED BOUND. Spellings, not semantics. A variable, alias or function, a script that deletes,
# `eval "$x"`, an interpreter (`python -c "shutil.rmtree(...)"`) and `git -c alias.x='!rm -rf .'` all
# pass, as does every destructive command the list never named (dd, mkfs, git branch -D). This raises
# the cost of a careless or injected command; a program written to delete can still be written.
#
# NO OVERRIDE, matching the deny list it extends. The reason tells the model to ask the developer to
# run the command themselves with `!`, which no hook sees.
#
# SECRETS. The command is never echoed (same rule as bash-write-guard, FR-015): only the form found.
#
# FAILS CLOSED on what it cannot read, but only for a command that names one of its trigger words —
# the same answer the pipeline guards give (spec 083, O3). Exit: always 0.

set -u

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Cheapest exit first. Every Bash call pays for this hook, so a command that names none of the words a
# destructive form needs never starts a process. Matched on the raw payload, which holds the command
# verbatim apart from JSON escaping (that never touches letters). Bounded like the other guards'
# prechecks: bash's matcher is slow on long strings, so a long payload goes straight to the parser.
# A JSON-escaped newline or tab (`\n`, `\t`) in front of the word counts as a boundary: in the raw
# payload `ls\nrm -rf x` has an `n` before `rm`, and a second line is still a command.
# Case-insensitive, because macOS finds /bin/RM. A word split by quotes or a backslash (`r""m`,
# `'r'm`, `g\it`) has no literal trigger in the raw text, so a letter touching a quote or an escaped
# backslash also sends the command to the parser (adversarial review, spec 083).
TRIGGER='(^|[^A-Za-z0-9_.-]|\\[ntr])(rm|sudo|doas|su|pkexec|find|eval|git)([^A-Za-z0-9_-]|$)'
NOGIT='(^|[^A-Za-z0-9_.-]|\\[ntr])(rm|sudo|doas|su|pkexec|find|eval)([^A-Za-z0-9_-]|$)'
SPLIT="[A-Za-z](\\\\|\\\"|')+[A-Za-z]|(^|[^A-Za-z0-9])('|\\\\\"|\\\\)[A-Za-z]+('|\\\\\")[A-Za-z]"
if [ "${#INPUT}" -le 4096 ]; then
  shopt -s nocasematch
  if [[ $INPUT =~ $SPLIT ]]; then :
  else
  [[ $INPUT =~ $TRIGGER ]] || exit 0
  # `git` alone is every status and log; only three of its subcommands are on the list.
  if ! [[ $INPUT =~ $NOGIT ]]; then
    [[ $INPUT =~ (push|reset|clean|send-pack|mirror|remote[[:space:]]+(add|set)|config) ]] || exit 0
  fi
  fi
  shopt -u nocasematch
fi

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! . "$HOOK_DIR/guard-lib.sh" 2>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED — destructive-command-guard cannot load scripts/guard-lib.sh, so it cannot read this command. Re-run the template sync (it is in CORE_SCRIPTS), or ask the developer to run the command with !"}}'
  exit 0
fi

CMD=$(guard_field .tool_input.command); FRC=$?
if [ "$FRC" -ne 0 ]; then
  [[ $INPUT =~ $TRIGGER ]] || exit 0
  guard_deny "BLOCKED — destructive-command-guard cannot read this command: $(guard_cause "$FRC").

It names a word on the destructive list (rm, sudo, find, eval, git), and a floor guard that cannot read the command does not wave it through (spec 083). Install jq, or ask the developer to run the command with ! — no hook sees that."
  exit 0
fi
[ -z "$CMD" ] && exit 0

FORM=$(CMD_TEXT="$CMD" python3 "$HOOK_DIR/destructive_command.py" 2>/dev/null); PRC=$?
if [ "$PRC" -ne 0 ] || [ -z "$FORM" ]; then
  guard_deny "BLOCKED — destructive-command-guard could not classify this command: python3 scripts/destructive_command.py did not answer (exit $PRC).

It names a word on the destructive list (rm, sudo, find, eval, git), and a floor guard that cannot read the command does not wave it through (spec 083). Fix python3, or ask the developer to run the command with ! — no hook sees that."
  exit 0
fi
[ "$FORM" = none ] && exit 0

case "$FORM" in
  rm-recursive-force) WHAT="a recursive, forced rm (rm -rf in some spelling: -r -f, -Rf, /bin/rm, command rm, behind xargs or sudo)" ;;
  sudo)               WHAT="a privilege escalation (sudo, doas, su, pkexec)" ;;
  git-push-force)     WHAT="a force push (git push -f / --force / --force-with-lease / --force-if-includes / a +refspec)" ;;
  git-push-delete)    WHAT="a push that deletes a remote ref (git push --delete / -d / --prune / a :ref refspec, or a remote.<x>.push of one)" ;;
  git-push-mirror)    WHAT="a mirror push (git push --mirror, send-pack --mirror, or remote.<x>.mirror), which deletes every remote ref the local repository lacks" ;;
  git-reset-hard)     WHAT="git reset --hard" ;;
  git-clean-force)    WHAT="git clean with -f (in any flag cluster)" ;;
  find-delete)        WHAT="find with -delete, or -exec rm" ;;
  *)                  WHAT="$FORM" ;;
esac

guard_deny "BLOCKED — this command contains ${WHAT}.

That form is on the project's destructive deny list (.claude/settings.json permissions.deny). The deny list matches the command text by prefix, so a different spelling of the same command used to run; this guard reads the command the way the shell will and applies the list to what it finds (spec 083, R9).

There is no override. If the operation is really needed:
  * ask the developer to run it themselves, prefixed with ! in the prompt — no hook sees that; or
  * do it narrowly instead: remove named files without -r/-f, push without force, git restore / git stash instead of reset --hard, git clean -n to list before anything is removed. Deleting a remote branch is always the developer's step."
exit 0
