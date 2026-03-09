# Sync-prompt for other projects

Copy everything between the `---` markers below and paste it into a Claude Code session
in the project you want to update.

---

## Prompt: Uppdatera projektet med senaste Claude Code-konfigurationen

Mallrepot för Claude Code-konfiguration finns i `/Users/jool/repos/Claude` och innehåller den senaste versionen av regler, hooks, agents, skills och referensdokumentation. Ditt jobb: uppdatera DETTA projekts Claude Code-setup så att det matchar mallrepots struktur och best practices.

### Vad du ska göra

1. **Läs mallrepots filer** — Läs följande filer från `/Users/jool/repos/Claude`:
   - `CLAUDE.md` (huvudkonfiguration)
   - `.claude/settings.json` (hooks och permissions)
   - `.claude/rules/*.md` (path-scoped regler)
   - `.claude/agents/*.md` (subagenter)
   - `.claude/skills/*/SKILL.md` (projektskills)
   - `.claude/docs/*.md` (referensdokumentation)

2. **Läs detta projekts filer** — Läs befintlig `CLAUDE.md`, `.claude/settings.json` och alla filer under `.claude/` i DETTA projekt.

3. **Analysera och uppdatera** — För varje fil:
   - Om filen INTE finns i detta projekt: kopiera den från mallen
   - Om filen finns: jämför och uppdatera till mallens version, MEN bevara allt som är markerat med `# PROJECT-SPECIFIC` eller som är unikt för detta projekt
   - För `CLAUDE.md`: uppdatera strukturen och generiska sektioner, bevara projektspecifik information (projektbeskrivning, teknikstack, kommandon, etc.)
   - For `.claude/settings.json`: MERGE hooks och permissions (union av båda), bevara projektspecifika hooks

4. **Ta bort irrelevant** — Om detta projekt inte använder en viss teknik (t.ex. WordPress, .NET), ta INTE med den teknikens regler/agents.

5. **Rapportera** — Skriv en sammanfattning av vad som uppdaterades:
   ```
   Synkad från mallrepo (YYYY-MM-DD):
   - [SKAPAD/UPPDATERAD/ÖVERHOPPAD] filnamn — anledning

   Projektspecifikt bevarat:
   - filnamn — vad som bevarades

   Manuell granskning behövs:
   - filnamn — varför
   ```

### Regler

- Skriv kommunikation på svenska, kod på engelska
- Ändra ALDRIG projektets kärnlogik eller applikationskod
- Bevara ALLTID projektspecifika anpassningar
- Om osäker: rapportera och fråga istället för att ändra
- Kör `dotnet build` efteråt om projektet är .NET
- Committa INTE automatiskt — låt utvecklaren granska först

---
