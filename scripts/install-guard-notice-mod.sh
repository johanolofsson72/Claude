#!/bin/bash
# Installs the guard-notice mod (spec 096) from its staged source in mods/guard-notice/.
#
#   ! bash scripts/install-guard-notice-mod.sh                    # into <config>/skills/guard-notice
#   ! bash scripts/install-guard-notice-mod.sh --target ~/mods/gn # a folder you load yourself
#   ! bash scripts/install-guard-notice-mod.sh --uninstall [--target DIR]
#   bash scripts/install-guard-notice-mod.sh --digest              # print the staged source's digest
#
# THE DEVELOPER RUNS THIS, WITH THE `!` PREFIX. A loaded mod's hook can allow any tool call past every
# settings hook (spec 095a), so the agent may not install one: settings-edit-guard denies any command
# that runs a script named install-*-mod.sh. A `!` command runs outside the agent's tools.
#
# THE SOURCE IS PINNED (spec 105 R8, F186, developer O3). The agent can edit mods/guard-notice/, so a
# change to the source never reaches the loaded mod on its own. The script prints the staged files'
# digest and installs only a digest the developer named:
#
#   ! bash scripts/install-guard-notice-mod.sh --accept <digest>
#
# Review the source first (git log -p -- mods/guard-notice). An accepted digest is recorded in the
# project's git dir (claude-mod-accepted, which trust-anchor-guard keeps the agent's tools out of),
# never in the target folder, which the agent can write. A rerun of a recorded digest needs no --accept.
# The files are copied to a private staging folder, hashed there, and installed from that same copy, so
# the bytes that were accepted are the bytes that land.
#
# WHAT IT DOES. The repository keeps the mod under names that do not load (plugin.json.staged,
# hooks.json.staged, no .claude-plugin/ and no hooks/hooks.json), so the agent can edit the source.
# This script copies it into the target with those two files renamed into place:
#
#   <target>/.claude-plugin/plugin.json     <target>/hooks/hooks.json
#   <target>/hooks/register.tsx             <target>/hooks/lib.ts
#   <target>/types/index.d.ts               <target>/.guard-notice-installed
#
# Run again to update. It overwrites only a folder carrying its own .guard-notice-installed marker,
# and --uninstall removes only such a folder. With `claude` on PATH it runs `claude plugin validate`.
#
# HOW IT LOADS. The default target, <config>/skills/guard-notice (CLAUDE_CONFIG_DIR, else ~/.claude), is
# loaded by Claude Code 2.1.288 at session start with no flag. Another target loads with
# `claude --plugin-dir <target>`, or from CLAUDE_CODE_PLUGIN_DIRS in ~/.claude/settings.json's env.
# The band has a Hide button; to remove it for good, --uninstall.
#
# Exit: 0 done, 1 refused (a folder it did not install, a missing staged file), 2 bad arguments,
# 3 claude plugin validate rejected the result (the files stay, for inspection), 4 the staged source's
# digest is not accepted (the message names it and the command that accepts it).

set -u

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/mods/guard-notice"
CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET="$CONF/skills/guard-notice"
UNINSTALL=0
DIGEST_ONLY=0
ACCEPT=""
MARK=.guard-notice-installed
FILES="plugin.json.staged hooks.json.staged register.tsx lib.ts types/index.d.ts"

while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || { echo "install-guard-notice-mod: --target needs a folder" >&2; exit 2; }
              TARGET="$2"; shift 2 ;;
    --target=*) TARGET="${1#--target=}"; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --digest) DIGEST_ONLY=1; shift ;;
    --accept) [ $# -ge 2 ] || { echo "install-guard-notice-mod: --accept needs a digest" >&2; exit 2; }
              ACCEPT="$2"; shift 2 ;;
    --accept=*) ACCEPT="${1#--accept=}"; shift ;;
    -h|--help) sed -n '2,42p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "install-guard-notice-mod: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TARGET" ] || { echo "install-guard-notice-mod: empty --target" >&2; exit 2; }

if [ "$DIGEST_ONLY" -eq 0 ] && [ -e "$TARGET" ] && [ ! -f "$TARGET/$MARK" ]; then
  echo "install-guard-notice-mod: $TARGET exists and was not installed by this script (no $MARK); leaving it alone." >&2
  exit 1
fi

if [ "$UNINSTALL" -eq 1 ]; then
  if [ ! -e "$TARGET" ]; then
    echo "install-guard-notice-mod: nothing installed at $TARGET"
    exit 0
  fi
  rm -r -- "$TARGET" && echo "install-guard-notice-mod: removed $TARGET. A session that loaded it keeps it until it restarts."
  exit $?
fi

for f in $FILES; do
  { [ -f "$SRC/$f" ] && [ ! -L "$SRC/$f" ]; } || { echo "install-guard-notice-mod: staged file missing (or a link): mods/guard-notice/$f" >&2; exit 1; }
done

_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -c1-64; else shasum -a 256 | cut -c1-64; fi; }
STAGE=$(mktemp -d 2>/dev/null || mktemp -d -t gnstage) || exit 1   # mutant-equivalent in the self-test: mktemp falls back to /tmp, so its failure cannot be induced portably
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/types" || exit 1                                    # mutant-equivalent: a fresh private dir; as above
for f in $FILES; do cp "$SRC/$f" "$STAGE/$f" || exit 1; done
DIGEST=$(for f in $FILES; do printf '%s %s\n' "$f" "$(_sha < "$STAGE/$f")"; done | _sha | cut -c1-16)
if [ "$DIGEST_ONLY" -eq 1 ]; then echo "$DIGEST"; exit 0; fi

# The accepted digests live in the git dir (GUARD_NOTICE_PIN_STORE is the self-test's seam; the agent
# cannot run this script at all, so the variable opens no route).
STORE=${GUARD_NOTICE_PIN_STORE:-}
if [ -z "$STORE" ]; then
  _gd=$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null) && STORE="$_gd/claude-mod-accepted"
fi
accepted() { [ -n "$STORE" ] && [ -f "$STORE" ] && grep -qx "guard-notice $DIGEST" "$STORE"; }   # mutant-equivalent (&& -> ||): every mutated chain still ends in a grep that fails on a missing store
if [ "$ACCEPT" != "$DIGEST" ] && ! accepted; then
  [ -n "$ACCEPT" ] && echo "install-guard-notice-mod: --accept $ACCEPT does not match the staged source." >&2
  _t=""; [ "$TARGET" != "$CONF/skills/guard-notice" ] && _t=" --target \"$TARGET\""
  {
    echo "install-guard-notice-mod: the staged source in mods/guard-notice/ digests to $DIGEST, which has not been accepted."
    echo "A loaded mod's hook can allow any tool call, and the agent can edit that source, so review it first:"
    echo "    git log -p -- mods/guard-notice"
    echo "then install it with:"
    echo "    ! bash scripts/install-guard-notice-mod.sh --accept $DIGEST$_t"
  } >&2
  exit 4
fi

mkdir -p "$TARGET/.claude-plugin" "$TARGET/hooks" "$TARGET/types" || exit 1
cp "$STAGE/plugin.json.staged" "$TARGET/.claude-plugin/plugin.json" &&
cp "$STAGE/hooks.json.staged" "$TARGET/hooks/hooks.json" &&
cp "$STAGE/register.tsx" "$STAGE/lib.ts" "$TARGET/hooks/" &&
cp "$STAGE/types/index.d.ts" "$TARGET/types/index.d.ts" &&
printf 'installed by scripts/install-guard-notice-mod.sh from %s\ndigest %s\n' "$SRC" "$DIGEST" > "$TARGET/$MARK" || exit 1   # mutant-equivalent: the folder was just made; a failed write cannot be induced portably
if [ -n "$STORE" ] && ! accepted; then printf 'guard-notice %s\n' "$DIGEST" >> "$STORE"; fi
echo "install-guard-notice-mod: installed into $TARGET (digest $DIGEST)"

if command -v claude >/dev/null 2>&1 && [ "${GUARD_NOTICE_SKIP_VALIDATE:-0}" != 1 ]; then
  if ! claude plugin validate "$TARGET"; then
    echo "install-guard-notice-mod: claude plugin validate rejected $TARGET (files left in place)." >&2
    exit 3
  fi
fi
case "$TARGET" in
  "$CONF/skills/"*) echo "It loads at the next session start." ;;
  *) echo "Load it with: claude --plugin-dir \"$TARGET\" (or add the folder to CLAUDE_CODE_PLUGIN_DIRS)." ;;
esac
