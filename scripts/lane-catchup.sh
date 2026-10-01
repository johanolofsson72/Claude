#!/bin/bash
# lane-catchup.sh — bring a second lane's machine level with the register.
#
# WHY THIS EXISTS. A two-lane project shares a git repo and nothing else. When
# one lane changes the config, the rules, or the shared machinery, the other
# lane finds out by pulling -- and on a lane that sets CLAUDE_TEMPLATE_AUTOSYNC=0
# (which .claude/rules/spec-register.md tells the second machine to do, so the
# two do not race each other's config commits) nothing arrives on its own.
#
# The alternative was a written list of steps sent to a person. That fails three
# ways and did, on the first draft: the step that stops permission prompts sat
# fourth, so the developer clicked through prompts to reach it; the paths were
# guesses about someone else's disk; and it ended with "report back", which makes
# a person the transport between two machines that already share a disk -- the
# exact anti-pattern .claude/rules/lane-handoff.md exists to remove.
#
# So: one command, ordered so each step clears the way for the next, and its
# findings are WRITTEN to specs/INDEX.pending.md rather than relayed by hand.
#
# Reports by default and changes nothing. --apply makes the one machine-local
# change (permission denies, credential-store denies always kept — spec 082); everything else is read-only.
#
# Usage:
#   bash scripts/lane-catchup.sh              # report only
#   bash scripts/lane-catchup.sh --apply      # also make the machine-local fixes
#   bash scripts/lane-catchup.sh --apply --at 03:00
#
# Exit: 0 nothing needs a human · 1 something does · 2 could not run

set -uo pipefail
export LC_ALL=C

APPLY=0; AT="02:30"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --at) AT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "lane-catchup.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "lane-catchup: run this from inside the project repo." >&2; exit 2; }
cd "$ROOT" || exit 2

NEEDS_HUMAN=0
say()  { printf '%s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*" 2>/dev/null || printf '\n%s\n' "$*"; }
todo() { NEEDS_HUMAN=1; printf '  → %s\n' "$*"; }

# ── 1. Permissions FIRST. Every step below runs shell commands, and if this is
#      unfixed the developer approves each one by hand on the way to the fix.
head_ "1. Permission prompts"
GS="$HOME/.claude/settings.json"
if [ ! -f "$GS" ]; then
  say "  no global settings at $GS — nothing to change"
else
  # Spec 082 (F063). This used to drop EVERY Read(~/…)/Edit(~/…) deny, and the ~/.ssh and ~/.aws
  # denies went with them: the step meant to stop permission prompts also opened the credential
  # stores to the agent. Credential-store denies are now kept whatever else goes. The write is
  # backup-first and atomic, because a crash halfway through rewriting ~/.claude/settings.json
  # used to leave a half-written file and no copy of the original.
  #
  # The helper prints `drop<TAB>rule` and `keep<TAB>rule` lines, or `malformed<TAB>why`. With
  # `apply` and something to drop it also makes the change and prints `backup<TAB>path`.
  PLAN=$(python3 - "$GS" "$([ "$APPLY" -eq 1 ] && echo apply)" <<'PY'
import fnmatch, json, os, re, shutil, sys, tempfile, time
# realpath: a dotfile manager keeps ~/.claude/settings.json as a symlink, and os.replace on the link
# would swap it for a regular file. Rewrite (and back up) the real file instead.
p, mode = os.path.realpath(sys.argv[1]), sys.argv[2]
CRED = (".ssh", ".aws", ".gnupg", ".kube", ".docker", ".azure", ".config/gh", ".config/gcloud",
        ".netrc", ".npmrc", ".pypirc", ".git-credentials", ".password-store", ".pgpass",
        ".vault-token", ".cargo/credentials", ".cargo/credentials.toml", ".config/op",
        ".claude/.credentials.json", "Library/Keychains")
# Adversarial review F5: a name list alone drops a broad rule. Read(~/**) or Read(~/.s*) names no
# store, yet guards all of them. So a rule is also kept when its glob could match one of these
# probes. fnmatch's * crosses "/", which only ever keeps more: the safe direction for a deny.
PROBES = ("~/.ssh/id_ed25519", "~/.aws/credentials", "~/.gnupg/x", "~/.kube/config",
          "~/.docker/config.json", "~/.azure/x", "~/.config/gh/hosts.yml", "~/.config/gcloud/x",
          "~/.netrc", "~/.npmrc", "~/.pypirc", "~/.git-credentials", "~/.password-store/x",
          "~/.pgpass", "~/.vault-token", "~/.cargo/credentials.toml", "~/.config/op/x",
          "~/.claude/.credentials.json", "~/Library/Keychains/x")

def is_cred(rule):
    m = re.match(r"^[A-Za-z]+\((.*)\)$", rule)
    path = (m.group(1) if m else rule).replace("\\", "/")
    # Whole path segments, so ~/.sshfoo or ~/notes/.aws-ideas.md is not mistaken for a store.
    segs = [x for x in path.split("/") if x]
    for store in CRED:
        parts = store.split("/")
        if any(segs[i:i + len(parts)] == parts for i in range(len(segs) - len(parts) + 1)):
            return True
    glob = path.replace("**", "*")
    return any(fnmatch.fnmatchcase(probe, glob) for probe in PROBES)

try:
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    deny = d.get("permissions", {}).get("deny", [])
    if not isinstance(deny, list):
        raise ValueError("permissions.deny is not a list")
except Exception as e:
    print("malformed\t%s" % str(e).replace("\n", " "))
    sys.exit(0)
home = [r for r in deny if isinstance(r, str) and r.startswith(("Read(~/", "Edit(~/"))]
drop = [r for r in home if not is_cred(r)]
for r in home:
    print("%s\t%s" % ("keep" if is_cred(r) else "drop", r))
if mode != "apply" or not drop:
    sys.exit(0)
st = os.stat(p)
backup = "%s.bak-%s" % (p, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
shutil.copy2(p, backup)
d["permissions"]["deny"] = [r for r in deny if r not in drop]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(p)), prefix=".settings.", suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    os.chmod(tmp, st.st_mode & 0o7777)
    os.replace(tmp, p)
except BaseException:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
print("backup\t%s" % backup)
PY
)
  TAB=$(printf '\t')
  DROP=$(printf '%s\n' "$PLAN" | sed -n "s/^drop$TAB//p")
  KEEP=$(printf '%s\n' "$PLAN" | sed -n "s/^keep$TAB//p")
  BAD=$(printf '%s\n' "$PLAN" | sed -n "s/^malformed$TAB//p")
  BACKUP=$(printf '%s\n' "$PLAN" | sed -n "s/^backup$TAB//p")
  if [ -n "$BAD" ]; then
    say "  $GS could not be read ($BAD) — nothing changed"
    todo "fix $GS by hand, then re-run"
  elif [ -z "$DROP" ]; then
    say "  no removable Read(~/…) deny rules — prompts are not coming from here"
  elif [ "$APPLY" -eq 1 ] && [ -n "$BACKUP" ]; then
    say "  removed $(printf '%s\n' "$DROP" | grep -c .) Read/Edit home-dir deny rule(s):"
    printf '%s\n' "$DROP" | sed 's/^/    /'
    say "  backup of the original: $BACKUP"
    say "  every Bash deny is kept — rm -rf, sudo, force-push, hard reset"
  elif [ "$APPLY" -eq 1 ]; then
    say "  could not rewrite $GS — nothing changed"
    todo "check that $GS and its directory are writable, then re-run"
  else
    say "  these deny rules are why ordinary commands prompt:"
    printf '%s\n' "$DROP" | sed 's/^/    /'
    todo "run with --apply to remove them (Bash denies and credential-store denies are kept)"
  fi
  if [ -n "$KEEP" ] && [ -z "$BAD" ]; then
    say "  kept, because they guard a credential store (spec 082):"
    printf '%s\n' "$KEEP" | sed 's/^/    /'
  fi
fi

# ── 2. Is the working tree even able to take an update?
head_ "2. Repository state"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
say "  branch $BRANCH · $DIRTY uncommitted file(s)"
git fetch -q origin 2>/dev/null || true
BEHIND=$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)
if [ "${BEHIND:-0}" -gt 0 ]; then
  say "  $BEHIND commit(s) behind origin/$BRANCH"
  todo "git pull  — this is where the rules, scripts and settings arrive"
else
  say "  up to date with origin/$BRANCH"
fi
[ "${AHEAD:-0}" -gt 0 ] && todo "$AHEAD commit(s) not pushed — the other lane cannot see them"

# ── 3. Did the shared machinery actually land?
head_ "3. Shared machinery"
# ASKED, not listed. This used to name four files, and the list was written before
# maintenance-due.sh, carve_audit.py and validate-portability.sh existed -- so on the day
# those landed, the one command whose job is "tell me what my machine is missing" would
# have said everything was present. That is the third time today the same shape has bitten:
# an enumeration is a list of what somebody thought of, and it goes stale silently because
# there is no error state for "you forgot to add it here too". The Bash allow list and
# sync-prompt.md's 27-script list were the other two.
#
# template-autosync.sh --list-core-scripts is the manifest, and it answers locally without
# a clone or a network round.
MISS=""
CORE_LIST=""
[ -f scripts/template-autosync.sh ] && \
  CORE_LIST=$(bash scripts/template-autosync.sh --list-core-scripts 2>/dev/null)
if [ -n "$CORE_LIST" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "scripts/$f" ] || MISS="$MISS scripts/$f"
  done <<< "$CORE_LIST"
  N_CORE=$(printf '%s\n' "$CORE_LIST" | grep -c .)
else
  # No manifest to ask: fall back to the rules, which are not in it.
  N_CORE=0
fi
for f in .claude/rules/carve-budget.md .claude/rules/spec-register.md .claude/rules/lane-handoff.md; do
  [ -f "$f" ] || MISS="$MISS $f"
done
if [ -n "$MISS" ]; then
  say "  missing:$MISS"
  todo "git pull first, then re-run this"
else
  say "  $N_CORE CORE script(s) + the lane rules — all present"
  # -f, not -x. Eight CORE scripts in the template were shipped without their
  # executable bit and the sync copies modes faithfully, so an -x guard here
  # skipped this entire check in silence on all six projects. The SessionStart
  # hook already learned this and tests `-x || -f`; this is the same lesson.
  if [ -f scripts/template-autosync.sh ]; then
    # CLAUDE_PROJECT_DIR is passed, not left to the `cd "$ROOT"` above: template-autosync.sh resolves
    # ${CLAUDE_PROJECT_DIR:-$PWD}, so an ambient value from another session would beat the cd and
    # this preview would describe that repository instead of this one. Spec 010.
    OUT=$(CLAUDE_PROJECT_DIR="$ROOT" timeout 240 bash scripts/template-autosync.sh --force --dry-run 2>&1)
    printf '%s\n' "$OUT" | grep -E '^\[check\] would' | sed 's/^/  /'
    SKIPS=$(printf '%s\n' "$OUT" | grep '^  SKIP' | sed 's/^  SKIP   //; s/ (differs.*//')
    if [ -n "$SKIPS" ]; then
      say "  locally-edited docs the sync will not touch:"
      printf '    %s\n' $SKIPS
      todo "these need /project-update (a prose merge) or --accept-local"
    fi
  fi
fi

# ── 3b. What lives on this machine and not in any repo (spec 073).
#
# Two things a pull can never deliver, because neither is in the project: the global
# /project-wizard and /project-update skills under ~/.claude/skills, and the spec-kit CLI.
# Both drifted per machine before 073 — the global skills were copied by hand once, and
# spec-kit was installed from whatever `main` was that day — so two lanes could run different
# phases of one pipeline on one register without either knowing. Both checks are read-only.
head_ "3b. Machine-level tools (global skills, spec-kit CLI)"
TPL=$( [ -f scripts/template-autosync.sh ] && bash scripts/template-autosync.sh --template-dir 2>/dev/null )
if [ -z "$TPL" ]; then
  todo "no template clone found — clone it (git clone https://github.com/johanolofsson72/Claude.git ~/repos/Claude) or set CLAUDE_TEMPLATE_DIR"
else
  if [ -f "$TPL/scripts/install-global-skills.sh" ] && ! bash "$TPL/scripts/install-global-skills.sh" --check >/dev/null 2>&1; then
    todo "global /project-wizard and /project-update skills are stale — run: git -C \"$TPL\" pull --ff-only && bash \"$TPL/scripts/install-global-skills.sh\""
  else
    say "  global skills match the template at $TPL"
  fi
fi
if [ -f scripts/speckit-sync.sh ]; then
  SK=$(bash scripts/speckit-sync.sh --check 2>&1); SKRC=$?
  if [ "$SKRC" -eq 0 ]; then
    say "  spec-kit CLI and .specify/ at the pin ($(tr -d '[:space:]' < scripts/speckit-version 2>/dev/null))"
  else
    printf '%s\n' "$SK" | grep -E 'out of date|FAIL' | sed 's/^/  /'
    todo "spec-kit is not at the template's pin — run: bash scripts/speckit-sync.sh"
  fi
fi

# ── 4. Recurring work: what this project owes, not what a timer says.
#
# This section used to install a crontab entry. That was the wrong answer and it is now the
# rule's own example of the wrong answer (.claude/rules/github-actions.md): a cron runs whether
# or not there is anything to do, runs at 02:00 on a sleeping laptop, and does not catch up a
# job it missed. Seven were installed on 2026-09-03 and not one had produced a log by morning.
#
# The project keeps its own due-state instead, and the developer plans the expensive work around
# their day. Reported in section 6 below, with the rest of what is true of THIS machine.
head_ "4. Recurring work"
if [ -f scripts/maintenance-due.sh ]; then
  say "  tracked by scripts/maintenance-due.sh — reported at every session start and after"
  say "  every ticked row, so an expensive pass is planned rather than scheduled. See section 6."
else
  say "  scripts/maintenance-due.sh is not here yet (pull first)"
fi

# ── 5. Where the register stands, and what this lane owns.
#
# DELEGATED, not reimplemented. .claude/rules/lane-handoff.md is explicit: "There is
# exactly one engine, scripts/lane_status.py. The hook renders the brief at session
# start, the script the full report on demand. Two readers of one register that
# could answer differently about who owns what is precisely what
# .claude/rules/spec-register.md warns about."
#
# The first draft of this file grepped for "@$OWNER" itself, which made three
# implementations of one question -- and they did not agree: spec_active.py requires
# an em-dash before the tag (OWNER_RE), that grep did not. It also answered far less:
# your rows and nothing about what the other lane holds, what is unclaimed and
# actually runnable, or what is held and why.
head_ "5. This lane"
if [ -z "${SPEC_OWNER:-}" ]; then
  say "  SPEC_OWNER is unset — set it in .claude/settings.local.json so the"
  say "  guards resolve YOUR row and not the other lane's:"
  say '    { "env": { "SPEC_OWNER": "yourname", "CLAUDE_TEMPLATE_AUTOSYNC": "0" } }'
  todo "set SPEC_OWNER"
elif [ -f scripts/lane-status.sh ]; then
  bash scripts/lane-status.sh 2>/dev/null | sed 's/^/  /'
else
  say "  scripts/lane-status.sh is not here yet (pull first)"
fi

# Convergence is a different question from ownership -- how fast the register closes,
# not who owns what -- so it keeps its own engine and its own line.
if [ -f scripts/register-convergence.sh ]; then
  CONV_RAW=$(bash scripts/register-convergence.sh 2>&1); RC=$?
  say "  $(printf '%s\n' "$CONV_RAW" | head -1)"
  # A register the developer already froze (row 077) is not asked the three-ways-out question again.
  FRZ_RAW=$(bash scripts/register-convergence.sh --freeze 2>/dev/null); FRZ_RC=$?
  case "$FRZ_RC" in
    0|2|3) say "  $(printf '%s\n' "$FRZ_RAW" | head -1)"
           [ "$FRZ_RC" = 2 ] && todo "rows added during the freeze without an approved proposal — surface them (approve or cut)" ;;
    4) todo "freeze line malformed: $(printf '%s\n' "$FRZ_RAW" | head -1)"
       [ "$RC" = 2 ] && todo "convergence stop — see .claude/rules/carve-budget.md before carving any row" ;;
    *) [ "$RC" = 2 ] && todo "convergence stop — see .claude/rules/carve-budget.md before carving any row" ;;
  esac
  # The two limits the ratio does not measure. Reported here because a lane arriving at a
  # register that already breaches them should know before it carves anything of its own.
  if [ -f scripts/carve_audit.py ]; then
    CARVE_RAW=$(bash scripts/register-convergence.sh --carves 2>&1)
    printf '%s\n' "$CARVE_RAW" | grep -E '^\[CARVE|^carve shape' | sed 's/^/  /' | sed -n 1,4p
  fi
fi

# ── 6. Does the shared machinery run on THIS machine?
#
# The point of this section is the asymmetry: Johan is on macOS and David on Linux, and a
# construct that works on one is a script the other never successfully runs -- usually with
# an empty result rather than an error. agentcrm's test-order-varied.sh enumerated 0 of 135
# test classes on macOS for months because of `find -printf`.
head_ "6. This machine"
if [ -f scripts/validate-portability.sh ]; then
  PORT_RAW=$(bash scripts/validate-portability.sh --all 2>&1); PRC=$?
  say "  $(printf '%s\n' "$PORT_RAW" | grep -E '^portability:' | head -1)"
  [ "$PRC" = 1 ] && todo "portability findings — bash scripts/validate-portability.sh --all"
else
  say "  scripts/validate-portability.sh is not here yet (pull first)"
fi
if [ -f scripts/maintenance-due.sh ]; then
  DUE_RAW=$(bash scripts/maintenance-due.sh --brief 2>&1)
  if [ -n "$DUE_RAW" ]; then
    printf '%s\n' "$DUE_RAW" | sed 's/^/  /'
    todo "maintenance is due on this machine — bash scripts/project-maintenance.sh --full --suite"
  else
    say "  maintenance: nothing due on this machine"
  fi
fi

head_ "Summary"
if [ "$NEEDS_HUMAN" -eq 0 ]; then
  say "  Nothing needs a human. This lane is level."
else
  say "  The arrows above are what is left. Findings that concern the OTHER lane"
  say "  belong in specs/INDEX.pending.md or a new register row, committed and"
  say "  pushed — not in a chat message (.claude/rules/lane-handoff.md)."
fi
exit "$NEEDS_HUMAN"
