#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Self-test for spec 082 R1-R4 in scripts/template-autosync.sh (F037, F045).
#
# What the sync may ship into a project, and from where:
#
#   R1  the remote tarball is fetched by the exact 40-hex SHA ls-remote named, never by
#       refs/heads/main — two reads of a moving ref can stamp one commit and ship another
#   R2  CLAUDE_TEMPLATE_PIN holds a project on one commit: a clean clone at exactly that commit, or
#       the remote tarball of that commit; anything that is not 40 hex is refused
#   R3  a template clone with uncommitted changes is not synced (082-AC-1) unless --force or
#       CLAUDE_TEMPLATE_ALLOW_DIRTY=1 says the author means it
#   R4  a symlink in the template tree is never followed into a project; any symlink under the
#       synced roots refuses the sync whole (H2 adversarial finding 7, a symlinked DIRECTORY)
#   F16 the remote tarball is downloaded to a file over https only, and its pax commit id must be
#       the SHA it was asked for before anything is extracted (H2 adversarial finding 16)
#
# Fixture-only: `git ls-remote` and `curl` are PATH shims that log what they were asked, and every
# run goes through drive-sync.sh with HOME pointed into the scratch dir, so no real clone under
# ~/repos is ever a candidate. Nothing touches the network.
#
# Run: bash scripts/test-template-autosync-supply-chain.sh
# SUPPLY_TEST_SCRIPT selects the script under test (used to sabotage-check the arms).

set -u
unset CDPATH
cd "$(dirname "$0")/.." || exit 1
SCRIPT="${SUPPLY_TEST_SCRIPT:-$PWD/scripts/template-autosync.sh}"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found at $SCRIPT"; exit 1; }
. "$PWD/scripts/drive-sync.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

REAL_GIT=$(command -v git)
SHIMS="$TMP/shims"; mkdir -p "$SHIMS"
# git: ls-remote answers $FAKE_LSREMOTE and is logged; everything else is the real git.
cat > "$SHIMS/git" <<EOF
#!/bin/bash
if [ "\${1:-}" = ls-remote ]; then
  echo "ls-remote \$*" >> "\$SHIM_LOG"
  [ -n "\${FAKE_LSREMOTE:-}" ] && printf '%s\trefs/heads/main\n' "\$FAKE_LSREMOTE"
  exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
# curl: logs its arguments and writes the fixture tarball to -o, as a GitHub archive does: a pax
# global header whose comment is the commit (what `git get-tar-commit-id` reads). The commit is the
# SHA at the end of the URL unless FAKE_TAR_ID names another, which is the forged-tarball case.
cat > "$SHIMS/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$SHIM_LOG"
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; http*) url="$1" ;; esac
  shift
done
[ -n "$out" ] || { echo "fake curl: no -o (the sync must download to a file)" >&2; exit 2; }
id="${FAKE_TAR_ID-${url##*/}}"
exec python3 "$FAKE_TAR_MAKER" "$out" "$FAKE_TAR_ROOT" "$id"
EOF
cat > "$SHIMS/make-tar.py" <<'EOF'
import os, sys, tarfile
out, root, cid = sys.argv[1:4]
hdr = {"comment": cid} if cid else {}
with tarfile.open(out, "w:gz", format=tarfile.PAX_FORMAT, pax_headers=hdr) as t:
    for name in sorted(os.listdir(root)):
        t.add(os.path.join(root, name), arcname=name)
EOF
chmod +x "$SHIMS/git" "$SHIMS/curl"

FULL_A=0123456789abcdef0123456789abcdef01234567
FULL_B=89abcdef0123456789abcdef0123456789abcdef

# A template clone and a project, both git repositories (the shape test-template-autosync-arms.sh
# uses). The template ships the sync itself, one CORE rule and sync-prompt.md, which together are
# what makes a directory a template candidate. The rule must be CORE: a non-CORE file the project
# does not already have is never added, and an assertion on it would pass against any script.
build() {
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R/home"
  T="$R/template"; P="$R/project"; H="$R/home"; LOG="$R/shim.log"; : > "$LOG"
  mkdir -p "$T/scripts" "$T/.claude/rules" "$T/.claude/docs"
  cp "$SCRIPT" "$T/scripts/template-autosync.sh"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'rule v1\n' > "$T/.claude/rules/allium.md"
  "$REAL_GIT" -C "$T" init -q -b main
  "$REAL_GIT" -C "$T" add -A; "$REAL_GIT" -C "$T" commit -qm template

  mkdir -p "$P/.claude/rules" "$P/scripts"
  echo '{"name":"fake"}' > "$P/package.json"
  cp "$SCRIPT" "$P/scripts/template-autosync.sh"
  "$REAL_GIT" -C "$P" init -q -b main
  "$REAL_GIT" -C "$P" add -A; "$REAL_GIT" -C "$P" commit -qm project
  P_HEAD0=$("$REAL_GIT" -C "$P" rev-parse HEAD)

  # The tarball a remote fetch serves: a copy of the template's tree, named as codeload names it.
  TAR="$R/tar"; mkdir -p "$TAR/Claude-fixture"
  (cd "$T" && tar -cf - --exclude .git .) | (cd "$TAR/Claude-fixture" && tar -xf -)
}

# Local path: CLAUDE_TEMPLATE_DIR names the clone. Remote path: no clone anywhere.
sync_local()  { HOME="$H" PATH="$SHIMS:$PATH" SHIM_LOG="$LOG" FAKE_TAR_ROOT="$TAR" FAKE_TAR_MAKER="$SHIMS/make-tar.py" CLAUDE_TEMPLATE_DIR="$T" \
                  DRIVE_SYNC_SCRIPT="$SCRIPT" drive_sync "$P" "$R" "$@" 2>&1; }
sync_remote() { HOME="$H" PATH="$SHIMS:$PATH" SHIM_LOG="$LOG" FAKE_TAR_ROOT="$TAR" FAKE_TAR_MAKER="$SHIMS/make-tar.py" CLAUDE_TEMPLATE_DIR="" \
                  DRIVE_SYNC_SCRIPT="$SCRIPT" drive_sync "$P" "$R" "$@" 2>&1; }
stamp_sha()   { sed -n 's/^sha=//p' "$P/.claude/.template-sync" 2>/dev/null | sed -n 1p; }
p_head()      { "$REAL_GIT" -C "$P" rev-parse HEAD; }

echo "== R1 — the remote tarball is the commit ls-remote named"
build r1
OUT=$(FAKE_LSREMOTE=$FULL_A sync_remote); RC=$?
same  "R1 exit 0"                                 "$RC" 0
has   "R1 curl asked for tar.gz/<full sha>"        "$(cat "$LOG")" "tar.gz/$FULL_A"
hasnt "R1 curl never asked for refs/heads/main"    "$(cat "$LOG")" "refs/heads/main"
same  "R1 stamp is the 12-char prefix of that sha" "$(stamp_sha)" "$(printf %s "$FULL_A" | cut -c1-12)"
[ -f "$P/.claude/rules/allium.md" ] && ok "R1 the tarball's files were synced" || bad "R1 the tarball's files were synced"

echo "== R1 — an answer that is not a 40-hex SHA downloads nothing"
build r1b
OUT=$(FAKE_LSREMOTE=zzzz456789abcdef0123456789abcdef0123zzzz sync_remote); RC=$?
same  "R1b exit 0 (fails open)"           "$RC" 0
hasnt "R1b curl was never called"          "$(cat "$LOG")" "curl"
has   "R1b says why"                       "$OUT" "not a 40-hex SHA"
same  "R1b nothing committed"              "$(p_head)" "$P_HEAD0"
OUT=$(FAKE_LSREMOTE=0123456789abcdef sync_remote); RC=$?
hasnt "R1b a short SHA downloads nothing"  "$(cat "$LOG")" "curl"

echo "== R2 — a pin that is not 40 hex is refused"
build r2a
OUT=$(CLAUDE_TEMPLATE_PIN=v1.2.3 sync_local); RC=$?
same  "R2a exit 0"                         "$RC" 0
has   "R2a the warning names the variable" "$OUT" "CLAUDE_TEMPLATE_PIN"
same  "R2a nothing committed"              "$(p_head)" "$P_HEAD0"
[ -f "$P/.claude/rules/allium.md" ] && bad "R2a nothing written" || ok "R2a nothing written"
hasnt "R2a no download either"             "$(cat "$LOG")" "curl"

echo "== R2 — a pin equal to a clean clone's HEAD uses the clone"
build r2b
PIN=$("$REAL_GIT" -C "$T" rev-parse HEAD)
OUT=$(CLAUDE_TEMPLATE_PIN=$PIN sync_local); RC=$?
same  "R2b exit 0"                         "$RC" 0
same  "R2b stamp is the clone's commit"    "$(stamp_sha)" "$(printf '%s' "$PIN" | cut -c1-12)"
hasnt "R2b no download"                    "$(cat "$LOG")" "curl"
hasnt "R2b no ls-remote"                   "$(cat "$LOG")" "ls-remote"

echo "== R2 — the pin is case-insensitive"
build r2u
PIN=$("$REAL_GIT" -C "$T" rev-parse HEAD | tr 'a-f' 'A-F')
OUT=$(CLAUDE_TEMPLATE_PIN=$PIN sync_local); RC=$?
same  "R2u upper-case pin matches the clone" "$(stamp_sha)" "$(printf '%s' "$PIN" | tr 'A-F' 'a-f' | cut -c1-12)"
hasnt "R2u no download"                      "$(cat "$LOG")" "curl"

echo "== R2 — a pin the clone is not at is fetched from the remote, by that SHA"
build r2c
OUT=$(CLAUDE_TEMPLATE_PIN=$FULL_B FAKE_LSREMOTE=$FULL_A sync_local); RC=$?
same  "R2c exit 0"                          "$RC" 0
has   "R2c curl asked for tar.gz/<pin>"      "$(cat "$LOG")" "tar.gz/$FULL_B"
hasnt "R2c not main's SHA"                   "$(cat "$LOG")" "tar.gz/$FULL_A"
hasnt "R2c no ls-remote needed"              "$(cat "$LOG")" "ls-remote"
same  "R2c stamp is the pin"                 "$(stamp_sha)" "$(printf '%s' "$FULL_B" | cut -c1-12)"

echo "== R2 — a pinned clone that is dirty is not used either"
build r2d
PIN=$("$REAL_GIT" -C "$T" rev-parse HEAD)
echo scratch >> "$T/.claude/rules/allium.md"
OUT=$(CLAUDE_TEMPLATE_PIN=$PIN sync_local); RC=$?
has   "R2d fetched the pin from the remote" "$(cat "$LOG")" "tar.gz/$PIN"
hasnt "R2d the scratch edit did not ship"   "$(cat "$P/.claude/rules/allium.md" 2>/dev/null)" "scratch"

echo "== R3 — 082-AC-1: a dirty template clone does not reach the projects"
build ac1
echo '# half-written' >> "$T/scripts/template-autosync.sh"
OUT=$(sync_local); RC=$?
same  "082-AC-1 exit 0"                                   "$RC" 0
same  "082-AC-1 no commit in the project"                 "$(p_head)" "$P_HEAD0"
same  "082-AC-1 the project tree is untouched"            "$("$REAL_GIT" -C "$P" status --porcelain)" ""
[ -f "$P/.claude/rules/allium.md" ] && bad "082-AC-1 no file written" || ok "082-AC-1 no file written"
same  "082-AC-1 the half-written CORE edit did not ship"  "$(grep -c '# half-written' "$P/scripts/template-autosync.sh")" 0
has   "082-AC-1 the warning names the clone"              "$OUT" "template clone at $T has uncommitted changes — not synced"
has   "082-AC-1 the warning names --force"                "$OUT" "--force"
has   "082-AC-1 the warning names CLAUDE_TEMPLATE_ALLOW_DIRTY=1" "$OUT" "CLAUDE_TEMPLATE_ALLOW_DIRTY=1"
hasnt "082-AC-1 no remote fallback either"                "$(cat "$LOG")" "curl"

echo "== R3 — an untracked file counts as uncommitted"
build r3u
echo x > "$T/.claude/rules/scratch.md"
OUT=$(sync_local); RC=$?
same  "R3u no commit" "$(p_head)" "$P_HEAD0"
has   "R3u refused"   "$OUT" "not synced"

echo "== R3 — CLAUDE_TEMPLATE_ALLOW_DIRTY=1 restores the -dirty- sync"
build r3a
echo 'rule v2-wip' > "$T/.claude/rules/allium.md"
OUT=$(CLAUDE_TEMPLATE_ALLOW_DIRTY=1 sync_local); RC=$?
same  "R3a exit 0"                    "$RC" 0
same  "R3a the WIP shipped"           "$(cat "$P/.claude/rules/allium.md" 2>/dev/null)" "rule v2-wip"
has   "R3a stamped -dirty-"           "$(stamp_sha)" "-dirty-"
hasnt "R3a not refused"               "$OUT" "not synced"

echo "== R3 — --force does too"
build r3f
echo 'rule v2-wip' > "$T/.claude/rules/allium.md"
OUT=$(sync_local --force); RC=$?
same  "R3f the WIP shipped"           "$(cat "$P/.claude/rules/allium.md" 2>/dev/null)" "rule v2-wip"
has   "R3f stamped -dirty-"           "$(stamp_sha)" "-dirty-"

echo "== R3 — a clean clone is unaffected"
build r3c
OUT=$(sync_local); RC=$?
same  "R3c synced"                    "$(cat "$P/.claude/rules/allium.md" 2>/dev/null)" "rule v1"
hasnt "R3c no -dirty- stamp"          "$(stamp_sha)" "-dirty-"

# R4 + H2 adversarial finding 7. A file symlink now refuses the whole tree: copy_file's per-file
# skip only ever saw leaves, and every copy source is under .claude/ or scripts/, which the tree
# check walks first. The per-file skip stays behind it as defence in depth.
echo "== R4 — a symlinked file in the template refuses the sync"
build r4
echo 'PRIVATE KEY' > "$R/secret"
ln -s "$R/secret" "$T/.claude/rules/tests.md"
ln -s "$R/secret" "$T/scripts/finding.sh"
"$REAL_GIT" -C "$T" add -A; "$REAL_GIT" -C "$T" commit -qm symlinks
OUT=$(sync_local); RC=$?
same  "R4 exit 0"                              "$RC" 0
[ -e "$P/.claude/rules/tests.md" ] && bad "R4 rule symlink not copied" || ok "R4 rule symlink not copied"
[ -e "$P/scripts/finding.sh" ] && bad "R4 script symlink not copied" || ok "R4 script symlink not copied"
hasnt "R4 the target's bytes reached nothing"  "$(grep -rl 'PRIVATE KEY' "$P" 2>/dev/null)" "$P"
has   "R4 says the tree has symlinks"          "$OUT" "symlinks in the synced tree — not synced"
has   "R4 names the link"                      "$OUT" ".claude/rules/tests.md"
same  "R4 nothing committed"                   "$(p_head)" "$P_HEAD0"

echo "== F7 — a symlinked DIRECTORY in the template refuses the sync"
build f7
mkdir -p "$R/vault"; echo 'PRIVATE KEY' > "$R/vault/secret.txt"
mkdir -p "$T/.claude/skills"; ln -s "$R/vault" "$T/.claude/skills/x"
"$REAL_GIT" -C "$T" add -A; "$REAL_GIT" -C "$T" commit -qm 'dir symlink'
OUT=$(sync_local); RC=$?
same  "F7 exit 0"                              "$RC" 0
hasnt "F7 the secret reached nothing"          "$(grep -rl 'PRIVATE KEY' "$P" 2>/dev/null)" "$P"
[ -e "$P/.claude/skills/x/secret.txt" ] && bad "F7 secret.txt not copied" || ok "F7 secret.txt not copied"
has   "F7 refused, naming the link"            "$OUT" ".claude/skills/x"
same  "F7 nothing committed"                   "$(p_head)" "$P_HEAD0"
same  "F7 the project tree is untouched"       "$("$REAL_GIT" -C "$P" status --porcelain)" ""

echo "== F7 — a symlinked .claude root refuses the sync"
build f7r
mv "$T/.claude" "$R/real-claude"; ln -s "$R/real-claude" "$T/.claude"
"$REAL_GIT" -C "$T" add -A; "$REAL_GIT" -C "$T" commit -qm 'root symlink'
OUT=$(sync_local); RC=$?
same  "F7r exit 0"                             "$RC" 0
has   "F7r refused"                            "$OUT" "symlinks in the synced tree — not synced"
same  "F7r nothing committed"                  "$(p_head)" "$P_HEAD0"

echo "== F7 — agent worktrees under .claude/worktrees are not the synced tree"
build f7w
echo '.claude/worktrees/' >> "$T/.gitignore"; "$REAL_GIT" -C "$T" add -A; "$REAL_GIT" -C "$T" commit -qm 'ignore worktrees'
mkdir -p "$T/.claude/worktrees/agent-a/node_modules/.bin"; ln -s ../x/cli.js "$T/.claude/worktrees/agent-a/node_modules/.bin/x"
OUT=$(sync_local); RC=$?
same  "F7w exit 0"                             "$RC" 0
hasnt "F7w an agent checkout's link does not refuse the sync" "$OUT" "symlinks in the synced tree"

echo "== F7 — the query modes need no tree check"
OUT=$(CLAUDE_TEMPLATE_DIR="$T" HOME="$H" CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT" --is-core scripts/finding.sh 2>&1); RC=$?
same  "F7q --is-core still answers CORE"       "$RC" 0

echo "== F16 — the remote tarball is downloaded to a file, over https only"
build f16
OUT=$(FAKE_LSREMOTE=$FULL_A sync_remote); RC=$?
has   "F16 curl wrote to a file (-o)"          "$(cat "$LOG")" " -o "
has   "F16 curl is held to https"              "$(cat "$LOG")" "--proto =https --proto-redir =https"
same  "F16 the named commit's tarball syncs"   "$(cat "$P/.claude/rules/allium.md" 2>/dev/null)" "rule v1"

echo "== F16 — a tarball that says it is another commit is not extracted"
build f16m
OUT=$(FAKE_TAR_ID=$FULL_B FAKE_LSREMOTE=$FULL_A sync_remote); RC=$?
same  "F16m exit 0 (fails open)"               "$RC" 0
has   "F16m says which commit it claimed"      "$OUT" "says it is commit '$FULL_B', not $FULL_A"
[ -f "$P/.claude/rules/allium.md" ] && bad "F16m nothing synced" || ok "F16m nothing synced"
same  "F16m nothing committed"                 "$(p_head)" "$P_HEAD0"
hasnt "F16m no stamp"                          "$(stamp_sha)" "$(printf %s "$FULL_A" | cut -c1-12)"

echo "== F16 — a tarball with no commit id is not extracted"
build f16n
OUT=$(FAKE_TAR_ID= FAKE_LSREMOTE=$FULL_A sync_remote); RC=$?
has   "F16n says the id is missing"            "$OUT" "says it is commit 'none'"
[ -f "$P/.claude/rules/allium.md" ] && bad "F16n nothing synced" || ok "F16n nothing synced"

echo
echo "template-autosync supply chain: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
