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

## Humanizer skill — detaljer

**CRITICAL — BLOCKERANDE KRAV:** 100% av all genererad text som riktas till människor MÅSTE köras genom `humanizer`-skillen innan leverans.

**Gäller för:**

- Commit-meddelanden och PR-beskrivningar
- Dokumentation, README-filer, CHANGELOG
- Mejl, artiklar, blogginlägg
- Kommentarer på issues/PRs
- All löpande text som levereras till användaren

**Gäller INTE för:**

- Kod (variabler, funktioner, klasser)
- Tekniska loggar och felmeddelanden
- JSON, YAML, konfigurationsfiler
- Inline-kommentarer i kod (engelska, tekniska)

**Korrekt ordning:**

1. Generera texten
2. **FÖRST:** Anropa `Skill`-verktyget med `skill: "humanizer"`
3. **SEDAN:** Leverera den humaniserade texten

## Plugins

Plugins buntar skills, agents, hooks, MCP-servrar och LSP-servrar i ett distribuerbart paket. Installeras med `/plugin install`.

**Skillnad mot skills:**

- **Skill** = en SKILL.md-fil med instruktioner (körs i huvudkontexten)
- **Plugin** = ett paket som kan innehålla skills + agents + hooks + MCP + LSP

### LSP-plugins och installation

Se `.claude/docs/skills.md` för LSP-plugins (C#, TypeScript, PHP) och installationskommandon.

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

### Hook-events (16 st)

| Hook-event | När det utlöses |
| --- | --- |
| `SessionStart` | Session startar eller återupptas |
| `SessionEnd` | Session avslutas. Matcher: `clear`, `logout`, `prompt_input_exit`, `other` |
| `UserPromptSubmit` | Användaren skickar en prompt — kan blockera eller injicera kontext |
| `PreToolUse` | Innan ett verktygsanrop — kan blockera eller modifiera input |
| `PermissionRequest` | Behörighetsdialog visas — kan auto-godkänna eller neka |
| `PostToolUse` | Efter ett lyckat verktygsanrop |
| `PostToolUseFailure` | Efter ett misslyckat verktygsanrop — kan ge korrigerande feedback |
| `Notification` | Notifikationer (`permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`) |
| `SubagentStart` | En subagent startas |
| `SubagentStop` | En subagent avslutas |
| `Stop` | Claude slutar svara — kan tvinga fortsättning |
| `TeammateIdle` | Agent team-medlem ska gå idle — kan tvinga fortsättning |
| `TaskCompleted` | En uppgift markeras som klar — kan blockera om kvalitetsvillkor inte uppfylls |
| `PreCompact` | Innan kontextkomprimering — bra för transkript-backup |
| `ConfigChange` | Konfigurationsfil ändras under session — kan blockera ändringen |
| `WorktreeCreate` / `WorktreeRemove` | Worktree skapas eller tas bort |

### Fyra typer av hooks

- `command` — kör shell-kommando. Tar emot JSON via stdin, returnerar JSON via stdout. Stöder `"async": true` för bakgrundskörning
- `http` — skickar JSON som HTTP POST till en URL. Konfigureras med `url`, `headers`, `allowedEnvVars`
- `prompt` — envägs-evaluering med Claude (Haiku), returnerar `{ "ok": true/false, "reason": "..." }`
- `agent` — flervägs-verifiering med verktygsåtkomst (Read, Grep, Glob), upp till 50 varv

### Blockering och kontroll

Hooks blockerar via:

- **Command:** exit code `2` = blockera (OBS: `exit 1` blockerar INTE, det är bara ett fel)
- **Command:** JSON-output med `"permissionDecision": "deny"` = blockera
- **Prompt/Agent:** `{ "ok": false, "reason": "..." }` = blockera
- **Permissions.deny** i settings.json = deterministisk blockering utan hook (rekommenderat för fasta regler)

### Async hooks (bakgrundskörning)

Sätt `"async": true` på command-hooks för att köra dem i bakgrunden utan att blockera Claude. Resultatet levereras på nästa konversationstur via `systemMessage`.

```json
{
  "matcher": "Edit|Write",
  "hooks": [{
    "type": "command",
    "command": "dotnet build 2>&1 | tail -5",
    "async": true,
    "timeout": 60
  }]
}
```

**Begränsningar:** Async hooks kan inte blockera, bara `type: "command"` stöds, och output levereras först vid nästa tur.

### JSON-output från hooks

| Fält | Beskrivning |
| --- | --- |
| `systemMessage` | Varningsmeddelande till användaren |
| `additionalContext` | Extra kontext för Claude |
| `continue` | `false` = stoppa Claude helt |
| `stopReason` | Meddelande vid `continue: false` |
| `suppressOutput` | Dölj stdout från verbose mode |
| `updatedInput` | Modifiera verktygets input (PreToolUse, PermissionRequest) |
| `updatedMCPToolOutput` | Ersätt MCP-verktygets output (PostToolUse) |

### Miljövariabler i hooks

| Variabel | Beskrivning |
| --- | --- |
| `$CLAUDE_PROJECT_DIR` | Projektets rotkatalog — använd i stället för relativa sökvägar |
| `$CLAUDE_ENV_FILE` | Sökväg där SessionStart-hooks kan skriva `export`-satser |
| `$CLAUDE_CODE_REMOTE` | `"true"` i fjärr-/webb-miljöer |
| `${CLAUDE_PLUGIN_ROOT}` | Pluginens rotkatalog |

### Vanliga automatiseringar

- Post-edit hook: kör linter efter varje filändring
- Pre-commit hook: kör `dotnet build` innan commit
- Blockerings-hook: `permissions.deny` i settings.json (föredra detta framför hooks)
- Stop-hook (agent): verifiera att tester passerar innan Claude stannar
- Async post-edit: kör tester i bakgrunden medan Claude fortsätter arbeta

### Exempel — Stop-hook för testverifiering

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Kontrollera att dotnet build och dotnet test passerar.",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### Exempel — Återinför kontext efter kompaktering

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"systemMessage\": \"Påminnelse: använd dotnet, kör dotnet test innan commit.\"}'"
          }
        ]
      }
    ]
  }
}
```

### Exempel — HTTP-hook för Slack-notifikation

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "http",
            "url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL",
            "headers": { "Content-Type": "application/json" }
          }
        ]
      }
    ]
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
tools: Read, Grep, Glob       # Valfritt. Allowlist för verktyg (Agent(type) begränsar subagenter)
disallowedTools: Write, Edit  # Valfritt. Denylist
model: sonnet                 # Valfritt. sonnet|opus|haiku (default: inherit)
permissionMode: default       # Valfritt. default|acceptEdits|dontAsk|plan|bypassPermissions
maxTurns: 20                  # Valfritt. Max antal agentvarv
memory: project               # Valfritt. user|project|local (bestående minne)
isolation: worktree           # Valfritt. Kör i isolerad git worktree
background: false             # Valfritt. true = kör i bakgrunden
skills:                       # Valfritt. Skills att ladda in i kontexten
  - api-conventions
mcpServers:                   # Valfritt. MCP-servrar tillgängliga för agenten
  - server-name
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
| `permissionMode` | `acceptEdits` auto-godkänner filändringar, `plan` = bara läsning, `bypassPermissions` = hoppa över alla |
| `memory` | `user` = alla projekt, `project` = delbart via git, `local` = bara du |
| `isolation` | `worktree` = isolerad git-kopia, städas automatiskt |
| `background` | Kör medan du fortsätter arbeta. MCP-verktyg ej tillgängliga |
| `skills` | Hela skill-innehållet injiceras vid start. Ärvs INTE från föräldern |
| `mcpServers` | MCP-servrar tillgängliga för agenten. Servernamn eller inline-definition |

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
