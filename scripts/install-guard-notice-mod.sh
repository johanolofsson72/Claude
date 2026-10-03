#!/bin/bash
# Installs the guard-notice mod (spec 096) from its staged source in mods/guard-notice/.
#
#   ! bash scripts/install-guard-notice-mod.sh                    # into <config>/skills/guard-notice
#   ! bash scripts/install-guard-notice-mod.sh --target ~/mods/gn # a folder you load yourself
#   ! bash scripts/install-guard-notice-mod.sh --uninstall [--target DIR]
#
# THE DEVELOPER RUNS THIS, WITH THE `!` PREFIX. A loaded mod's hook can allow any tool call past every
# settings hook (spec 095a), so the agent may not install one: settings-edit-guard denies any command
# that runs a script named install-*-mod.sh. A `!` command runs outside the agent's tools.
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
# 3 claude plugin validate rejected the result (the files stay, for inspection).

set -u

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/mods/guard-notice"
CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET="$CONF/skills/guard-notice"
UNINSTALL=0
MARK=.guard-notice-installed

while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || { echo "install-guard-notice-mod: --target needs a folder" >&2; exit 2; }
              TARGET="$2"; shift 2 ;;
    --target=*) TARGET="${1#--target=}"; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "install-guard-notice-mod: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TARGET" ] || { echo "install-guard-notice-mod: empty --target" >&2; exit 2; }

if [ -e "$TARGET" ] && [ ! -f "$TARGET/$MARK" ]; then
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

for f in plugin.json.staged hooks.json.staged register.tsx lib.ts types/index.d.ts; do
  [ -f "$SRC/$f" ] || { echo "install-guard-notice-mod: staged file missing: mods/guard-notice/$f" >&2; exit 1; }
done

mkdir -p "$TARGET/.claude-plugin" "$TARGET/hooks" "$TARGET/types" || exit 1
cp "$SRC/plugin.json.staged" "$TARGET/.claude-plugin/plugin.json" &&
cp "$SRC/hooks.json.staged" "$TARGET/hooks/hooks.json" &&
cp "$SRC/register.tsx" "$SRC/lib.ts" "$TARGET/hooks/" &&
cp "$SRC/types/index.d.ts" "$TARGET/types/index.d.ts" &&
printf 'installed by scripts/install-guard-notice-mod.sh from %s\n' "$SRC" > "$TARGET/$MARK" || exit 1
echo "install-guard-notice-mod: installed into $TARGET"

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
