#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-sensitive-file-guard.sh — scripts/sensitive-file-guard-hook.sh and its retirement of the old
# inline hook (spec 083, R10, F039).
#
# The inline hook it replaces covered Read|Edit|Write, wanted a leading `/`, knew six names and
# allowed above 4096 bytes without jq. This runs the real hook over every tool that can name a path,
# relative and absolute spellings, the four added names, the .env templates the developer allowed
# (O1), a payload too large for the precheck, an unparseable one, and the sync-core-hooks retirement.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
HOOK="$SELF_DIR/sensitive-file-guard-hook.sh"
BASH_BIN=$(command -v bash)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

[ -f "$HOOK" ] || { echo "missing: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t sens); trap 'rm -rf "$WORK"' EXIT

run() {               # $1 = payload JSON, [$2 = hook]
  local rc
  LAST_OUT=$(printf '%s' "$1" | "$BASH_BIN" "${2:-$HOOK}" 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || { echo "exit-$rc"; return; }
  hook_verdict "$LAST_OUT"
}
tool() {              # $1 = tool, $2 = key, $3 = value
  jq -nc --arg t "$1" --arg k "$2" --arg v "$3" '{tool_name:$t, tool_input:{($k):$v}}'
}
expect() {            # $1 = want, $2 = label, $3 = payload
  local v; v=$(run "$3")
  [ "$v" = "$1" ] && ok "$1: $2" || { bad "$v (want $1): $2"; info "$LAST_OUT"; }
}

printf '\n[deny] every tool, every spelling  (083-AC-5)\n'
expect deny "Bash cat ~/.ssh/id_rsa"                 "$(tool Bash command 'cat ~/.ssh/id_rsa')"
expect deny "Read /home/u/.ssh/config"               "$(tool Read file_path /home/u/.ssh/config)"
expect deny "Read relative .ssh/config"              "$(tool Read file_path .ssh/config)"
expect deny "Edit .aws/credentials"                  "$(tool Edit file_path /home/u/.aws/credentials)"
expect deny "Write .azure/x"                         "$(tool Write file_path /home/u/.azure/x)"
expect deny "Read .netrc"                            "$(tool Read file_path /home/u/.netrc)"
expect deny "Read relative .npmrc"                   "$(tool Read file_path .npmrc)"
expect deny "Read .kube/config"                      "$(tool Read file_path /home/u/.kube/config)"
expect deny "Read .gnupg/secring.gpg"                "$(tool Read file_path /home/u/.gnupg/secring.gpg)"
expect deny "Read .git-credentials"                  "$(tool Read file_path /home/u/.git-credentials)"
expect deny "Read .docker/config.json"               "$(tool Read file_path /home/u/.docker/config.json)"
expect deny "Read .config/gh/hosts.yml"              "$(tool Read file_path /home/u/.config/gh/hosts.yml)"
expect deny "Read .env"                              "$(tool Read file_path /p/.env)"
expect deny "Read .env.local"                        "$(tool Read file_path /p/.env.local)"
expect deny "Read .env.production"                   "$(tool Read file_path /p/.env.production)"
expect deny "MultiEdit .env"                         "$(tool MultiEdit file_path /p/.env)"
expect deny "NotebookEdit under .ssh"                "$(tool NotebookEdit notebook_path /home/u/.ssh/n.ipynb)"
expect deny "Grep path ~/.aws"                       "$(tool Grep path /home/u/.aws)"
expect deny "Grep glob .env*"                        "$(jq -nc '{tool_name:"Grep",tool_input:{pattern:"KEY",glob:".env*"}}')"
expect deny "Glob pattern **/.env"                   "$(tool Glob pattern '**/.env')"
expect deny "Glob path ~/.gnupg"                     "$(tool Glob path /home/u/.gnupg)"
expect deny "Bash < redirect from .netrc"            "$(tool Bash command 'wc -l <~/.netrc')"
expect deny "Bash --flag=path"                       "$(tool Bash command 'tool --config=/home/u/.kube/config')"
expect deny "Bash \$HOME/.ssh"                       "$(tool Bash command 'ls $HOME/.ssh')"
expect deny "Bash cp .env.example .env (writes .env)" "$(tool Bash command 'cp .env.example .env')"
expect deny "Bash second line"                       "$(tool Bash command $'ls\ncat .aws/credentials')"

printf '\n[deny] the adversarial review'"'"'s spellings (spec 083)\n'
expect deny "bash -c 'cat .env' (an executed body)"  "$(tool Bash command "bash -c 'cat .env'")"
expect deny "eval 'cat .netrc'"                      "$(tool Bash command "eval 'cat .netrc'")"
expect deny "echo \"\$(cat .env)\""                  "$(tool Bash command 'echo "$(cat .env)"')"
expect deny "echo 'cat .npmrc' | sh"                 "$(tool Bash command "echo 'cat .npmrc' | sh")"
expect deny "a name split by quotes: .s\"\"sh"       "$(tool Bash command 'cat ~/.s""sh/id_rsa')"
expect deny "a name split by a backslash"            "$(tool Bash command 'cat ~/.s\sh/id_rsa')"
expect deny "brace expansion {.ssh,x}"               "$(tool Bash command 'cat ~/{.ssh,x}/id_rsa')"
expect deny "a dot glob .ss[h]"                      "$(tool Bash command 'cat ~/.ss[h]/id_rsa')"
expect deny "a dot glob .s* (security-review)"       "$(tool Bash command 'cat ~/.s*/id_rsa')"
expect deny "a dot glob .n?trc (security-review)"    "$(tool Bash command 'cat ~/.n?trc')"
expect deny "Glob **/.s?h/* (security-review)"       "$(tool Glob pattern '**/.s?h/*')"
expect deny "upper case ~/.SSH (case-insensitive FS)" "$(tool Bash command 'cat ~/.SSH/id_rsa')"
expect deny "Read ~/.AWS/credentials"                "$(tool Read file_path /home/u/.AWS/credentials)"
expect deny "Read .pgpass"                           "$(tool Read file_path /home/u/.pgpass)"
expect deny "Read .config/gcloud/credentials.db"     "$(tool Read file_path /home/u/.config/gcloud/credentials.db)"

printf '\n[allow] templates, prose, the everyday\n'
expect none "grep -rn \"\\.env\" docs/ (searching for the text)" "$(tool Bash command 'grep -rn "\.env" docs/')"
expect none "Read .env.example (O1)"                 "$(tool Read file_path /p/.env.example)"
expect none "Read .env.sample (O1)"                  "$(tool Read file_path /p/.env.sample)"
expect none "Read .env.template (O1)"                "$(tool Read file_path /p/.env.template)"
expect none "Bash cat .env.example"                  "$(tool Bash command 'cat .env.example')"
expect none "Bash commit message mentioning .env"    "$(tool Bash command 'git commit -m "fix .env loading"')"
expect none "Write a doc whose content mentions ~/.ssh" "$(jq -nc '{tool_name:"Write",tool_input:{file_path:"/p/docs/a.md",content:"never read ~/.ssh/id_rsa"}}')"
expect none "Read src/environment.ts"                "$(tool Read file_path /p/src/environment.ts)"
expect none "Read tsconfig.json"                     "$(tool Read file_path /p/tsconfig.json)"
expect none "Read webpack.config.js"                 "$(tool Read file_path /p/webpack.config.js)"
expect none "Grep pattern .env (the text, not a path)" "$(jq -nc '{tool_name:"Grep",tool_input:{pattern:"\\.env",path:"/p/src"}}')"
expect none "Glob **/*.ts"                           "$(tool Glob pattern '**/*.ts')"
expect none "Bash git status"                        "$(tool Bash command 'git status')"
expect none "Bash ls * (a glob without a dot reaches no dotfile)" "$(tool Bash command 'ls * **')"
expect none "Bash cat > doc <<E with prose naming .env" "$(tool Bash command $'cat > d.md <<\'E\'\nsee .env and **\nE')"
expect none "Bash python3 - <<E whose program says .env" "$(tool Bash command $'python3 - <<\'E\'\nprint(".env")\nE')"
expect deny "Bash ls .env* (a dot glob)"             "$(tool Bash command 'ls .env*')"
expect deny "Bash bash <<E that cats a key"          "$(tool Bash command $'bash <<E\ncat ~/.ssh/id_rsa\nE')"

printf '\n[sed] a pure substitution is a pattern, a file operand or file command is a path  (090-AC-5, R8a)\n'
expect none "090-AC-5 sed 's/.env//' f.txt (F085)" "$(tool Bash command "sed 's/.env//' f.txt")"
expect none "sed -i '' 's/.env//' f.txt (BSD -i)" "$(tool Bash command "sed -i '' 's/.env//' f.txt")"
expect none "sed -e 's|.ssh|x|g' -e 'y/a/b/' f" "$(tool Bash command "sed -e 's|.ssh|x|g' -e 'y/a/b/' f")"
expect none "sed --expression=s/.env// f" "$(tool Bash command "sed --expression=s/.env// f")"
expect none "sed -ne 's/.env//p' f" "$(tool Bash command "sed -ne 's/.env//p' f")"
expect none "sed -- 's/.env//' f" "$(tool Bash command "sed -- 's/.env//' f")"
expect deny "090-AC-5 sed 's/a/b/' .env (a file operand)" "$(tool Bash command "sed 's/a/b/' .env")"
expect deny "sed -n 's/x/y/p' .env" "$(tool Bash command "sed -n 's/x/y/p' .env")"
expect deny "sed -f .env x (a script file)" "$(tool Bash command "sed -f .env x")"
expect deny "sed 'r .env' README.md (sed reads it)" "$(tool Bash command "sed 'r .env' README.md")"
expect deny "sed -n -e 'R .env' f" "$(tool Bash command "sed -n -e 'R .env' f")"
expect deny "sed 's/x/y/w .env' f (the w flag writes it)" "$(tool Bash command "sed 's/x/y/w .env' f")"
expect deny "sed 's/x/y/w.env' f (no space)" "$(tool Bash command "sed 's/x/y/w.env' f")"
expect deny "sed '1e cat .env' f (e runs a command)" "$(tool Bash command "sed '1e cat .env' f")"
expect deny "sed 's/a/b/;r .env' f (two commands)" "$(tool Bash command "sed 's/a/b/;r .env' f")"
expect deny "review #4: sed -n '1r.env' f.txt" "$(tool Bash command "sed -n '1r.env' f.txt")"
expect deny "review #4: sed -n -e '1R.env' f.txt" "$(tool Bash command "sed -n -e '1R.env' f.txt")"
expect deny "review #4: sed --expression=1r.env f.txt" "$(tool Bash command "sed --expression=1r.env f.txt")"
expect deny "review #4: sed 's/x/y/;1r.env' f.txt" "$(tool Bash command "sed 's/x/y/;1r.env' f.txt")"
expect deny "review #4: sed -n '/r/r.env' f.txt" "$(tool Bash command "sed -n '/r/r.env' f.txt")"
expect deny "review #4: sed 's/r/b/w.env' f.txt" "$(tool Bash command "sed 's/r/b/w.env' f.txt")"
expect deny "/security-review: sed -f script.sed s/x/.env/ (with -f every operand is a path)" "$(tool Bash command "sed -f script.sed s/x/.env/")"
expect deny "sed -nf prog .env" "$(tool Bash command "sed -nf prog .env")"
expect deny "sed --file=prog .env" "$(tool Bash command "sed --file=prog .env")"
expect none "sed -e's/.env//' f (an attached script)" "$(tool Bash command "sed -e's/.env//' f")"
expect deny "perl -pe 's/.env//' f (a program, not a pattern)" "$(tool Bash command "perl -pe 's/.env//' f")"

printf '\n[size and parse] the old fail-open paths\n'
BIG=$(python3 -c 'import json; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":"/home/u/.ssh/config","old_string":"x"*9000,"new_string":"y"}}))')
expect deny "a 9 KB Edit of .ssh/config" "$BIG"
BIGOK=$(python3 -c 'import json; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":"/p/a.md","content":"x"*9000}}))')
expect none "a 9 KB Write elsewhere" "$BIGOK"
expect deny "a truncated payload mentioning .ssh" '{"tool_name":"Read","tool_input":{"file_path":"/home/u/.ssh/id_rsa"'
expect none "a truncated payload mentioning nothing" '{"tool_name":"Read","tool_input":{"file_path":"/p/a.md"'
mkdir -p "$WORK/nopy"; cp "$HOOK" "$SELF_DIR/guard-lib.sh" "$SELF_DIR/hook-notice.sh" "$WORK/nopy/"
printf 'import sys\nsys.exit(1)\n' > "$WORK/nopy/sensitive_paths.py"
V=$(run "$(tool Read file_path /home/u/.ssh/id_rsa)" "$WORK/nopy/sensitive-file-guard-hook.sh")
[ "$V" = deny ] && ok "a classifier that crashes: deny" || bad "crashed classifier: $V"

printf '\n[reason] names the path, never a whole command\n'
run "$(tool Bash command 'cat ~/.ssh/id_rsa && echo TOKEN=abc123')" >/dev/null
R=$(printf '%s' "$LAST_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
case "$R" in *abc123*) bad "the reason echoes the command" ;; *) ok "the reason does not echo the command" ;; esac
case "$R" in *".ssh/id_rsa"*) ok "the reason names the path" ;; *) bad "the reason does not name the path" ;; esac

printf '\n[retire] sync-core-hooks drops the old inline hook once the script is there\n'
P="$WORK/proj"; mkdir -p "$P/.claude" "$P/scripts"
python3 - "$SELF_DIR/sync-core-hooks.py" "$P/.claude/settings.json" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("sch", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
old73 = m._TEMPLATE_INLINE_SPEEDUPS[0][2]; old = m._TEMPLATE_INLINE_SPEEDUPS[0][1]
json.dump({"hooks": {"PreToolUse": [
    {"matcher": "Read|Edit|Write", "hooks": [{"type": "command", "command": old73}]},
    {"matcher": "Read", "hooks": [{"type": "command", "command": old}]},
    {"matcher": "Read", "hooks": [{"type": "command", "command": old73 + " # project's own"}]},
]}}, open(sys.argv[2], "w"))
PY
cp "$SELF_DIR/sync-core-hooks.py" "$P/scripts/"
( cd "$P" && python3 scripts/sync-core-hooks.py "$SELF_DIR/../.claude/settings.json" >/dev/null 2>&1 )
N=$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(sum(1 for m in s["hooks"].get("PreToolUse",[]) for h in m["hooks"] if "sensitive files" in h.get("command","")))' "$P/.claude/settings.json")
[ "$N" = 3 ] && ok "without the script in the project, both template texts stay (3 inline hooks)" || bad "retired without the script: $N left"
cp "$HOOK" "$SELF_DIR/sensitive_paths.py" "$P/scripts/"
( cd "$P" && python3 scripts/sync-core-hooks.py "$SELF_DIR/../.claude/settings.json" >/dev/null 2>&1 )
python3 - "$P/.claude/settings.json" <<'PY' && ok "with the script: both template texts retired, the project's own copy kept, the script hook wired" || bad "retirement did not happen as specified"
import json, sys
s = json.load(open(sys.argv[1]))
cmds = [h.get("command", "") for m in s["hooks"].get("PreToolUse", []) for h in m["hooks"]]
inline = [c for c in cmds if "sensitive files" in c]
assert len(inline) == 1 and inline[0].endswith("# project's own"), inline
assert any("sensitive-file-guard-hook.sh" in c for c in cmds), cmds
PY

printf '\n[sabotage] the matrix bites\n'
SAB="$WORK/sab"; mkdir -p "$SAB"; cp "$HOOK" "$SELF_DIR/guard-lib.sh" "$SELF_DIR/hook-notice.sh" "$SELF_DIR/shell_glob.py" "$SAB/"
sed 's/SEGMENTS = {".ssh", ".aws", ".azure", ".kube", ".gnupg"}/SEGMENTS = {".ssh", ".aws", ".azure"}/' "$SELF_DIR/sensitive_paths.py" > "$SAB/sensitive_paths.py"
V=$(run "$(tool Read file_path /home/u/.kube/config)" "$SAB/sensitive-file-guard-hook.sh")
[ "$V" != deny ] && ok "a list without .kube lets it through — the matrix would see it" || bad "sabotage .kube not observable"
sed 's/if base in ENV_TEMPLATES:/if False:/' "$SELF_DIR/sensitive_paths.py" > "$SAB/sensitive_paths.py"
V=$(run "$(tool Read file_path /p/.env.example)" "$SAB/sensitive-file-guard-hook.sh")
[ "$V" = deny ] && ok "without the O1 exception .env.example is denied — the allow arm would see it" || bad "sabotage O1 not observable"
sed 's/out.extend((w, True) for w in shell_words(ti\["command"\]))/pass/' "$SELF_DIR/sensitive_paths.py" > "$SAB/sensitive_paths.py"
V=$(run "$(tool Bash command 'cat ~/.ssh/id_rsa')" "$SAB/sensitive-file-guard-hook.sh")
[ "$V" != deny ] && ok "a classifier that skips Bash lets cat ~/.ssh through — AC-5 would see it" || bad "sabotage Bash not observable"
cp "$SELF_DIR/destructive_command.py" "$SAB/"     # the shell tokeniser the sed rule rides on
sed 's/    return \[tok for tok, body in sed_scripts(args) if _SED_PURE.match(body)\]/    return []/' "$SELF_DIR/sensitive_paths.py" > "$SAB/sensitive_paths.py"
V=$(run "$(tool Bash command "sed 's/.env//' f.txt")" "$SAB/sensitive-file-guard-hook.sh")
[ "$V" = deny ] && ok "without the sed rule s/.env// is denied again — the 090 arm would see it" || bad "sabotage sed not observable"
sed 's/    return out$/    return []/' "$SELF_DIR/sensitive_paths.py" > "$SAB/sensitive_paths.py"
V=$(run "$(tool Bash command "sed 'r .env' README.md")" "$SAB/sensitive-file-guard-hook.sh")
[ "$V" != deny ] && ok "without the script split sed 'r .env' passes — the 090 arm would see it" || bad "sabotage sed split not observable"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
