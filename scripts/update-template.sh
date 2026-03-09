#!/usr/bin/env bash
# update-template.sh — Analyserar senaste Claude Code best practices online
# och uppdaterar mallrepots struktur (.claude/, CLAUDE.md, etc.)
#
# Användning:
#   ./scripts/update-template.sh              # Fullständig uppdatering
#   ./scripts/update-template.sh --dry-run    # Bara rapport, inga ändringar
#   ./scripts/update-template.sh --focus hooks # Fokusera på ett område
#
# Kräver: claude CLI (Claude Code) installerat

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=false
FOCUS=""
DATE=$(date +%Y-%m-%d)

# Parsning av argument
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --focus)   FOCUS="$2"; shift 2 ;;
    --help|-h)
      echo "Användning: $0 [--dry-run] [--focus <område>]"
      echo ""
      echo "Områden: hooks, skills, agents, rules, docs, settings, claude-md"
      echo ""
      echo "Exempel:"
      echo "  $0                    # Full uppdatering"
      echo "  $0 --dry-run          # Bara rapport"
      echo "  $0 --focus skills     # Bara skills-relaterat"
      exit 0
      ;;
    *) echo "Okänt argument: $1"; exit 1 ;;
  esac
done

# Validera att claude CLI finns
if ! command -v claude &>/dev/null; then
  echo "Fel: 'claude' CLI hittades inte. Installera Claude Code först."
  echo "  npm install -g @anthropic-ai/claude-code"
  exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Claude Code Template Updater                       ║"
echo "║  Datum: $DATE                                  ║"
echo "║  Läge: $([ "$DRY_RUN" = true ] && echo 'DRY RUN (inga ändringar)' || echo 'LIVE (uppdaterar filer)')           ║"
[ -n "$FOCUS" ] && \
echo "║  Fokus: $(printf '%-44s' "$FOCUS")║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Bygg fokusfilter
FOCUS_INSTRUCTION=""
if [ -n "$FOCUS" ]; then
  FOCUS_INSTRUCTION="Fokusera ENBART på området: $FOCUS. Ignorera andra områden."
fi

# Bygg dry-run-instruktion
MODE_INSTRUCTION=""
if [ "$DRY_RUN" = true ]; then
  MODE_INSTRUCTION="VIKTIGT: Detta är en DRY RUN. Gör INGA ändringar i filer. Skriv BARA en rapport med rekommendationer."
else
  MODE_INSTRUCTION="Genomför alla rekommenderade ändringar direkt i filerna. Skapa en git commit efteråt med meddelandet 'chore: Uppdatera mallrepo med senaste Claude Code best practices ($DATE)'."
fi

# Huvudprompt som skickas till Claude
PROMPT=$(cat <<'PROMPT_EOF'
Du är en expert på Claude Code-konfiguration. Din uppgift är att analysera de senaste nyheterna, riktlinjerna och best practices för Claude Code och sedan uppdatera detta mallrepo.

## Steg 1: Research (OBLIGATORISKT)

Sök online efter ALLT av följande. Använd WebSearch-verktyget för varje sökning:

1. **Claude Code changelog & release notes** — Sök: "Claude Code changelog 2026", "Claude Code release notes latest"
2. **CLAUDE.md best practices** — Sök: "CLAUDE.md best practices 2026", "claude code configuration guide"
3. **Agent Skills standard** — Sök: "agentskills.io", "claude code skills SKILL.md"
4. **Claude Code hooks** — Sök: "claude code hooks PostToolUse PreToolUse 2026"
5. **Claude Code nya features** — Sök: "claude code new features 2026", "anthropic claude code update"
6. **Context engineering** — Sök: "context engineering claude code", "claude code context management best practices"
7. **Claude Code settings.json schema** — Sök: "claude code settings.json schema permissions"
8. **Community best practices** — Sök: "claude code CLAUDE.md examples github", "claude code configuration template"

Samla ALL relevant information innan du går vidare.

## Steg 2: Analysera nuvarande struktur

Läs följande filer i detta repo:
- CLAUDE.md
- .claude/settings.json
- .claude/docs/skills.md
- .claude/docs/workflows.md
- .claude/docs/conventions.md
- .claude/rules/*.md
- .claude/agents/*.md
- .claude/skills/*/SKILL.md

## Steg 3: Identifiera gap

Jämför det du hittade online (steg 1) med nuvarande struktur (steg 2). Identifiera:

1. **Nya features** som borde användas men saknas
2. **Deprecated patterns** som borde tas bort eller ersättas
3. **Förbättrade mönster** som borde uppdateras
4. **Nya hooks/settings** som borde läggas till
5. **Nya skill-typer** som borde skapas
6. **Säkerhetsförbättringar** som saknas
7. **Prestanda/kontext-optimeringar** som kan göras

## Steg 4: Rapport och åtgärder

Skriv en tydlig rapport i följande format:

```
## Uppdateringsrapport ($DATE)

### Nya features hittade
- [feature]: [beskrivning] → [åtgärd]

### Deprecated/ändrade mönster
- [mönster]: [vad som ändrats] → [åtgärd]

### Rekommenderade uppdateringar
1. [fil]: [ändring]
2. [fil]: [ändring]

### Inga ändringar behövs
- [område]: [anledning]
```

$MODE_INSTRUCTION

$FOCUS_INSTRUCTION

## Regler

- Skriv ALL kommunikation på svenska
- Håll storleken på claude.md så låg som det är möjligt
- Kod och tekniska termer på engelska
- Bevara ALLA projektspecifika anpassningar (markerade med # PROJECT-SPECIFIC)
- Ändra ALDRIG grundstrukturen utan starka skäl
- Prioritera: Säkerhet > Korrekthet > Enkelhet
- Om du är osäker, rapportera istället för att ändra
- Kör humanizer-skillen på ALL genererad text som riktas till människor
PROMPT_EOF
)

# Ersätt variabler i prompten
PROMPT="${PROMPT//\$MODE_INSTRUCTION/$MODE_INSTRUCTION}"
PROMPT="${PROMPT//\$FOCUS_INSTRUCTION/$FOCUS_INSTRUCTION}"
PROMPT="${PROMPT//\$DATE/$DATE}"

echo "Startar Claude Code-analys..."
echo ""

# Kör Claude Code med prompten
cd "$REPO_ROOT"
claude -p "$PROMPT" --allowedTools "WebSearch,WebFetch,Read,Glob,Grep,Edit,Write,Bash,Skill,Agent" 2>&1 | tee "/tmp/claude-template-update-${DATE}.log"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "════════════════════════════════════════════════════════"
if [ $EXIT_CODE -eq 0 ]; then
  echo "Klar! Logg sparad: /tmp/claude-template-update-${DATE}.log"
  if [ "$DRY_RUN" = false ]; then
    echo ""
    echo "Granska ändringarna:"
    echo "  cd $REPO_ROOT && git diff"
  fi
else
  echo "Fel uppstod (exit code: $EXIT_CODE)"
  echo "Se loggen: /tmp/claude-template-update-${DATE}.log"
fi
