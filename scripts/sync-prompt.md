# Sync-prompt for other projects

Copy everything between the `---` markers below and paste it into a Claude Code session
in the project you want to update.

---

## Uppdatera projektet med senaste Claude Code-konfigurationen

Mallrepot finns i `/Users/jool/repos/Claude`. Ditt jobb: synka DETTA projekts Claude Code-setup mot mallrepots senaste version.

### Steg 1: Läs mallrepot

Läs följande filer från `/Users/jool/repos/Claude` (alla är viktiga — hoppa inte över några):

**Konfiguration:**
- `CLAUDE.md` — huvudkonfiguration med kritiska regler och arbetsflöde
- `.claude/settings.json` — hooks, permissions, hook-typer (command, prompt, http, agent)

**Rules (auto-laddas, path-scoped via YAML-frontmatter):**
- `.claude/rules/dotnet.md` — .NET-kodregler (paths: `**/*.cs`, `**/*.csproj`)
- `.claude/rules/frontend.md` — frontend-regler
- `.claude/rules/security.md` — säkerhetsregler för C#
- `.claude/rules/specs.md` — spec/task-regler med destruktiva testerkrav (paths: `**/spec*.md`, `**/tasks*.md`, etc.)
- `.claude/rules/wordpress.md` — WordPress-regler

**Docs (laddas vid behov, refereras från CLAUDE.md):**
- `.claude/docs/testing.md` — testkonventioner, destruktiva browsertester (6+1 attackkategorier)
- `.claude/docs/spec-testing-checklist.md` — obligatorisk checklista för destruktiva tester i specs
- `.claude/docs/conventions.md` — kodstil och namngivning
- `.claude/docs/security.md` — säkerhetsreferens
- `.claude/docs/git.md` — commit/branch/PR-konventioner
- `.claude/docs/workflows.md` — hooks (25 events), skills, subagenter, plugins, agent teams
- `.claude/docs/skills.md` — SKILL.md-format, frontmatter-fält, rekommenderade skills
- `.claude/docs/agents-templates.md` — kopieringsbara agentmallar
- `.claude/docs/deployment.md` — Docker Swarm, CI/CD
- `.claude/docs/project-template.md` — mall för projektstart

**Agents (subagenter med YAML-frontmatter):**
- `.claude/agents/dotnet-reviewer.md` — kodgranskning (isolation: worktree)
- `.claude/agents/security-scanner.md` — säkerhetsskanning (isolation: worktree)
- `.claude/agents/test-runner.md` — testkörning (background: true)
- `.claude/agents/db-agent.md` — EF Core/SQLite

**Skills (SKILL.md med frontmatter):**
- `.claude/skills/code-review/SKILL.md`
- `.claude/skills/explore-codebase/SKILL.md`
- `.claude/skills/deploy-checklist/SKILL.md`

### Steg 2: Läs detta projekts filer

Läs befintlig `CLAUDE.md`, `.claude/settings.json` och alla filer under `.claude/` i DETTA projekt. Notera vad som är projektspecifikt.

### Steg 3: Analysera och uppdatera

För varje fil i mallen:

| Situation | Åtgärd |
|-----------|--------|
| Filen finns INTE i detta projekt | Kopiera från mallen |
| Filen finns och matchar mallen | Överhoppa |
| Filen finns men är äldre | Uppdatera till mallens version, bevara `# PROJECT-SPECIFIC`-block |
| Filen finns med projektspecifikt innehåll | Merge — mallens struktur + projektets anpassningar |

**CLAUDE.md-merge:**
- Uppdatera: kritiska regler, exekveringsläge, arbetsflöde, verifiering, kontexthantering, referensfiler
- Bevara: projektbeskrivning, teknikstack, kommandon, projektspecifika principer

**settings.json-merge:**
- UNION av hooks — lägg till mallens hooks utan att ta bort projektets egna
- UNION av permissions.deny — sammanfoga båda listorna
- Bevara projektspecifika hooks och permissions
- OBS: mallen använder nya hook-typer som kanske inte finns i projektet:
  - `type: "prompt"` — LLM-evaluering (för spec-validering)
  - `type: "agent"` — flervägs-verifiering med verktygsåtkomst
  - `type: "http"` — webhook-integration
  - `if`-fältet (v2.1.85) — filtrering med permission rule-syntax

### Steg 4: Verifiera spec-testning (KRITISKT)

Dessa tre komponenter arbetar tillsammans för att säkerställa att destruktiva browsertester inkluderas redan vid spec-skrivning — inte som eftertanke:

1. **`.claude/rules/specs.md`** — path-scoped rule som triggar på spec/task/plan-filer. Kräver att testing.md och checklistan läses INNAN specen skrivs.

2. **`.claude/docs/spec-testing-checklist.md`** — konkret mall med task-struktur per attackkategori. Definierar minimikrav per feature-typ (8-15 tester). Mål: 99% E2E-täckning.

3. **PostToolUse prompt-hook i settings.json** — triggar vid Edit/Write på spec-filer och blockerar om destruktiva tester saknas. Kontrollera att denna hook finns:
   ```json
   {
     "matcher": "Edit|Write",
     "hooks": [{
       "type": "prompt",
       "prompt": "A file was just written/edited. Check: if the file path contains spec, tasks, plan, or feature AND is a .md file AND involves UI features, verify it includes destructive browser test scenarios...",
       "statusMessage": "Validating spec completeness..."
     }]
   }
   ```

Om NÅGON av dessa tre saknas — kopiera från mallen.

### Steg 5: Ta bort irrelevant

- Projektet använder INTE WordPress? → ta bort `.claude/rules/wordpress.md`
- Projektet använder INTE .NET? → ta bort `.claude/rules/dotnet.md`, `.claude/rules/security.md`, `.claude/agents/dotnet-reviewer.md`, `.claude/agents/db-agent.md`
- Projektet har INTE UI? → ta bort `.claude/rules/specs.md`, `.claude/docs/spec-testing-checklist.md`, spec-hooken
- Behåll ALLTID: `testing.md`, `conventions.md`, `workflows.md`, `skills.md`, `git.md`

### Steg 6: Verifiera

Efter synkronisering:
- Kör `dotnet build` om projektet är .NET
- Kontrollera att `settings.json` är giltig JSON (`python3 -m json.tool .claude/settings.json`)
- Kontrollera att CLAUDE.md inte överstiger ~200 rader (Anthropics rekommendation)
- Kontrollera att referensfil-sektionen i CLAUDE.md pekar på filer som faktiskt finns

### Steg 7: Rapportera

Skriv en sammanfattning:

```
Synkad från mallrepo (YYYY-MM-DD):
- [SKAPAD] filnamn — anledning
- [UPPDATERAD] filnamn — vad som ändrades
- [ÖVERHOPPAD] filnamn — varför (redan aktuell / ej relevant)
- [BORTTAGEN] filnamn — ej relevant för projektets teknikstack

Projektspecifikt bevarat:
- filnamn — vad som bevarades

Manuell granskning rekommenderas:
- filnamn — varför
```

### Regler

- Kommunicera på svenska med korrekta **å, ä, ö** — använd ALDRIG a/o som ersättning
- Kod skrivs på engelska
- Ändra ALDRIG projektets kärnlogik eller applikationskod
- Bevara ALLTID projektspecifika anpassningar (markerade med `# PROJECT-SPECIFIC` eller tydligt unika för projektet)
- Om osäker: rapportera och fråga istället för att ändra
- Committa INTE automatiskt — låt utvecklaren granska först

Sedan kontrollerar du claude.md så att den inte överstiger 200 rader annars bryt ut avsnitt och lägg i separat fil/filer.

---
