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

## Hooks (deterministiska regler)

Överväg Claude Code hooks (`.claude/settings.json`) för regler som MÅSTE efterlevas utan undantag. Till skillnad från CLAUDE.md-instruktioner som är rådgivande är hooks deterministiska och garanterade.

**Hooktyper:**

| Hook-event | När det utlöses |
|---|---|
| `PreToolUse` | Innan ett verktygsanrop — kan blockera |
| `PostToolUse` | Efter ett verktygsanrop lyckas |
| `Stop` | När Claude slutar svara |
| `SessionStart` | När session startar eller återvänder |

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

## Subagenter

Skapa dedikerade subagenter i `.claude/agents/` för isolerade uppgifter som inte ska fylla huvudkontexten. Subagenter körs i egna kontextfönster och rapporterar tillbaka sammanfattningar.

**Konfigurationsformat (YAML-frontmatter i `.claude/agents/`):**

```markdown
---
name: security-reviewer
description: Reviews code for security vulnerabilities
tools: Read, Grep, Glob, Bash
model: opus
memory: project
---
Du är en senior säkerhetsingenjör. Granska koden för...
```

**Nyckelparametrar:**

- `tools` — vilka verktyg subagenten har tillgång till
- `model` — opus, sonnet eller haiku
- `memory` — user, project eller local (bestående minne)
- `isolation: worktree` — kör i temporär git worktree

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

## Iterativ förbättring

Om samma misstag upprepas, föreslå en ny regel för CLAUDE.md eller en hook som förhindrar det.
