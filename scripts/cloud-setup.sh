#!/bin/bash
# cloud-setup.sh — make a Claude cloud VM able to run this project's heavy maintenance jobs (row 075).
#
# WHY THIS EXISTS. The cloud VM ships Python, Node, Java, Go, Rust and Docker, and no .NET SDK
# (code.claude.com/docs/en/cloud-environments, 2026-09-29). Stryker.NET and `dotnet test` are the
# two jobs row 075 moves to the cloud, so without this the cloud half fails on its first command.
#
# What it does, only when it is needed:
#   - a .NET solution or project exists, and `dotnet` is not on PATH → install the SDK with
#     Microsoft's dotnet-install.sh into ~/.dotnet. The channel comes from global.json's
#     sdk.version when the project pins one (major.minor), otherwise LTS.
#   - `dotnet stryker` is configured (a stryker-config.json exists) and no stryker tool is restored →
#     `dotnet tool restore` when a tool manifest exists, else install dotnet-stryker globally.
# Idempotent: a second run finds dotnet and the tool and does nothing.
#
# It can be pasted as the environment's setup script (claude.ai/code/environments) with
#   bash scripts/cloud-setup.sh
# when that script runs inside the clone, and scripts/cloud-maintenance.sh calls it anyway, so the
# run works whether or not the environment was configured.
#
# PATH: the SDK lands in ~/.dotnet. This script cannot change its caller's PATH; the caller sources
# the line it prints on stdout (`export PATH=...`). Everything else goes to stderr.
#
# Exit: 0 ready (or nothing to do) · 1 an install failed. CLOUD_SETUP_DRY_RUN=1 prints the actions
# without running them (tests). bash 3.2-safe.

set -u

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT" || exit 1
DOTNET_DIR="${DOTNET_INSTALL_DIR:-$HOME/.dotnet}"
DRY="${CLOUD_SETUP_DRY_RUN:-0}"

say() { echo "cloud-setup: $*" >&2; }
act() { # act CMD... — run, or print under dry run
  if [ "$DRY" = 1 ]; then say "would run: $*"; return 0; fi
  "$@"
}

HAS_DOTNET_PROJECT=$(find . -maxdepth 4 \( -name node_modules -o -name .git -o -name bin -o -name obj \) -prune -o \
  -type f \( -name '*.sln' -o -name '*.slnx' -o -name '*.csproj' \) -print 2>/dev/null | sed -n 1p)

if [ -z "$HAS_DOTNET_PROJECT" ]; then
  say "no .NET solution or project — nothing to install."
  exit 0
fi

[ -x "$DOTNET_DIR/dotnet" ] && PATH="$DOTNET_DIR:$DOTNET_DIR/tools:$PATH"

if ! command -v dotnet >/dev/null 2>&1; then
  CHANNEL=LTS
  if [ -f global.json ]; then
    PINNED=$(tr -d '\r' < global.json | grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+$' | head -1)
    [ -n "$PINNED" ] && CHANNEL="$PINNED"
  fi
  say "installing the .NET SDK (channel $CHANNEL) into $DOTNET_DIR"
  INSTALLER=$(mktemp "${TMPDIR:-/tmp}/dotnet-install.XXXXXX") || { say "could not create a temp file"; exit 1; }
  act curl -fsSL --proto '=https' --proto-redir '=https' https://dot.net/v1/dotnet-install.sh -o "$INSTALLER" ||
    { say "could not download dotnet-install.sh"; rm -f "$INSTALLER"; exit 1; }
  act bash "$INSTALLER" --channel "$CHANNEL" --install-dir "$DOTNET_DIR" >&2 || { say "dotnet-install.sh failed (channel $CHANNEL)"; rm -f "$INSTALLER"; exit 1; }
  rm -f "$INSTALLER"
  PATH="$DOTNET_DIR:$DOTNET_DIR/tools:$PATH"
  if [ "$DRY" != 1 ] && ! command -v dotnet >/dev/null 2>&1; then
    say "the SDK installed, but dotnet is still not runnable from $DOTNET_DIR"
    exit 1
  fi
fi

STRYKER_CFG=$(find . -maxdepth 4 \( -name node_modules -o -name .git -o -name bin -o -name obj \) -prune -o \
  -type f -name 'stryker-config*.json' -print 2>/dev/null | sed -n 1p)
if [ -n "$STRYKER_CFG" ]; then
  if [ -f .config/dotnet-tools.json ] && grep -q 'dotnet-stryker' .config/dotnet-tools.json; then
    act dotnet tool restore >&2 || { say "dotnet tool restore failed"; exit 1; }
  elif [ "$DRY" = 1 ] || ! grep -q dotnet-stryker <<< "$(dotnet tool list -g 2>/dev/null)"; then
    act dotnet tool install -g dotnet-stryker >&2 || { say "could not install dotnet-stryker"; exit 1; }
  fi
fi

echo "export PATH=\"$DOTNET_DIR:$DOTNET_DIR/tools:\$PATH\""
say "ready."
