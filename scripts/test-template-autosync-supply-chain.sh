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
for a in "\$@"; do [ "\$a" = checkout-index ] && [ -n "\${FAKE_CHECKOUT_FAIL:-}" ] && exit 1; done
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
# Spec 091 R3: GitHub's compare API. FAKE_COMPARE_STATUS is what it says about <pin>...main (default
# ahead, with the pin as merge base); `none` is no answer at all; FAKE_COMPARE_BASE overrides the base.
case "$url" in
  https://api.github.com/repos/johanolofsson72/Claude/compare/*)
    pin=${url##*/compare/}; pin=${pin%%...*}
    st="${FAKE_COMPARE_STATUS:-ahead}"
    [ "$st" = none ] && exit 7
    if [ "$st" = ratelimit ]; then
      printf '{"message":"API rate limit exceeded"}' > "$out"; printf 403; exit 0
    fi
    printf '{"url":"x","base_commit":{"sha":"%s"},"merge_base_commit":{"sha":"%s"},"status":"%s","files":[{"status":"ahead"}]}' \
      "$pin" "${FAKE_COMPARE_BASE:-$pin}" "$st" > "$out"
    printf 200; exit 0 ;;
esac
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
  # A real clone has origin/main; spec 091 R3 asks the pin's ancestry against it, without a fetch.
  "$REAL_GIT" -C "$T" update-ref refs/remotes/origin/main HEAD
  # ...and the template's URL as origin (091 adversarial B7), fetched from the clone itself so a
  # refresh never reaches the network.
  "$REAL_GIT" -C "$T" remote add origin https://github.com/johanolofsson72/Claude.git
  "$REAL_GIT" -C "$T" config "url.$T.insteadOf" https://github.com/johanolofsson72/Claude.git

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

echo "== 091 R3 — 091-AC-2: a pin off the template's main is never synced"
build ac2
OUT=$(CLAUDE_TEMPLATE_PIN=$FULL_B FAKE_COMPARE_STATUS=diverged sync_remote); RC=$?
same  "091-AC-2 exit 0"                                  "$RC" 0
has   "091-AC-2 GitHub's compare API was asked about the pin" "$(cat "$LOG")" "compare/$FULL_B...main"
hasnt "091-AC-2 nothing was downloaded"                  "$(cat "$LOG")" "tar.gz"
same  "091-AC-2 no commit in the project"                "$(p_head)" "$P_HEAD0"
same  "091-AC-2 the project tree is untouched"           "$("$REAL_GIT" -C "$P" status --porcelain)" ""
has   "091-AC-2 the warning says why"                    "$OUT" "cannot show CLAUDE_TEMPLATE_PIN $(printf '%s' "$FULL_B" | cut -c1-12) is on the template's main (GitHub compares it to main as diverged)"
build ac2b
OUT=$(CLAUDE_TEMPLATE_PIN=$FULL_B sync_remote); RC=$?
has   "091-AC-2 a pin GitHub reports behind main syncs as before" "$(cat "$LOG")" "tar.gz/$FULL_B"
same  "091-AC-2 its stamp is the pin"                    "$(stamp_sha)" "$(printf '%s' "$FULL_B" | cut -c1-12)"
build r3x
OUT=$(CLAUDE_TEMPLATE_PIN=$FULL_B FAKE_COMPARE_STATUS=identical sync_remote)
has   "R3 identical counts as on main"                   "$(cat "$LOG")" "tar.gz/$FULL_B"
for st in behind none ratelimit; do
  build "r3$st"
  OUT=$(CLAUDE_TEMPLATE_PIN=$FULL_B FAKE_COMPARE_STATUS=$st sync_remote)
  hasnt "R3 '$st' downloads nothing"                     "$(cat "$LOG")" "tar.gz"
  has   "R3 '$st' says it was not synced"                "$OUT" "not synced"
done
has   "R3 a rate limit names GitHub's message"           "$OUT" "API rate limit exceeded"
build r3base
OUT=$(CLAUDE_TEMPLATE_PIN=$FULL_B FAKE_COMPARE_BASE=$FULL_A sync_remote)
hasnt "R3 ahead with another merge base is no proof"     "$(cat "$LOG")" "tar.gz"
build r3clone
"$REAL_GIT" -C "$T" commit -q --allow-empty -m "local, not on main"
PIN=$("$REAL_GIT" -C "$T" rev-parse HEAD)
OUT=$(CLAUDE_TEMPLATE_PIN=$PIN FAKE_COMPARE_STATUS=diverged sync_local); RC=$?
has   "R3 a clone at a pin its origin/main lacks asks GitHub" "$(cat "$LOG")" "compare/$PIN...main"
hasnt "R3 and, refused there, downloads nothing"         "$(cat "$LOG")" "tar.gz"
same  "R3 and writes nothing"                            "$(p_head)" "$P_HEAD0"

build r3fork
PIN=$("$REAL_GIT" -C "$T" rev-parse HEAD)
"$REAL_GIT" -C "$T" remote set-url origin https://github.com/someone/Claude-fork.git
OUT=$(CLAUDE_TEMPLATE_PIN=$PIN FAKE_COMPARE_STATUS=diverged sync_local); RC=$?
has   "B7 a clean clone at the pin whose origin is a fork asks GitHub" "$(cat "$LOG")" "compare/$PIN...main"
hasnt "B7 and, refused there, downloads nothing"         "$(cat "$LOG")" "tar.gz"
same  "B7 and writes nothing"                            "$(p_head)" "$P_HEAD0"

echo "== 091 R4 — a clean clone ships its committed bytes"
build r4s
"$REAL_GIT" -C "$T" update-index --skip-worktree .claude/rules/allium.md
printf 'rule v1\nplanted under skip-worktree\n' > "$T/.claude/rules/allium.md"
same  "R4 git status calls the clone clean"              "$("$REAL_GIT" -C "$T" status --porcelain)" ""
OUT=$(sync_local); RC=$?
same  "R4 exit 0"                                        "$RC" 0
same  "R4 the skip-worktree file ships its committed bytes" "$(cat "$P/.claude/rules/allium.md" 2>/dev/null)" "rule v1"
has   "R4 the warning names the path"                    "$OUT" ".claude/rules/allium.md"
has   "R4 the warning says why"                          "$OUT" "skip-worktree or assume-unchanged"
build r4a
"$REAL_GIT" -C "$T" update-index --assume-unchanged .claude/rules/allium.md
printf 'rule v1\nplanted under assume-unchanged\n' > "$T/.claude/rules/allium.md"
OUT=$(sync_local)
same  "R4 an assume-unchanged file ships its committed bytes" "$(cat "$P/.claude/rules/allium.md" 2>/dev/null)" "rule v1"
build r4i
mkdir -p "$T/.claude/skills/demo"
printf -- '---\nname: demo\n---\nbody\n' > "$T/.claude/skills/demo/SKILL.md"
printf '.claude/skills/demo/secret.md\n' > "$T/.gitignore"
"$REAL_GIT" -C "$T" add -A; "$REAL_GIT" -C "$T" commit -qm skills; "$REAL_GIT" -C "$T" update-ref refs/remotes/origin/main HEAD
printf 'ignored, never committed\n' > "$T/.claude/skills/demo/secret.md"
same  "R4 the ignored file leaves the clone clean"       "$("$REAL_GIT" -C "$T" status --porcelain)" ""
OUT=$(sync_local)
[ -f "$P/.claude/skills/demo/SKILL.md" ] && ok "R4 the tracked skill file ships" || bad "R4 the tracked skill file did not ship ($(printf '%s' "$OUT" | tail -3 | tr '\n' '|'))"
[ -e "$P/.claude/skills/demo/secret.md" ] && bad "R4 an ignored file under .claude/skills shipped" || ok "R4 an ignored file under .claude/skills is not shipped"

build r3anc
PIN=$("$REAL_GIT" -C "$T" rev-parse HEAD)
"$REAL_GIT" -C "$T" commit -q --allow-empty -m "one more on main"
"$REAL_GIT" -C "$T" update-ref refs/remotes/origin/main HEAD
OUT=$(CLAUDE_TEMPLATE_PIN=$PIN sync_local)
has   "R3 a clean template clone whose HEAD is past the pin is not the pin: the pin is downloaded" "$(cat "$LOG")" "tar.gz/$PIN"

build r4f
"$REAL_GIT" -C "$T" update-index --skip-worktree .claude/rules/allium.md
printf 'rule v1\nplanted\n' > "$T/.claude/rules/allium.md"
OUT=$(FAKE_CHECKOUT_FAIL=1 sync_local); RC=$?
same  "R4 a flagged path that cannot be staged: exit 0"  "$RC" 0
has   "R4 ... the clone is refused, not synced"          "$OUT" "not synced"
same  "R4 ... and nothing is written"                    "$(p_head)" "$P_HEAD0"
[ -f "$P/.claude/rules/allium.md" ] && bad "R4 the planted bytes shipped" || ok "R4 the planted bytes did not ship"

build r4t
mkdir -p "$T/.claude/skills/demo" "$TAR/Claude-fixture/.claude/skills/demo"
printf -- '---\nname: demo\n---\nbody\n' > "$T/.claude/skills/demo/SKILL.md"
cp "$T/.claude/skills/demo/SKILL.md" "$TAR/Claude-fixture/.claude/skills/demo/SKILL.md"
OUT=$(FAKE_LSREMOTE=$FULL_A sync_remote)
[ -f "$P/.claude/skills/demo/SKILL.md" ] && ok "R4 a tarball (no .git) still ships its skills by find" \
  || bad "R4 the tarball's skill did not ship ($(printf '%s' "$OUT" | tail -2 | tr '\n' '|'))"

echo "== 091 units — the new functions, extracted"
UH="$TMP/units.sh"
{ echo 'warn() { printf "%s\n" "$*"; }'
  echo 'TEMPLATE_COMPARE_BASE="https://api.github.com/repos/johanolofsson72/Claude/compare"'
  for fn in pin_on_main flagged_paths report_flagged stage_clone_divergence stage_committed_bytes report_eol_divergence; do
    sed -n "/^$fn() {/,/^}\$/p" "$SCRIPT"
  done; } > "$UH"
NOBIN="$TMP/nobin"; mkdir -p "$NOBIN"; for b in mktemp rm cat tr grep sed awk xargs; do ln -sf "$(command -v $b)" "$NOBIN/$b"; done
OUT=$( . "$UH"; PATH="$NOBIN"; pin_on_main "$FULL_A"; echo "rc=$? why=$PIN_WHY" )
has   "U pin_on_main without curl: no proof"             "$OUT" "rc=1 why=no curl"
ln -sf "$SHIMS/curl" "$NOBIN/curl"
OUT=$( . "$UH"; PATH="$NOBIN"; pin_on_main "$FULL_A"; echo "rc=$? why=$PIN_WHY" )
has   "U pin_on_main without python3: no proof"          "$OUT" "rc=1 why=no python3"
FAILMK="$TMP/failmk"; mkdir -p "$FAILMK"; printf '#!/bin/sh\nexit 1\n' > "$FAILMK/mktemp"; chmod +x "$FAILMK/mktemp"
OUT=$( . "$UH"; PATH="$FAILMK:$SHIMS:$PATH"; SHIM_LOG="$TMP/u.log"; pin_on_main "$FULL_A"; echo "rc=$? why=$PIN_WHY" )
has   "U pin_on_main with no temp file: no proof"        "$OUT" "rc=1 why=no temp file"
OUT=$( . "$UH"; PATH="$SHIMS:$PATH"; SHIM_LOG="$TMP/u.log"; FAKE_COMPARE_STATUS=none pin_on_main "$FULL_A"; echo "rc=$? why=$PIN_WHY" )
has   "U pin_on_main when curl fails: the reason says no answer" "$OUT" "rc=1 why=GitHub answered HTTP none"
OUT=$( . "$UH"; PATH="$SHIMS:$PATH"; SHIM_LOG="$TMP/u.log"; pin_on_main "$FULL_A"; echo "rc=$? why=$PIN_WHY" )
has   "U pin_on_main on ahead: proven"                   "$OUT" "rc=0 why=ok"
OUT=$( . "$UH"; EOL_STAGE=""; stage_committed_bytes "$TMP" ""; echo "rc=$? stage=[$EOL_STAGE]" )
same  "U stage_committed_bytes with nothing to stage: rc 0, no stage" "$OUT" "rc=0 stage=[]"
OUT=$( . "$UH"; EOL_STAGE=""; PATH="$FAILMK:$PATH"; stage_committed_bytes "$TMP" "x"; echo "rc=$? stage=[$EOL_STAGE]" )
same  "U stage_committed_bytes with no temp dir: rc 0, no stage" "$OUT" "rc=0 stage=[]"
OUT=$( . "$UH"; report_flagged /c ""; echo "rc=$?" )
same  "U report_flagged with nothing flagged: silent, rc 0" "$OUT" "rc=0"
OUT=$( . "$UH"; report_flagged /c "$(printf 'a.md\n\nb.md')" )
has   "U report_flagged counts and names each path"      "$OUT" "marks 2 path(s)"
same  "U report_flagged prints no blank path line"       "$(printf '%s\n' "$OUT" | grep -c '^      $')" 0
build u1
OUT=$( . "$UH"; EOL_DIVERGED=".claude/rules/allium.md"; EOL_STAGE=""; stage_clone_divergence "$T"; echo "rc=$?" )
has   "U stage_clone_divergence reports EOL_DIVERGED"    "$OUT" "[eol] 1 file(s)"
has   "U ... and stages it (rc 0)"                       "$OUT" "rc=0"
OUT=$( . "$UH"; EOL_DIVERGED=""; EOL_STAGE=""; stage_clone_divergence "$T"; echo "rc=$? stage=[$EOL_STAGE]" )
has   "U nothing diverged, nothing flagged: rc 0, no stage" "$OUT" "rc=0 stage=[]"
hasnt "U ... and no report"                              "$OUT" "[eol]"
"$REAL_GIT" -C "$T" update-index --skip-worktree .claude/rules/allium.md
OUT=$( . "$UH"; EOL_DIVERGED=""; EOL_STAGE=""; stage_committed_bytes() { EOL_STAGE="$TMP/empty-stage"; mkdir -p "$EOL_STAGE"; }; stage_clone_divergence "$T"; echo "rc=$?" )
has   "U a flagged path missing from the stage: rc 1"    "$OUT" "rc=1"
"$REAL_GIT" -C "$T" update-index --no-skip-worktree .claude/rules/allium.md

echo "== R2 — a candidate needs sync-prompt.md AND .claude/rules"
build r2cand
rm -f "$T/scripts/sync-prompt.md"; "$REAL_GIT" -C "$T" commit -qam "no prompt"
OUT=$(FAKE_LSREMOTE=$FULL_A sync_local)
has   "R2 a clone without sync-prompt.md is not a template: the remote is used" "$(cat "$LOG")" "tar.gz/$FULL_A"

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
