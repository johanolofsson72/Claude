# Arbetsflöden och verktyg

## Spec-driven arbetsmodell

Om projektet använder ett spec-kit eller liknande:

- Prioritera spec-kitets arbetsmodell i första hand.
- Alla implementationer utgår från specifikationen.
- Avvikelser kräver explicit godkännande.
- Standarduppgift: [T.ex. "Hitta högst numrerade ofullständiga spec och implementera den."]

## Frontend design skill — detaljer

**Triggerord som kräver frontend-design skill:**

- Design, utseende, layout, styling, CSS, färg, font, typografi
- Knapp, formulär, navbar, footer, header, sidebar, modal, kort/card
- Responsivt, mobil, dark mode, tema, animation
- "Snyggare", "finare", "modernare", "proffsigare", "bättre utseende"

**Korrekt ordning:**

1. Användaren frågar om något UI-relaterat
2. **FÖRST:** Anropa `Skill`-verktyget med `skill: "frontend-design"`
3. **SEDAN:** Följ instruktionerna från skillen för implementation

## Plugins

Plugins buntar skills, agents, hooks, MCP-servrar och LSP-servrar i ett distribuerbart paket. Installeras med `/plugin install`.

**Skillnad mot skills:**

- **Skill** = en SKILL.md-fil med instruktioner (körs i huvudkontexten)
- **Plugin** = ett paket som kan innehålla skills + agents + hooks + MCP + LSP

### LSP-plugins (Code Intelligence)

LSP-plugins ger Claude kodnavigering på ~50ms istället för ~45s textsök. **Installera alltid relevanta LSP-plugins för projektets språk.**

| Språk | Plugin | Binär | Installera binär |
| --- | --- | --- | --- |
| **C#** | `csharp-lsp` | `csharp-ls` | `dotnet tool install --global csharp-ls` |
| **TypeScript** | `typescript-lsp` | `typescript-language-server` | `npm i -g typescript-language-server typescript` |
| PHP | `php-lsp` | `intelephense` | `npm i -g intelephense` |

**Installation:**

```bash
# 1. Installera binären först
dotnet tool install --global csharp-ls

# 2. Sedan plugin
/plugin install csharp-lsp@claude-plugins-official
```

### Vanliga plugins

```bash
# Projekthantering
/plugin install github@claude-plugins-official

# Övriga användbara
/plugin install sentry@claude-plugins-official     # Felspårning
/plugin install slack@claude-plugins-official       # Kommunikation
```

### Pluginscopes

| Scope | Fil | Gäller |
| --- | --- | --- |
| `user` (default) | `~/.claude/settings.json` | Alla dina projekt |
| `project` | `.claude/settings.json` | Alla i teamet (via git) |
| `local` | `.claude/settings.local.json` | Bara du, i detta repo |

```bash
/plugin install <namn>@<marknadsplats> --scope project  # Delat med teamet
/plugin disable <namn>@<marknadsplats>                   # Avaktivera
/plugin update <namn>@<marknadsplats>                    # Uppdatera
```

## Hooks (deterministiska regler)

Överväg Claude Code hooks (`.claude/settings.json`) för regler som MÅSTE efterlevas utan undantag. Till skillnad från CLAUDE.md-instruktioner som är rådgivande är hooks deterministiska och garanterade.

**Hooktyper:**

| Hook-event | När det utlöses |
| --- | --- |
| `PreToolUse` | Innan ett verktygsanrop — kan blockera |
| `PostToolUse` | Efter ett verktygsanrop lyckas |
| `Stop` | När Claude slutar svara |
| `SessionStart` | När session startar eller återvänder |
| `SubagentStart/Stop` | När en subagent startas/stoppas |
| `PreCompact` | Innan kontextkomprimering |
| `TaskCompleted` | När en uppgift markeras som klar |

**Tre typer av hooks:**

- `command` — kör shell-kommando (standard)
- `prompt` — envägs-evaluering med Claude (Haiku), returnerar ja/nej
- `agent` — flervägs-verifiering med verktygsåtkomst (kan läsa filer, köra kommandon)

**Vanliga automatiseringar:**

- Post-edit hook: kör linter efter varje filändring
- Pre-commit hook: kör `dotnet build` innan commit
- Blockerings-hook: förhindra skrivning till skyddade kataloger
- Stop-hook (agent): verifiera att tester passerar innan Claude stannar

**Exempel — Stop-hook för testverifiering:**

```json
{
  "hooks": {
    "Stop": [{
      "type": "agent",
      "description": "Verify tests pass before stopping",
      "hook": "Kontrollera att dotnet build och dotnet test passerar."
    }]
  }
}
```

**Exempel — Återinför kontext efter kompaktering:**

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "compact",
      "hooks": [{
        "type": "command",
        "command": "echo 'Påminnelse: använd dotnet, kör dotnet test innan commit.'"
      }]
    }]
  }
}
```

## Subagenter

Skapa dedikerade subagenter i `.claude/agents/` för isolerade uppgifter som inte ska fylla huvudkontexten. Subagenter körs i egna kontextfönster och rapporterar tillbaka sammanfattningar.

Skapa via `/agents`-kommandot eller manuellt som markdown-filer.

### YAML-frontmatter — komplett referens

```yaml
---
name: agent-name              # Krävs. Gemener och bindestreck
description: When to use      # Krävs. Claude använder detta för delegering
tools: Read, Grep, Glob       # Valfritt. Allowlist för verktyg
disallowedTools: Write, Edit  # Valfritt. Denylist
model: sonnet                 # Valfritt. sonnet|opus|haiku (default: inherit)
permissionMode: default       # Valfritt. default|acceptEdits|dontAsk|plan
maxTurns: 20                  # Valfritt. Max antal agentvarv
memory: project               # Valfritt. user|project|local (bestående minne)
isolation: worktree           # Valfritt. Kör i isolerad git worktree
background: false             # Valfritt. true = kör i bakgrunden
skills:                       # Valfritt. Skills att ladda in i kontexten
  - api-conventions
hooks:                        # Valfritt. Hooks scopade till denna agent
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/lint.sh"
---

Systemprompt börjar här. Agenten får BARA detta prompt.
```

### Fältbeskrivningar

| Fält | Beskrivning |
| --- | --- |
| `name` | Unikt ID, gemener och bindestreck |
| `description` | **Kritiskt** — Claude delegerar baserat på detta. Inkludera "Use proactively" för automatisk användning |
| `tools` | Allowlist. Utelämnad = ärver alla verktyg |
| `disallowedTools` | Denylist. Tas bort från ärvda verktyg |
| `model` | `opus` (mest kapabel), `sonnet` (balans), `haiku` (snabbast/billigast) |
| `permissionMode` | `acceptEdits` auto-godkänner filändringar, `plan` = bara läsning |
| `memory` | `user` = alla projekt, `project` = delbart via git, `local` = bara du |
| `isolation` | `worktree` = isolerad git-kopia, städas automatiskt |
| `background` | Kör medan du fortsätter arbeta. MCP-verktyg ej tillgängliga |
| `skills` | Hela skill-innehållet injiceras vid start. Ärvs INTE från föräldern |

### Placering

| Plats | Scope |
| --- | --- |
| `.claude/agents/` | Projektspecifik (delas via git) |
| `~/.claude/agents/` | Personlig (alla projekt) |

### Kopieringsbara agentmallar

Se @.claude/docs/agents-templates.md för färdiga agenter anpassade för .NET/fullstack-projekt:

- **dotnet-reviewer** — kodgranskning för C#/ASP.NET Core
- **security-scanner** — säkerhetsskanning (SQL injection, XSS, secrets)
- **test-runner** — kör och analyserar testresultat
- **db-agent** — EF Core migrations, schema, queries

## Agent Teams (experimentellt)

Flera Claude Code-instanser som arbetar tillsammans med direkt kommunikation och delad uppgiftslista. En session är teamledare, övriga är medlemmar.

**Aktivera:**

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

**Skillnad mot subagenter:**

- Subagenter rapporterar bara tillbaka resultat
- Team-medlemmar kommunicerar direkt med varandra och koordinerar självständigt

**Bäst för:** Komplexa uppgifter med flera parallella spår (frontend + backend + tester).

## Parallella sessioner

- **Writer/Reviewer**: En session implementerar, en annan granskar
- **Fan-out**: `for file in $(cat files.txt); do claude -p "Migrera $file" --allowedTools "Edit"; done`

## Thinking triggers

- `think` → ~4 000 tokens tankebudget
- `think hard` → ~10 000 tokens
- `ultrathink` → ~32 000 tokens (rekommenderas för arkitekturbeslut och svår felsökning)

## Sessions-hantering

- `claude --continue` — återuppta senaste sessionen
- `claude --resume` — välj bland tidigare sessioner
- `/rewind` eller `Esc+Esc` — gå tillbaka till tidigare checkpoint
- `/rename` — ge sessionen beskrivande namn för enkel återfinnbarhet
- `/compact <instruktioner>` — kontrollerad komprimering med fokusområde, t.ex. `/compact Fokusera på API-ändringarna`

## Auto memory (MEMORY.md)

Claude sparar automatiskt användbara insikter till `~/.claude/projects/<projekt>/memory/MEMORY.md`. De första 200 raderna laddas i varje session.

- Säg "kom ihåg att vi använder X" för att spara specifik information
- Använd `/memory` för att öppna och redigera minnesfiler i editorn
- Skapa ämnesfiler (t.ex. `debugging.md`, `api-conventions.md`) för detaljer och länka från MEMORY.md
- Spara bara verifierade mönster — inte spekulationer eller sessionspecifik kontext

## Iterativ förbättring

Om samma misstag upprepas, föreslå en ny regel för CLAUDE.md eller en hook som förhindrar det.
