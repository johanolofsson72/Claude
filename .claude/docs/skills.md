# Skills

Skills ger Claude specialiserade förmågor genom SKILL.md-filer med instruktioner och frontmatter. Claude Code följer Agent Skills-standarden (agentskills.io) — ekosystemet har vuxit till 349+ skills i 12 kategorier (mars 2026). OpenAI har adopterat samma format för Codex CLI.

## Hur skills fungerar

### Progressiv laddning

1. **Metadata** (~100 tokens) — `name` + `description` laddas vid sessionstart för ALLA skills
2. **Instruktioner** (<5000 tokens rekommenderat) — full SKILL.md laddas vid aktivering
3. **Resurser** (vid behov) — stödfiler laddas när de refereras

### Anropsmetoder

- **Manuellt:** Användaren skriver `/skill-namn` (slash command)
- **Automatiskt:** Claude laddar skillen baserat på `description`-matchning
- **Blockerande:** Skills med `disable-model-invocation: true` kan bara anropas manuellt

## Projektskills (`.claude/skills/`)

Dessa skills levereras med mallrepot:

| Skill | Typ | Beskrivning |
| --- | --- | --- |
| `/code-review` | `context: fork` | Kodgranskning med isolerad kontext |
| `/explore-codebase` | `context: fork` | Djup arkitekturanalys via Explore-agent |
| `/deploy-checklist` | `disable-model-invocation` | Pre-deploy verifiering (bara manuellt) |
| `/update-template` | standard | Söker online efter senaste best practices och uppdaterar mallrepot |
| `/sync-template` | `disable-model-invocation` | Synkar projektkonfiguration från mallrepot |

## SKILL.md-struktur

### Obligatoriska fält (Agent Skills-standarden)

```yaml
---
name: my-skill          # Gemener, siffror, bindestreck. Max 64 tecken. Matchar mappnamn.
description: >          # Max 1024 tecken. Beskriv VAD och NÄR. Inkludera trigger-nyckelord.
  Reviews code for bugs and security issues.
  Use when asking for code review or after significant changes.
---
```

### Valfria fält (Claude Code-tillägg)

```yaml
---
argument-hint: "[issue-number]"       # Ledtråd vid autocomplete
disable-model-invocation: true        # Bara användaren kan anropa (deploy, commit)
user-invocable: false                 # Göm från /-menyn (bakgrundskunskap)
allowed-tools: Read, Grep, Glob       # Verktyg utan behörighetsprompt
model: sonnet                        # Åsidosätt modell (sonnet|opus|haiku)
context: fork                         # Kör i isolerad subagent-kontext
agent: Explore                        # Subagent-typ (Explore, Plan, general-purpose, custom)
hooks:                                # Hooks scopade till skillens livscykel
  PostToolUse:
    - matcher: "Edit"
      hooks:
        - type: command
          command: "./scripts/lint.sh"
---
```

### Anropskontroll

| Frontmatter | Användare | Claude | Laddning |
| --- | --- | --- | --- |
| (standard) | Ja | Ja | Description alltid, full vid anrop |
| `disable-model-invocation: true` | Ja | Nej | Description INTE i kontext |
| `user-invocable: false` | Nej | Ja | Description alltid i kontext |

## Strängsubstitutioner

| Variabel | Beskrivning |
| --- | --- |
| `$ARGUMENTS` | Alla argument vid anrop |
| `$ARGUMENTS[N]` / `$N` | Specifikt argument (0-baserat) |
| `${CLAUDE_SESSION_ID}` | Aktuellt sessions-ID |
| `${CLAUDE_SKILL_DIR}` | Mappen som innehåller SKILL.md |

## Dynamisk kontextinjektion

Kör shell-kommandon under preprocessing med `` !`command` ``:

```markdown
## PR-kontext
- Diff: !`gh pr diff`
- Kommentarer: !`gh pr view --comments`
```

## Katalogstruktur för skills

```text
my-skill/
├── SKILL.md           # Obligatorisk — huvudinstruktioner
├── scripts/           # Körbara hjälpskript
│   └── helper.py
├── references/        # Referensmaterial (laddas vid behov)
│   └── REFERENCE.md
└── assets/            # Statiska resurser (mallar, scheman)
    └── template.html
```

## Placering och prioritet

| Plats | Sökväg | Gäller |
| --- | --- | --- |
| Enterprise | Managed settings | Alla i organisationen |
| Personlig | `~/.claude/skills/<skill>/SKILL.md` | Alla dina projekt |
| Projekt | `.claude/skills/<skill>/SKILL.md` | Bara detta projekt |
| Plugin | `<plugin>/skills/<skill>/SKILL.md` | Där pluginen är aktiverad |

Vid namnkonflikter: enterprise > personlig > projekt. Plugin-skills använder namespace (`plugin:skill`).

### Automatisk upptäckt i underkataloger

I monorepo-setups upptäcker Claude Code skills från nestade `.claude/skills/`-kataloger automatiskt. Om du redigerar filer i `packages/frontend/` laddas även skills från `packages/frontend/.claude/skills/`.

### Skills från extra kataloger

Skills i `.claude/skills/` från kataloger som lagts till via `--add-dir` laddas automatiskt med live change detection — du kan redigera dem under en session utan omstart.

### Storleksrekommendation

Håll `SKILL.md` under 500 rader. Flytta detaljerat referensmaterial till separata filer i skillens katalog och referera dem från SKILL.md.

## Rekommenderade externa skills

Installera till `~/.claude/skills/` för att dela mellan projekt:

| Skill | Repo | Beskrivning |
| --- | --- | --- |
| **anthropics/skills** | `anthropics/skills` | Officiell samling (frontend-design, PDF, PPTX, XLSX) |
| **superpowers** | `obra/superpowers` | Planering, TDD, kodgranskning |
| **context-engineering** | `muratcankoylan/Agent-Skills-for-Context-Engineering` | Multi-agent-arkitekturer |
| **trailofbits/skills** | `trailofbits/skills` | Säkerhetsforsknings-skills |

### Installation

```bash
declare -A SKILL_REPOS=(
  [anthropics-skills]="anthropics/skills"
  [superpowers]="obra/superpowers"
  [context-engineering]="muratcankoylan/Agent-Skills-for-Context-Engineering"
  [trailofbits-skills]="trailofbits/skills"
)

for skill in "${!SKILL_REPOS[@]}"; do
  if [ ! -d "$HOME/.claude/skills/$skill" ]; then
    echo "Installerar skill: $skill"
    git clone "https://github.com/${SKILL_REPOS[$skill]}.git" "$HOME/.claude/skills/$skill"
  fi
done
```

## Kända begränsningar

- YAML multiline-indikatorer (`>-`, `|`, `|-`) parsas inte korrekt i skills-indexeraren — använd enrads-strängar för `description`
- Kontextbudget: skill-beskrivningar använder ~2% av kontextfönstret (fallback: 16 000 tecken)
- Åsidosätt med `SLASH_COMMAND_TOOL_CHAR_BUDGET` miljövariabel vid behov
- `/clear` nollställer cachade skills

## Rekommenderade plugins

LSP-plugins ger kodnavigering (~50ms istället för ~45s textsök):

```bash
# .NET-projekt
dotnet tool install --global csharp-ls 2>/dev/null || true

# TypeScript/JavaScript
npm i -g typescript-language-server typescript 2>/dev/null || true

# GitHub-integration
# /plugin install github@claude-plugins-official
```
