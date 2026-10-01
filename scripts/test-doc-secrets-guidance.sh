#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Self-test for the template's own docs (spec 072): no doc may tell a project to keep production
# secrets in environment variables, or any secret in appsettings.json. rules/security.md said
# "use appsettings.json (local) or environment variables (production)" for months. teach spec 014
# found the cost: `docker service inspect` prints every environment variable in plain text, so it
# moved every secret to Swarm secret files and refused any other source (teach F061). A rule that
# names the weaker shape steers the next project into it.
#
# Template-only: it checks the template's docs, and projects receive the fixed docs through sync.
#
# Run:  bash scripts/test-doc-secrets-guidance.sh            (scan the template docs)
#       bash scripts/test-doc-secrets-guidance.sh FILE...    (scan these files instead)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Advice shapes that place a secret in env vars or appsettings. Matched case-insensitively per line.
# Prose that mentions env vars as a fallback, or says "never in appsettings", matches none of them.
BAD='environment variables? \(production\)|\(only in environment variables\)|appsettings(\.[a-z]+)?\.json`? \(local\)|environment variables? in `?appsettings'

# Prints "<file>:<line>: <text>" for every line giving the old advice.
scan() {
  grep -HniE "$BAD" "$@" 2>/dev/null | sed -E 's/^([^:]+):([0-9]+):/\1:\2: /'
}

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

if [ $# -gt 0 ]; then
  HITS=$(scan "$@")
  [ -z "$HITS" ] && { echo "clean"; exit 0; }
  printf '%s\n' "$HITS"; exit 1
fi

# --- the real docs --------------------------------------------------------------------------------
DOCS=()
for f in "$ROOT"/.claude/docs/*.md "$ROOT"/.claude/rules/*.md "$ROOT"/.claude/skills/*/SKILL.md "$ROOT"/CLAUDE.md; do
  [ -f "$f" ] && DOCS+=("$f")
done
[ ${#DOCS[@]} -gt 0 ] || { echo "ERROR: no docs found under $ROOT — nothing was scanned." >&2; exit 2; }

HITS=$(scan "${DOCS[@]}")
if [ -z "$HITS" ]; then ok "no doc puts secrets in env vars or appsettings.json (${#DOCS[@]} docs)"
else bad "a doc still gives the env-var / appsettings secrets advice" "$HITS"; fi

# The replacement has to exist, not just the old advice be gone.
SEC="$ROOT/.claude/docs/security.md"
for needle in '## Secrets' 'op run --env-file' 'docker secret create' 'AddKeyPerFile' 'RUN --mount=type=secret'; do
  if grep -qF -- "$needle" "$SEC"; then ok "docs/security.md carries '$needle'"
  else bad "docs/security.md is missing '$needle'"; fi
done
grep -qF '/run/secrets' "$ROOT/.claude/docs/deployment.md" \
  && ok "deployment.md mounts secrets as files" || bad "deployment.md never mentions /run/secrets"
for f in "$ROOT/.claude/rules/security.md" "$ROOT/.claude/skills/deploy-checklist/SKILL.md"; do
  grep -qF 'security.md' "$f" && grep -qiF 'secret' "$f" \
    && ok "${f#"$ROOT"/} points at the secrets pattern" || bad "${f#"$ROOT"/} does not point at docs/security.md"
done

# --- the scanner bites (sabotage arms) ------------------------------------------------------------
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
printf -- '- Never store secrets in code — use appsettings.json (local) or environment variables (production).\n' > "$TMP/rule.md"
case "$(scan "$TMP/rule.md")" in *rule.md:1:*) ok "sabotage: the pre-072 rule line is caught" ;;
  *) bad "sabotage: the pre-072 rule line was NOT caught" ;; esac

printf -- '- No secrets in appsettings.json (only in environment variables)\n' > "$TMP/check.md"
[ -n "$(scan "$TMP/check.md")" ] && ok "sabotage: the pre-072 checklist line is caught" \
  || bad "sabotage: the pre-072 checklist line was NOT caught"

printf -- '    - Environment variables in `appsettings.Production.json`\n' > "$TMP/wizard.md"
[ -n "$(scan "$TMP/wizard.md")" ] && ok "sabotage: the pre-072 wizard option is caught" \
  || bad "sabotage: the pre-072 wizard option was NOT caught"

printf -- '%s\n' \
  '- Environment variables are the fallback only where the platform has no file-mounted secret store.' \
  '- Committed config (`appsettings.json`, `.env.example`) holds placeholders, never a value.' \
  '- `ASPNETCORE_ENVIRONMENT=Production` is set as an environment variable.' > "$TMP/new.md"
[ -z "$(scan "$TMP/new.md")" ] && ok "the new wording and ordinary env-var prose are allowed" \
  || bad "the new wording was flagged" "$(scan "$TMP/new.md")"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
