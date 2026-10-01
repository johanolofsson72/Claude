#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Self-test for spec 082 R9 in scripts/lane-catchup.sh (F063).
#
#   bash scripts/test-lane-catchup.sh
#
# What is under test: --apply removes the Read(~/…)/Edit(~/…) deny rules that make ordinary commands
# prompt, and never the ones guarding a credential store; it backs the file up first and replaces it
# atomically with its mode intact; a file it cannot parse is left exactly as it was.
#
# Cases: 082-AC-3 (lane-catchup keeps credential denies).
#
# Fixture-only: HOME is a temp dir and the script runs inside a throwaway git repo with no scripts/,
# so every later step finds nothing to run. No network, no crontab. bash 3.2-safe.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$DIR/lane-catchup.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/lane-catchup-test.$$")
mkdir -p "$TMP"
PASS=0
FAIL=0
trap 'rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
expect_contains() { if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "contains: $2" "$3"; fi; }
expect_absent()   { if grep -Fq -e "$2" <<< "$3"; then bad "$1" "absent: $2" "$3"; else ok "$1"; fi; }

command -v python3 >/dev/null 2>&1 || { echo "SKIP — python3 not installed"; exit 0; }

REPO="$TMP/repo"
mkdir -p "$REPO" && ( cd "$REPO" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )

# run HOME [args] -> output; the repo has no remote, so `git fetch` fails and is ignored.
run() { local h="$1"; shift; ( cd "$REPO" && HOME="$h" GIT_TERMINAL_PROMPT=0 bash "$SCRIPT" "$@" 2>&1 ); }
denies() { python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1]))["permissions"]["deny"]))' "$1"; }
mode_of() { python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"; }
backups() { ls "$1"/.claude/settings.json.bak-* 2>/dev/null; }

mkhome() { # mkhome NAME JSON -> home path
  local h="$TMP/$1"; mkdir -p "$h/.claude"; printf '%s\n' "$2" > "$h/.claude/settings.json"; printf '%s' "$h"
}

echo "lane-catchup.sh — permission denies (spec 082 R9)"

AC3='{"permissions":{"deny":["Read(~/.ssh/**)","Read(~/.aws/**)","Read(~/Documents/**)","Bash(rm -rf *)"]}}'

# --- 082-AC-3: credential denies kept, the rest removed, a backup that equals the original --------
H=$(mkhome ac3 "$AC3")
ORIG=$(cat "$H/.claude/settings.json")
chmod 600 "$H/.claude/settings.json"
OUT=$(run "$H" --apply)
D=$(denies "$H/.claude/settings.json")
expect_contains "082-AC-3 Read(~/.ssh/**) kept"             "Read(~/.ssh/**)" "$D"
expect_contains "082-AC-3 Read(~/.aws/**) kept"             "Read(~/.aws/**)" "$D"
expect_absent   "082-AC-3 Read(~/Documents/**) removed"     "Read(~/Documents/**)" "$D"
expect_contains "082-AC-3 Bash denies untouched"            "Bash(rm -rf *)" "$D"
B=$(backups "$H")
expect_eq       "082-AC-3 exactly one timestamped backup"   "1" "$(printf '%s' "$B" | grep -c .)"
case "$B" in *settings.json.bak-[0-9]*T[0-9]*Z) ok "082-AC-3 backup name is .bak-<UTC stamp>" ;;
  *) bad "082-AC-3 backup name is .bak-<UTC stamp>" "settings.json.bak-YYYYmmddTHHMMSSZ" "$B" ;; esac
expect_eq       "082-AC-3 backup equals the original"       "$ORIG" "$(cat "$B" 2>/dev/null)"
expect_eq       "R9 mode 600 preserved on the rewritten file" "0o600" "$(mode_of "$H/.claude/settings.json")"
expect_eq       "R9 mode 600 preserved on the backup"       "0o600" "$(mode_of "$B")"
expect_contains "R9 report names the removed rule"          "Read(~/Documents/**)" "$OUT"
expect_contains "R9 report names a kept credential rule"    "Read(~/.ssh/**)" "$OUT"
expect_contains "R9 report says why they are kept"          "credential store" "$OUT"
expect_eq       "R9 no temp file left in ~/.claude"         "" "$(ls -A "$H/.claude" | grep -v '^settings.json' )"

# --- idempotent: a second run changes nothing and writes no second backup ------------------------
BEFORE=$(cat "$H/.claude/settings.json")
OUT2=$(run "$H" --apply)
expect_eq       "R9 second run leaves the file as it was"   "$BEFORE" "$(cat "$H/.claude/settings.json")"
expect_eq       "R9 second run writes no second backup"     "1" "$(backups "$H" | grep -c .)"
expect_contains "R9 second run says nothing is removable"   "no removable" "$OUT2"

# --- the whole credential family, every spelling the rule names ---------------------------------
ALL='{"permissions":{"deny":["Read(~/.ssh/id_ed25519)","Edit(~/.aws/credentials)","Read(~/.gnupg/**)","Read(~/.kube/config)","Read(~/.docker/config.json)","Read(~/.azure/**)","Read(~/.config/gh/hosts.yml)","Read(~/.config/gcloud/**)","Read(~/.netrc)","Read(~/.npmrc)","Read(~/.pypirc)","Read(~/.git-credentials)","Read(~/.password-store/**)","Read(~/.sshfoo/x)","Read(~/notes/.aws-ideas.md)","Edit(~/.config/other/**)"]}}'
H=$(mkhome all "$ALL")
run "$H" --apply >/dev/null
D=$(denies "$H/.claude/settings.json")
expect_eq       "R9 all 13 credential stores kept"          "13" "$(printf '%s\n' "$D" | grep -c .)"
expect_absent   "R9 ~/.sshfoo is not .ssh"                  "Read(~/.sshfoo/x)" "$D"
expect_absent   "R9 .aws-ideas.md is not .aws"              "Read(~/notes/.aws-ideas.md)" "$D"
expect_absent   "R9 .config/other is not .config/gh"        "Edit(~/.config/other/**)" "$D"

# --- only credential denies: no change, no backup -----------------------------------------------
H=$(mkhome credonly '{"permissions":{"deny":["Read(~/.ssh/**)"]}}')
ORIG=$(cat "$H/.claude/settings.json")
run "$H" --apply >/dev/null
expect_eq       "R9 credential-only file untouched"         "$ORIG" "$(cat "$H/.claude/settings.json")"
expect_eq       "R9 credential-only file gets no backup"    "" "$(backups "$H")"

# --- malformed JSON: reported, unchanged, no backup ---------------------------------------------
H=$(mkhome bad '{"permissions": {"deny": ["Read(~/Documents/**)",')
ORIG=$(cat "$H/.claude/settings.json")
OUT=$(run "$H" --apply)
expect_eq       "R9 malformed JSON left byte-identical"     "$ORIG" "$(cat "$H/.claude/settings.json")"
expect_eq       "R9 malformed JSON gets no backup"          "" "$(backups "$H")"
expect_contains "R9 malformed JSON is reported"             "could not be read" "$OUT"

# --- report mode changes nothing ---------------------------------------------------------------
H=$(mkhome report "$AC3")
ORIG=$(cat "$H/.claude/settings.json")
OUT=$(run "$H")
expect_eq       "R9 report mode changes nothing"            "$ORIG" "$(cat "$H/.claude/settings.json")"
expect_eq       "R9 report mode writes no backup"           "" "$(backups "$H")"
expect_contains "R9 report mode lists what --apply removes" "Read(~/Documents/**)" "$OUT"

# --- F5 (adversarial review): a broad glob guards every store, so it is kept -------------------
BROAD='{"permissions":{"deny":["Read(~/**)","Read(~/.*)","Read(~/.s*)","Edit(~/**)","Read(~/Documents/**)"]}}'
H=$(mkhome broad "$BROAD")
run "$H" --apply >/dev/null
D=$(denies "$H/.claude/settings.json")
expect_contains "F5 Read(~/**) kept (matches ~/.ssh/id_ed25519)"  "Read(~/**)" "$D"
expect_contains "F5 Read(~/.*) kept"                              "Read(~/.*)" "$D"
expect_contains "F5 Read(~/.s*) kept (matches ~/.ssh)"            "Read(~/.s*)" "$D"
expect_contains "F5 Edit(~/**) kept"                              "Edit(~/**)" "$D"
expect_absent   "F5 Read(~/Documents/**) still removed"           "Read(~/Documents/**)" "$D"

# --- F5: the stores the first list missed --------------------------------------------------------
MORE='{"permissions":{"deny":["Read(~/.pgpass)","Read(~/.vault-token)","Read(~/.cargo/credentials.toml)","Read(~/.config/op/**)","Read(~/.claude/.credentials.json)","Read(~/Library/Keychains/**)","Read(~/Pictures/**)"]}}'
H=$(mkhome more "$MORE")
run "$H" --apply >/dev/null
D=$(denies "$H/.claude/settings.json")
expect_eq       "F5 six extra credential stores kept"  "6" "$(printf '%s\n' "$D" | grep -c .)"
expect_absent   "F5 Read(~/Pictures/**) removed"       "Read(~/Pictures/**)" "$D"

# --- F5: a dotfile-managed symlink stays a symlink; the real file is rewritten and backed up --------
H="$TMP/symhome"; mkdir -p "$H/.claude" "$H/dotfiles"
printf '%s\n' "$AC3" > "$H/dotfiles/settings.json"
ln -s "$H/dotfiles/settings.json" "$H/.claude/settings.json"
run "$H" --apply >/dev/null
if [ -L "$H/.claude/settings.json" ]; then ok "F5 symlinked settings.json is still a symlink"
else bad "F5 symlinked settings.json is still a symlink" "symlink" "regular file"; fi
D=$(denies "$H/dotfiles/settings.json")
expect_absent   "F5 the symlink target was rewritten"  "Read(~/Documents/**)" "$D"
expect_contains "F5 the target kept .ssh"              "Read(~/.ssh/**)" "$D"
expect_eq       "F5 backup sits beside the real file"  "1" "$(ls "$H"/dotfiles/settings.json.bak-* 2>/dev/null | grep -c .)"

echo
echo "lane-catchup: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
