#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-template-autosync-sandbox-writes.sh — a run that declared a sandbox writes nowhere else
# (spec 084, R2 R3, F013).
#
# Spec 010's interlock checked WHERE the project root is. Two writes still left a declared run: a
# push to whatever `origin` the fixture's branch tracked, and a fetch + fast-forward of the first
# template clone on the candidate list (~/repos/Claude).
#
#   S1  end to end through drive_sync: an origin outside the sandbox is not pushed and its refs do
#       not move; an origin inside is pushed. 084-AC-2.
#   S2  the push judgement over URL shapes: path, relative, file:///, file://host, https, scp-like,
#       %-encoded, ext::, missing, symlink out, pushurl, pushInsteadOf, several push URLs.
#   S3  a behind template clone outside the sandbox is used as-is, says so, and its HEAD and refs do
#       not move; inside the sandbox it fast-forwards; undeclared it fast-forwards; a worktree inside
#       whose git dir is outside counts as outside. 084-AC-3.
#   S4  sabotage: a sync with R2 removed pushes out, and a refresh with R3 removed moves the outside
#       clone — so S1 and S3 can fail.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

ROOT=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
SCRIPT="$ROOT/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "missing: $SCRIPT"; exit 1; }
. "$ROOT/scripts/drive-sync.sh"   # the only way to the sync (spec 011)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-300))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t sbxwrites)
WORK=$(cd -P -- "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

refs() { git -C "$1" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null; }

# ------------------------------------------------------------------------------- S1 end to end
# A template the sync can copy from (its origin is not the template's URL, so it is never fetched),
# and a project whose main tracks a bare origin. $1 = sandbox, $2 = where the bare origin lives.
build() {
  SB="$1"; BARE="$2"; T="$SB/template"; P="$SB/project"
  mkdir -p "$T/scripts" "$T/.claude/rules"
  cp "$SCRIPT" "$T/scripts/template-autosync.sh"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'placeholder rule\n' > "$T/.claude/rules/allium.md"
  git -C "$T" init -q -b main && git -C "$T" add -A && git -C "$T" commit -qm "template v1"
  git init -q --bare -b main "$BARE"
  mkdir -p "$P/.claude" "$P/scripts"
  echo '{"name":"fake"}' > "$P/package.json"
  cp "$SCRIPT" "$P/scripts/template-autosync.sh"
  git -C "$P" init -q -b main && git -C "$P" add -A && git -C "$P" commit -qm "project init"
  git -C "$P" remote add origin "$BARE" && git -C "$P" push -q -u origin main 2>/dev/null
}
sync_in() {  # sync_in <sandbox> [script]
  CLAUDE_TEMPLATE_DIR="$1/template" DRIVE_SYNC_SCRIPT="${2:-$SCRIPT}" drive_sync "$1/project" "$1" 2>&1
}

printf '\n[S1] end to end: the commit stays home unless origin is inside (084-AC-2)\n'
mkdir -p "$WORK/s1out/sbx" "$WORK/s1out/elsewhere"
build "$WORK/s1out/sbx" "$WORK/s1out/elsewhere/origin.git"
BEFORE=$(refs "$WORK/s1out/elsewhere/origin.git")
OUT=$(sync_in "$WORK/s1out/sbx")
has   "outside origin: the sync committed"                 "$OUT" "committed"
has   "outside origin: it says why it did not push"        "$OUT" "not pushed — origin is outside the declared sandbox"
hasnt "outside origin: no URL in the note"                 "$OUT" "elsewhere/origin.git"
same  "outside origin: the bare repo's refs did not move"  "$(refs "$WORK/s1out/elsewhere/origin.git")" "$BEFORE"
HEADP=$(git -C "$WORK/s1out/sbx/project" rev-parse HEAD)
[ "$HEADP" != "$(git -C "$WORK/s1out/elsewhere/origin.git" rev-parse main)" ] && ok "outside origin: the local commit exists and was not sent" || bad "outside origin: project HEAD equals the outside origin"

mkdir -p "$WORK/s1in/sbx"
build "$WORK/s1in/sbx" "$WORK/s1in/sbx/origin.git"
OUT=$(sync_in "$WORK/s1in/sbx")
has  "inside origin: pushed as before"                     "$OUT" "pushed to main"
same "inside origin: the bare repo holds the sync commit"  "$(git -C "$WORK/s1in/sbx/origin.git" rev-parse main)" "$(git -C "$WORK/s1in/sbx/project" rev-parse HEAD)"

# ------------------------------------------------------------------------------- S2 URL shapes
# The judgement in isolation: the sync does real work at load time, so its helpers are extracted.
HARNESS="$WORK/harness.sh"
{
  echo 'warn() { printf "%s\n" "$*" >&2; }'
  cat "$(dirname "$SCRIPT")/template-identity.sh"     # template_url_matches (spec 091 R1)
  for fn in _phys _within _inside_sandbox _push_inside_sandbox _clone_inside_sandbox refresh_local_template; do
    sed -n "/^$fn() {/,/^}\$/p" "$SCRIPT"
  done
} > "$HARNESS"
for fn in _phys _within _inside_sandbox _push_inside_sandbox _clone_inside_sandbox refresh_local_template; do
  grep -q "^$fn() {" "$HARNESS" || bad "could not extract $fn from the sync"
done
push_ok() {  # push_ok <project> <sandbox> → 0 inside, 1 outside
  ( . "$HARNESS"; PROJECT_ROOT="$1"; _sbx=$(_phys "$2"); _push_inside_sandbox )
}

printf '\n[S2] the push judgement over URL shapes\n'
SB="$WORK/s2/sbx"; OUTSIDE="$WORK/s2/outside"
mkdir -p "$SB/p" "$OUTSIDE"
git init -q --bare "$SB/in.git"; git init -q --bare "$OUTSIDE/out.git"
git -C "$SB/p" init -q
ln -s "$OUTSIDE/out.git" "$SB/link.git"
url() { git -C "$SB/p" remote remove origin 2>/dev/null; git -C "$SB/p" remote add origin "$1"; }
judge() {  # judge <label> <want 0|1>
  push_ok "$SB/p" "$SB"; _rc=$?
  same "$1" "$_rc" "$2"
}
url "$SB/in.git";                         judge "absolute path inside → push"               0
url "$OUTSIDE/out.git";                   judge "absolute path outside → hold"              1
url "../in.git";                          judge "relative path, resolved from the project"  0
url "file://$SB/in.git";                  judge "file:/// inside → push"                    0
url "file://localhost$SB/in.git";         judge "file://host/… → hold"                      1
url "https://example.invalid/x/y.git";    judge "https → hold"                              1
url "git@example.invalid:x/y.git";        judge "scp-like host:path → hold"                 1
url "$SB/%2e%2e/outside/out.git";         judge "a %-encoded path → hold"                   1
url "ext::sh -c true";                    judge "ext:: transport → hold"                    1
url "$SB/missing.git";                    judge "a path that does not exist → hold"         1
url "$SB/link.git";                       judge "a symlink inside pointing out → hold"      1
url "$SB/in.git"; git -C "$SB/p" config remote.origin.pushurl "$OUTSIDE/out.git"
                                          judge "url inside, pushurl outside → hold"        1
git -C "$SB/p" config --unset remote.origin.pushurl
git -C "$SB/p" config "url.$OUTSIDE/out.git.pushInsteadOf" "$SB/in.git"
                                          judge "pushInsteadOf rewrites it outside → hold"  1
git -C "$SB/p" config --unset "url.$OUTSIDE/out.git.pushInsteadOf"
git -C "$SB/p" config --add remote.origin.pushurl "$SB/in.git"
git -C "$SB/p" config --add remote.origin.pushurl "$OUTSIDE/out.git"
                                          judge "two push URLs, one outside → hold"         1
# Where git lands, not what the URL says (adversarial review 084, both verified by PoC first).
mkdir -p "$SB/gf" && printf 'gitdir: %s\n' "$OUTSIDE/out.git" > "$SB/gf/.git"
url "$SB/gf";                             judge "a dir whose .git FILE points out → hold"   1
mkdir -p "$SB/probe" && ln -s "$OUTSIDE/out.git" "$SB/probe.git"
url "$SB/probe";                          judge "empty dir beside an outside probe.git → hold" 1
git -C "$OUTSIDE/out.git" worktree add -q "$SB/wtp" 2>/dev/null || { git init -q "$OUTSIDE/nb" && git -C "$OUTSIDE/nb" commit -q --allow-empty -m x && git -C "$OUTSIDE/nb" worktree add -q "$SB/wtp" -b w 2>/dev/null; }
url "$SB/wtp";                            judge "a worktree inside of a repo outside → hold" 1
git -C "$SB/p" remote remove origin;      judge "no origin at all → hold"                   1

# ------------------------------------------------------------------------------- S3 clone refresh
printf '\n[S3] a template clone outside the sandbox is read, never moved (084-AC-3)\n'
ORIGIN="$WORK/s3/johanolofsson72/Claude.git"          # matches the refresh's template-URL check
mkdir -p "$(dirname "$ORIGIN")"; git init -q --bare -b main "$ORIGIN"
SEED="$WORK/s3/seed"; git init -q -b main "$SEED"
mkdir -p "$SEED/scripts"; echo v1 > "$SEED/scripts/sync-prompt.md"
git -C "$SEED" add -A && git -C "$SEED" commit -qm v1
git -C "$SEED" remote add origin "$ORIGIN" && git -C "$SEED" push -q origin main
V1=$(git -C "$SEED" rev-parse HEAD)
echo v2 > "$SEED/scripts/sync-prompt.md"; git -C "$SEED" commit -qam v2 && git -C "$SEED" push -q origin main
V2=$(git -C "$SEED" rev-parse HEAD)
clone_v1() {
  git clone -q "$ORIGIN" "$1" 2>/dev/null
  # Spec 091 R1: the clone's origin is the template's real URL (the anchored match), and git fetches it
  # from the local bare repository through insteadOf.
  git -C "$1" remote set-url origin https://github.com/johanolofsson72/Claude.git
  git -C "$1" config "url.$ORIGIN.insteadOf" https://github.com/johanolofsson72/Claude.git
  git -C "$1" checkout -q -B main "$V1"; git -C "$1" update-ref refs/remotes/origin/main "$V1"
}
refresh() {  # refresh <clone> <sandbox-or-empty> [harness]
  ( . "${3:-$HARNESS}"
    if [ -n "$2" ]; then CLAUDE_TEMPLATE_SYNC_SANDBOX="$2"; _sbx=$(_phys "$2"); fi
    refresh_local_template "$1" ) 2>&1
}
SB3="$WORK/s3/sbx"; mkdir -p "$SB3"

C="$WORK/s3/home-clone"; clone_v1 "$C"; R0=$(refs "$C")
OUT=$(refresh "$C" "$SB3")
same "outside, declared: HEAD did not move"            "$(git -C "$C" rev-parse HEAD)" "$V1"
same "outside, declared: no ref moved (no fetch)"      "$(refs "$C")" "$R0"
has  "outside, declared: one note says so"             "$OUT" "outside the declared sandbox — used as-is"

C="$SB3/clone"; clone_v1 "$C"
OUT=$(refresh "$C" "$SB3")
same "inside, declared: fast-forwarded as before"      "$(git -C "$C" rev-parse HEAD)" "$V2"

C="$WORK/s3/undeclared"; clone_v1 "$C"
OUT=$(refresh "$C" "")
same "undeclared: fast-forwarded as before"            "$(git -C "$C" rev-parse HEAD)" "$V2"

C="$WORK/s3/wt-main"; clone_v1 "$C"
git -C "$C" worktree add -q "$SB3/wt" -b wtb "$V1" 2>/dev/null
R0=$(refs "$C")
OUT=$(refresh "$SB3/wt" "$SB3")
same "worktree inside, git dir outside: no ref moved"  "$(refs "$C")" "$R0"
has  "…and it is treated as outside"                   "$OUT" "outside the declared sandbox"

# ------------------------------------------------------------------------------- S4 sabotage
printf '\n[S4] sabotage: without R2 and R3 the writes escape\n'
SAB="$WORK/sab-sync.sh"
sed 's/\[ "${CLAUDE_TEMPLATE_SYNC_SANDBOX+set}" = set \] \&\& ! _push_inside_sandbox/false/' "$SCRIPT" > "$SAB"
if cmp -s "$SAB" "$SCRIPT"; then bad "R2 sabotage did not apply"; else
  mkdir -p "$WORK/sab/sbx" "$WORK/sab/elsewhere"
  build "$WORK/sab/sbx" "$WORK/sab/elsewhere/origin.git"
  BEFORE=$(refs "$WORK/sab/elsewhere/origin.git")
  sync_in "$WORK/sab/sbx" "$SAB" >/dev/null
  [ "$(refs "$WORK/sab/elsewhere/origin.git")" != "$BEFORE" ] && ok "without R2 the outside origin is pushed — S1 can fail" || bad "the R2 sabotage did not push; S1 proves nothing"
fi
SABH="$WORK/sab-harness.sh"
sed 's/\[ "${CLAUDE_TEMPLATE_SYNC_SANDBOX+set}" = set \] \&\& ! _clone_inside_sandbox "$_c"/false/' "$HARNESS" > "$SABH"
if cmp -s "$SABH" "$HARNESS"; then bad "R3 sabotage did not apply"; else
  C="$WORK/s3/sab-clone"; clone_v1 "$C"
  refresh "$C" "$SB3" "$SABH" >/dev/null
  [ "$(git -C "$C" rev-parse HEAD)" = "$V2" ] && ok "without R3 the outside clone is fast-forwarded — S3 can fail" || bad "the R3 sabotage did not move the clone; S3 proves nothing"
fi

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
