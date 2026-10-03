#!/bin/bash
# PreToolUse guard: the files that wire every hook stay out of the agent's tools for the keys that
# decide which hooks run (spec 089).
#
# WHY THIS EXISTS
# ---------------
# Every gate in this template is a PreToolUse hook wired in a settings file, and a settings file is
# JSON the gated agent could write. One Edit of .claude/settings.json removed every hook (F081, 083
# adversarial #15). An `env` entry in the gitignored settings.local.json set SPEC_ACCEPTANCE=off or
# ALLOW_CORE_MACHINERY_EDIT=1 for the next session and left no diff behind (F103, 088 adversarial
# #11). `"disableAllHooks": true` in any of them switched everything off at once.
#
# WHAT IT GUARDS (developer O1, O2)
# ---------------------------------
# Three files: <project>/.claude/settings.json, <project>/.claude/settings.local.json and
# <config>/settings.json (CLAUDE_CONFIG_DIR, default ~/.claude). Every key except a safe list
# ($schema, language, model, and permissions.allow/ask/additionalDirectories): spec 095 R2 inverted
# 089's three keys (F115). Another
# project's settings are not this guard's. The verdict is scripts/settings_guard.py:
#
#   Edit/Write/MultiEdit  the call is applied to the current bytes as the tool would apply it, and a
#                         change to any of the three keys is denied, as is a result that is not a
#                         JSON object (Claude Code drops a file it cannot parse, hooks and all)
#   NotebookEdit, a glob, a path with no bytes (bash-write-guard's delegated shell write)
#                         denied: nothing to compare
#   Bash                  a simple command that names a guarded file passes only when it reads
#                         (cat, jq, grep, sed -n, git diff/add/commit, …) on a line that changes no
#                         variable, function or alias first (095 R7); a redirection into one never does
#   Bash, git             a verb that writes the tree (checkout, restore, stash pop, apply, merge, …)
#                         is judged by what git says it would write (095 R1, F114). A bound (/tla
#                         GAP-1): a hand edit landing between the check and git's run is overwritten
#                         by restore, checkout -- path and reset --hard, which do not refuse
#   mcp__* tools          every string in the input, as a path and as a command (095 R3, F116); the
#                         matcher in settings.json must list mcp__.* for this to run (R4)
#
# MODS (spec 095a). A plugin folder whose hooks/hooks.json names a module is a mod; a loaded one can
# answer allow to any tool call before a settings hook runs, and its module runs code of its own. So
# no agent tool writes a mod path (settings_guard.ModZones): a .claude-plugin component, a
# hooks/hooks.json, anything in a folder holding either (anywhere, developer decision M1), anything
# under a load root (<config>/plugins, <config>/dev-mods, <any>/.claude/plugins|dev-mods, each folder on
# CLAUDE_CODE_PLUGIN_DIRS from the environment or any of the three settings files), the user's skills
# root and its children, and a skill's hooks/ folder. A project's .claude/skills and its skill folders
# are refused only to verbs that place a folder (cp, mv, ln, rsync, tar, git clone, find -exec …).
# Git verbs compare every mod path in the index, the named revisions and the untracked files (M3).
# The claude CLI's plugin subcommands other than list/validate, --plugin-dir, --plugin-url, --settings,
# --setting-sources, and CLAUDE_CODE_PLUGIN_DIRS / CLAUDE_CONFIG_DIR / HOME set for claude, are writes.
# The pre-check wakes on plugin, hooks, mods, skills, on any write-capable shell construct, on a
# file_path or cwd inside a plugin folder, and on every call while CLAUDE_CODE_PLUGIN_DIRS is set.
# Bounds (spec 095a threat model): a plugin-shaped folder staged outside every root and loaded later by
# the developer, a folder the developer makes a plugin between an allowed check and the write landing
# (/tla GAP-1, ModGuard.tla), a hard link made earlier, git filters and hooks, parallel calls racing a symlink, the
# claude binary under another name, and a CLAUDE_CODE_PLUGIN_DIRS export in a shell startup file (F080).
#
# THE ROUTES THAT STAY OPEN (developer O3, O4). No override variable, no template exemption. The
# developer edits the file by hand, or runs a command with the `!` prefix: that runs outside the
# agent's tools, so no PreToolUse hook sees it. The SessionStart autosync wires project hooks as a hook
# of its own, not as an agent tool, and is not affected.
#
# THE BOUND. Command text only, like bash-write-guard and trust-anchor-guard. A script the agent writes
# and runs, a tool that writes a settings file it was not handed on the command line
# (sync-core-hooks.py), and a directory assembled at runtime from parts that spell neither the file nor
# its directory are not seen here.
#
# AN ASSUMPTION (/tla GAP-1). A Write is judged against the bytes on disk at check time. If the developer
# hand-edits the file before the Write lands, a Write allowed against the old bytes would put the old
# keys back. Claude Code refuses a Write/Edit to a file that changed since it was read, and that check
# is what closes the race: specs/089-settings-edit-guard/SettingsGuard.tla holds with it, and fails in
# 4 steps without it.
#
# FAILS CLOSED on a call the pre-check sends to the verdict when the verdict cannot run, except an
# Edit/Write of this guard's own files: a guard that cannot run must not block its own repair (the
# 2026-10-01 trust-anchor lockout). Never echoes the command. Exit: always 0.

set -u

INPUT=$(cat 2>/dev/null || true)   # mutant-equivalent: cat on a pipe does not fail; the || only guards a closed stdin
[ -z "$INPUT" ] && exit 0

# Spec 095a R6: is <path>, or a folder above it, a plugin folder (a .claude-plugin entry or a
# hooks/hooks.json)? Past 64 levels it answers yes: the verdict decides, and it fails closed too.
in_plugin_folder() {
  local d=$1 n=0
  while [ "$n" -lt 64 ]; do
    if [ -e "$d/.claude-plugin" ] || [ -L "$d/.claude-plugin" ] || [ -e "$d/hooks/hooks.json" ]; then
      return 0
    fi
    case "$d" in /|.|"") return 1 ;; esac
    case "$d" in */*) d=${d%/*}; [ -n "$d" ] || d=/ ;; *) d=. ;; esac
    n=$((n + 1))
  done
  return 0
}

has_non_ascii() { local LC_ALL=C; [[ $1 == *[$'\x80'-$'\xff']* ]]; }

# Cheapest exit first: only the tool call is matched, from "tool_input" on, so the harness fields
# (transcript_path, cwd) never wake the verdict.
TI=${INPUT#*\"tool_input\"}
HIT=0
if [ "${#TI}" -gt 4096 ]; then
  HIT=1
else
  N=${TI//[\"\'\\]/}
  shopt -s nocasematch
  case "$N" in
    *sett*|*.cla*) HIT=1 ;;
  esac
  shopt -u nocasematch
  case "$TI" in
    *"\$'"*) HIT=1 ;;                                  # ANSI-C quoting hides the letters
    *\"command\"*) case "$TI" in *[*?[]*) HIT=1 ;; esac ;;   # a glob can spell either name
  esac
  # Spec 095 R1: a git verb that rewrites the tree names no settings file (`git checkout HEAD -- .`),
  # and git aliases can spell one, so any git command with a second word goes to the verdict.
  case "$TI" in
    # On the raw payload: a JSON \n or \t before git is a boundary (a heredoc body), and stripping the
    # backslash would glue it to the word.
    *\"command\"*) [[ $TI =~ (^|[^A-Za-z0-9_.-]|\\[nt])git[[:space:]]+[^[:space:]] ]] && HIT=1 ;;
  esac
  # Spec 095 R3: an MCP or plugin tool names its file in a field of its own choosing.
  [[ $INPUT =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"mcp__ ]] && HIT=1
  # A file_path that is a symlink, or a hard link to a guarded file, under an innocent name.
  if [ "$HIT" -eq 0 ] && [[ $TI =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    _fp="${BASH_REMATCH[1]}"
    case "$_fp" in *[*?[]*) HIT=1 ;; esac
    [ -L "$_fp" ] && HIT=1
    if [ "$HIT" -eq 0 ] && [ -f "$_fp" ]; then   # mutant-equivalent: with HIT=1 the loop can only set HIT=1 again
      _cfg="${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}"
      for _s in "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" "$_cfg/settings.json"; do
        [ -f "$_s" ] && [ "$_fp" -ef "$_s" ] && { HIT=1; break; }
      done
    fi
  fi
  # Spec 095a R6: a mod path names no settings file. The mod words wake the verdict, and so does, in a
  # command, any construct that can write (a write into a plugin folder outside every root names none).
  shopt -s nocasematch
  case "$N" in *plugin*|*hooks*|*mods*|*skills*|*-mod.sh*) HIT=1 ;; esac   # -mod.sh: spec 096 R6
  shopt -u nocasematch
  _writer='(>|(^|[^A-Za-z0-9_.-]|\\[nt])(tee|cp|mv|ln|rm|sed|install|rsync|tar|unzip|patch|touch|dd|ditto|python[0-9.]*|node|perl|ruby|sh|bash|zsh|claude)([^A-Za-z0-9_.-]|$))'
  case "$TI" in *\"command\"*) [[ $TI =~ $_writer ]] && HIT=1 ;; esac
  # A folder on CLAUDE_CODE_PLUGIN_DIRS is a load root under any name: while one is set, every call
  # goes to the verdict.
  [ -n "${CLAUDE_CODE_PLUGIN_DIRS:-}" ] && HIT=1
  if [ "$HIT" -eq 0 ]; then
    _cfg="${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}"
    for _s in "$_cfg/settings.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json"; do
      [ -f "$_s" ] && [[ $(<"$_s") == *CLAUDE_CODE_PLUGIN_DIRS* ]] && { HIT=1; break; }
    done
  fi
  # A non-ASCII spelling (hookſ opens as hooks on APFS) slips past every wake word; the verdict
  # casefolds it (adversarial review #4). Only the command and the path are read: prose in a Write's
  # content is not a path.
  if [ "$HIT" -eq 0 ]; then
    case "$TI" in *\"command\"*) has_non_ascii "$TI" && HIT=1 ;; esac
    [[ $TI =~ \"(file_path|notebook_path)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && has_non_ascii "${BASH_REMATCH[2]}" && HIT=1
  fi
  # A write into an existing plugin folder outside every root by a program not on the writer list
  # (curl -o, wget -O): every path-shaped word of a command is walked (adversarial review #3).
  # The walk below resolves words against the payload cwd only, and cannot expand a variable: a command
  # that moves (cd, pushd, -C) or holds any $ goes to the verdict, which follows both. A path with a JSON
  # escape (a quote in a folder name cuts the match short) or a .. segment does too (/security-review).
  if [ "$HIT" -eq 0 ]; then
    case "$TI" in *\"command\"*)
      _mv='(^|[^A-Za-z0-9_.-]|\\[nt])(cd|pushd)([[:space:]]|$)|[[:space:]]-C[[:space:]]'
      case "$TI" in *'$'*) HIT=1 ;; esac
      [[ $TI =~ $_mv ]] && HIT=1 ;;
    esac
    _pv='"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
    if [[ $TI =~ $_pv ]]; then
      case "${BASH_REMATCH[2]}" in *\\*|*/..|*/../*|../*|..) HIT=1 ;; esac
    fi
  fi
  if [ "$HIT" -eq 0 ]; then
    case "$TI" in *\"command\"*)
      _cwd=.
      [[ $INPUT =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && _cwd="${BASH_REMATCH[1]}"
      _n=0
      set -f
      for _t in ${N//[,:\{\}=\(\)\;\&\|\<\>]/ }; do
        case "$_t" in */*) ;; *) continue ;; esac
        _n=$((_n + 1))
        [ "$_n" -gt 64 ] && { HIT=1; break; }
        case "$_t" in "~"/*) _t="${HOME:-/nonexistent}${_t#\~}" ;; /*) ;; *) _t="$_cwd/$_t" ;; esac
        in_plugin_folder "$_t" && { HIT=1; break; }
      done
      set +f ;;
    esac
  fi
  if [ "$HIT" -eq 0 ]; then
    _cands=()
    [[ $TI =~ \"(file_path|notebook_path)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && _cands+=("${BASH_REMATCH[2]}")
    [[ $INPUT =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && _cands+=("${BASH_REMATCH[1]}")
    for _c in ${_cands[@]+"${_cands[@]}"}; do
      in_plugin_folder "$_c" && { HIT=1; break; }
    done
  fi
fi
[ "$HIT" -eq 1 ] || exit 0

HOOK_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! . "$HOOK_DIR/guard-lib.sh" 2>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED — settings-edit-guard cannot load scripts/guard-lib.sh, and this call names a settings file. Re-run the template sync (it is in CORE_SCRIPTS)."}}'
  exit 0
fi

VERDICT=$(printf '%s' "$INPUT" | python3 "$HOOK_DIR/settings_guard.py" 2>/dev/null) || VERDICT="crash"
[ -n "$VERDICT" ] || VERDICT="crash"
KIND=${VERDICT%%$'\t'*}
REST=""
case "$VERDICT" in *$'\t'*) REST=${VERDICT#*$'\t'} ;; esac
TARGET=${REST%%$'\t'*}
KEYS=""
case "$REST" in *$'\t'*) KEYS=${REST#*$'\t'} ;; esac

# The repair path: a crash denies everything it would judge except an edit of the guard itself.
if [ "$KIND" = crash ] && [[ $TI =~ \"file_path\"[[:space:]]*:[[:space:]]*\"[^\"]*/scripts/(settings-edit-guard-hook\.sh|settings_guard\.py|shell_glob\.py|guard-lib\.sh)\" ]]; then
  guard_context "settings-edit-guard crashed and ALLOWED this edit unchecked, because it is an edit of the guard's own code (${BASH_REMATCH[1]}): a guard that cannot run must not block its own repair. Fix the crash; every settings call it would judge is denied until then."
  exit 0
fi

ROUTES="Hook wiring and hook environment are the developer's to change. Show them the exact change you wanted (the JSON before and after, or the command), and ask them to apply it by hand in their editor, or to run it themselves with the \`!\` prefix (a \`!\` command runs outside the agent's tools, so no PreToolUse hook sees it). There is no override variable (spec 089, developer decision O3). Reading stays open: the Read tool, or cat / jq / grep in the shell."

case "$KIND" in
  none) exit 0 ;;
  settings-key)
    guard_deny "BLOCKED — this edit changes ${KEYS} in ${TARGET} (spec 089, 095).

Every settings key is guarded except a short safe list (\$schema, language, model, and permissions.allow, ask, additionalDirectories). hooks, env and disableAllHooks decide which guards run and what they see, and keys such as apiKeyHelper, statusLine or enabledPlugins run a command or add tools next session. Formatting and the safe keys stay editable.

$ROUTES" ;;
  settings-invalid)
    guard_deny "BLOCKED — after this edit ${TARGET} would not be a JSON object (spec 089).

Claude Code ignores a settings file it cannot parse, and every hook wired in it goes with it. Check the edit: a missing comma or brace is the usual cause.

$ROUTES" ;;
  settings-unreadable)
    guard_deny "BLOCKED — ${TARGET} is not a JSON object right now, so this guard cannot tell what the edit changes (spec 089).

The file needs a repair the developer makes by hand.

$ROUTES" ;;
  settings-shell)
    guard_deny "BLOCKED — a write to ${TARGET} that carries no bytes to check (a shell write, a NotebookEdit, or a glob path) (spec 089).

This guard judges a settings write by what it does to the guarded keys, and this route (a shell write, an MCP tool, a NotebookEdit) does not show it the result. Use the Edit tool for a change to another key; it is judged on the bytes.

$ROUTES" ;;
  settings-bash)
    guard_deny "BLOCKED — this shell command writes, or may write, a guarded settings file (spec 089). Derived target: ${TARGET}

The command is not shown here. Only reads pass when a command names one of the three settings files (cat, head, tail, grep, rg, jq, wc, diff, ls, stat, python3 -m json.tool <file>, git diff/log/show/status/add/commit, …). A redirection into one, an output option naming one, sed, cp, mv, rm, ln, touch, an interpreter or a script handed one are refused. If the file is only mentioned in prose (a message, a finding), drop the .claude/ prefix or use the Write tool for the text.

$ROUTES" ;;
  settings-git)
    guard_deny "BLOCKED — this git command would rewrite a settings file's guarded keys, or this guard cannot tell what it would write (spec 095). Target: ${TARGET}. Cause: ${KEYS}.

A git verb that writes the working tree (checkout, restore, switch, reset --hard, stash, clean, apply, am, merge, rebase, cherry-pick, revert, read-tree) is judged by the content it would leave. It passes when the settings files keep their hooks, env and other guarded keys, and is refused when they change or when git cannot answer. A pull from a configured remote is not judged.

$ROUTES" ;;
  mod-file|mod-bash|mod-git)
    case "$KIND" in
      mod-file) _how="this call writes" ;;
      mod-bash) _how="this shell command writes, or may write," ;;
      *)        _how="this git command would add, change or remove" ;;
    esac
    guard_deny "BLOCKED — ${_how} a Claude Code mod: ${TARGET}${KEYS:+ (${KEYS})} (spec 095a).

A plugin folder whose hooks/hooks.json names a module is a mod. Once loaded, its function hook can allow any tool call past every hook, settings guards included, and its module runs code of its own. So no agent tool creates or changes one: not a file in a folder that holds .claude-plugin or hooks/hooks.json, not anything under ~/.claude/plugins, ~/.claude/dev-mods or a folder on CLAUDE_CODE_PLUGIN_DIRS, not a skill folder in ~/.claude/skills, not a skill's hooks/ folder. The claude CLI's plugin install, --plugin-dir and --settings count as writes too.

Reading stays open: the Read tool, or cat / grep / ls in the shell. To install or change a mod, show the developer the files you want and ask them to put them in place in their editor or with a command they run with the \`!\` prefix (it runs outside the agent's tools). A mod staged under a name that does not load can be installed by a script the developer runs that way (row 096). There is no override." ;;
  crash)
    guard_deny "BLOCKED — settings-edit-guard crashed (python3 missing, or an error in scripts/settings_guard.py) on a call that names a settings file. It does not allow what it could not judge (spec 089). Its own files (scripts/settings-edit-guard-hook.sh, settings_guard.py, guard-lib.sh) stay editable with the Edit tool so it can be repaired." ;;
  *)
    guard_deny "BLOCKED — settings-edit-guard cannot read this call (the payload is not JSON), and its text names a settings file. A guard that cannot see what it guards does not allow (spec 089)." ;;
esac
exit 0
