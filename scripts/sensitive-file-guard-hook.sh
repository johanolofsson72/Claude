#!/bin/bash
# PreToolUse guard: keeps credential files out of every tool that can name a path (spec 083, R10).
#
# WHY THIS EXISTS
# ---------------
# The template shipped this check as an inline hook on Read|Edit|Write (security.md: permissions.deny
# has known enforcement bugs, so a PreToolUse deny is the reliable layer). H1's adversarial pass found
# the reliable layer full of holes (F039): `Bash cat ~/.ssh/id_rsa`, Grep over ~/.aws, Glob and
# NotebookEdit were never asked; the regex wanted a leading `/`, so a relative `.ssh/config` passed;
# .netrc, .npmrc, .kube and .gnupg were not listed; and above 4096 bytes, with no jq, it allowed.
#
# Now: one matcher across Read, Edit, Write, MultiEdit, NotebookEdit, Grep, Glob and Bash, with the
# rule in scripts/sensitive_paths.py (what counts as sensitive, and where in each payload it looks).
# sync-core-hooks.py retires the two template texts of the old inline hook in any project that has
# this script, so a project is never left with only the old one.
#
# FAILS CLOSED, on what it cannot read: a payload that mentions a sensitive name but cannot be parsed
# is denied. Everything that names none passes in the bash precheck, without a process.
#
# THE BOUND. Named paths only; see sensitive_paths.py. Exit: always 0.

set -u

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Cheapest exit first: no sensitive name anywhere in the raw payload, nothing to decide. Bounded like
# the other prechecks; a long payload goes straight to the parser instead.
#
# Case-insensitive (macOS opens ~/.SSH), and a dot-name the raw text splits with a quote, a backslash,
# a brace or a bracket (`.s""sh`, `.s\sh`, `{.ssh,x}`, `.ss[h]`) also goes to the parser, because the
# shell joins it back together (adversarial review, spec 083).
if [ "${#INPUT}" -le 4096 ]; then
  shopt -s nocasematch
  case "$INPUT" in
    *.ssh*|*.aws*|*.azure*|*.kube*|*.gnupg*|*.docker/config*|*.config/gh*|*.config/gcloud*|*.git-credentials*|*.netrc*|*.npmrc*|*.env*|*.pgpass*|*.pypirc*) ;;
    # `?` and `*` too: the shell expands `.s*` to .ssh (/security-review, spec 083).
    *) [[ $INPUT =~ \.[A-Za-z-]{0,12}(\\\\|\\\"|\'|\{|\[|\?|\*) ]] || exit 0 ;;
  esac
  shopt -u nocasematch
fi

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! . "$HOOK_DIR/guard-lib.sh" 2>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED — sensitive-file-guard cannot load scripts/guard-lib.sh, and this call mentions a credential-shaped name. Re-run the template sync (it is in CORE_SCRIPTS)."}}'
  exit 0
fi

VERDICT=$(printf '%s' "$INPUT" | python3 "$HOOK_DIR/sensitive_paths.py" 2>/dev/null) || VERDICT="unparseable"
[ -n "$VERDICT" ] || VERDICT="unparseable"

case "$VERDICT" in
  none) exit 0 ;;
  hit\ *)
    HIT="${VERDICT#hit }"
    guard_deny "BLOCKED — this call names a credential file or directory: ${HIT}

Paths under .ssh, .aws, .azure, .kube or .gnupg, the Docker and gh CLI configs, .git-credentials, .netrc, .npmrc, .env and .env.<anything> are off limits to every tool, the shell included (.claude/docs/security.md). .env.example, .env.sample and .env.template are allowed.

If you are searching for the TEXT of such a name rather than opening the file, use the Grep tool with a path that is not one of these. If the developer needs a value from one, ask them for it."
    exit 0
    ;;
esac

# unparseable, or python3 missing: the raw text mentioned a sensitive name and nothing could say
# whether it is a path. Deny, naming the cause.
if command -v python3 >/dev/null 2>&1; then CAUSE="the hook payload is not a JSON object"
else CAUSE="python3 is not on PATH, and the paths are classified in python3"; fi
guard_deny "BLOCKED — sensitive-file-guard cannot read this call ($CAUSE), and its text mentions a credential-shaped name (.ssh, .aws, .env, …). A guard that cannot see whether that is a path does not allow it (spec 083, R10)."
exit 0
