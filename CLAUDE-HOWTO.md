# Kom igång med Claude Code-konfigurationen

Steg-för-steg-guide för att använda detta mallrepo i ett nytt eller befintligt projekt.

---

## Nytt projekt

### 1. Kopiera alla konfigurationsfiler

Kör följande från ditt nya projekts rotkatalog:

```bash
# Sökväg till mallrepot
MALL=/Users/jool/repos/Claude

# Skapa katalogstrukturen
mkdir -p .claude/docs .claude/agents .claude/rules

# Kopiera huvudfilen
cp "$MALL/CLAUDE.md" ./CLAUDE.md

# Kopiera referensfiler
cp "$MALL/.claude/docs/conventions.md"      .claude/docs/
cp "$MALL/.claude/docs/deployment.md"       .claude/docs/
cp "$MALL/.claude/docs/git.md"              .claude/docs/
cp "$MALL/.claude/docs/project-template.md" .claude/docs/
cp "$MALL/.claude/docs/security.md"         .claude/docs/
cp "$MALL/.claude/docs/skills.md"           .claude/docs/
cp "$MALL/.claude/docs/testing.md"          .claude/docs/
cp "$MALL/.claude/docs/workflows.md"        .claude/docs/
cp "$MALL/.claude/docs/agents-templates.md" .claude/docs/

# Kopiera hooks
cp "$MALL/.claude/settings.json" .claude/settings.json

# Kopiera path-scoped regler (välj de som är relevanta)
cp "$MALL/.claude/rules/security.md"  .claude/rules/    # Alltid
cp "$MALL/.claude/rules/dotnet.md"    .claude/rules/    # .NET-projekt
cp "$MALL/.claude/rules/frontend.md"  .claude/rules/    # Frontend
cp "$MALL/.claude/rules/wordpress.md" .claude/rules/    # WordPress (ta bort om ej aktuellt)

# Kopiera agenter (välj de som är relevanta)
cp "$MALL/.claude/agents/dotnet-reviewer.md"  .claude/agents/  # .NET
cp "$MALL/.claude/agents/security-scanner.md" .claude/agents/  # Alltid
cp "$MALL/.claude/agents/test-runner.md"      .claude/agents/  # Alltid
cp "$MALL/.claude/agents/db-agent.md"         .claude/agents/  # EF Core + SQLite
```

### 2. Fyll i projektspecifik information

Öppna `CLAUDE.md` och uppdatera **Projektbeskrivning**-sektionen:

```markdown
## Projektbeskrivning

Detta är ett **[PROJEKTNAMN]** — [kort beskrivning av vad systemet gör och för vem].

> **Vid projektstart:** Fyll i kärnprinciper, arkitektur och dev-miljö i `.claude/docs/project-template.md`
```

### 3. Fyll i projektmallen

Öppna `.claude/docs/project-template.md` och fyll i ALLA sektioner markerade med `[FYLL I]`:

- **Kärnprinciper** — regler som ALDRIG får brytas (t.ex. "All data MÅSTE vara tenant-scopad")
- **Projektnamn och syfte** — en rad som orienterar Claude
- **Arkitektur** — ASCII-diagram över systemets komponenter
- **Nyckelmönster** — autentisering, databasaccess, API-mönster, felhantering, state management, domäntermer
- **Startkommando** — t.ex. `dotnet run --project src/AppHost`
- **URL:er** — t.ex. `https://localhost:5001`
- **Kända workarounds** — IPv6-problem, certifikat, etc.

### 4. Ta bort det som inte är relevant

- Inte WordPress? → Ta bort `.claude/rules/wordpress.md`
- Inte .NET? → Ta bort `.claude/rules/dotnet.md` och `.claude/agents/dotnet-reviewer.md`
- Inte EF Core/SQLite? → Ta bort `.claude/agents/db-agent.md`
- Annan deploy-miljö? → Uppdatera `.claude/docs/deployment.md` med era egna uppgifter

### 5. Committa

```bash
git add CLAUDE.md .claude/
git commit -m "feat: Lägg till Claude Code-konfiguration"
```

---

## Befintligt projekt

### Alternativ A: Kopiera in allt (rekommenderat)

Samma steg som för nytt projekt ovan. Om projektet redan har en `CLAUDE.md`, gör en backup först:

```bash
cp CLAUDE.md CLAUDE.md.backup
```

Kopiera sedan in mallfilerna och slå ihop det befintliga innehållet med det nya.

### Alternativ B: Uppdatera stegvis

Om du bara vill lägga till det som saknas:

```bash
MALL=/Users/jool/repos/Claude

# 1. Hooks (om .claude/settings.json saknas)
cp "$MALL/.claude/settings.json" .claude/settings.json

# 2. Path-scoped regler (om .claude/rules/ saknas)
mkdir -p .claude/rules
cp "$MALL/.claude/rules/"*.md .claude/rules/

# 3. Agenter (om .claude/agents/ saknas)
mkdir -p .claude/agents
cp "$MALL/.claude/agents/"*.md .claude/agents/

# 4. Referensfiler (om .claude/docs/ saknas)
mkdir -p .claude/docs
cp "$MALL/.claude/docs/"*.md .claude/docs/
```

Öppna sedan `CLAUDE.md` och lägg till de sektioner som saknas (kopiera från mallen).

### Alternativ C: Be Claude göra det

Starta en Claude Code-session i projektet och skriv:

```
Uppdatera eller skapa claude.md med mallfilerna från /Users/jool/repos/Claude.
Kopiera in hooks, rules, agents och docs.
Fyll i projektnamn: [DITT PROJEKTNAMN]
Fyll i syfte: [VAD PROJEKTET GÖR]
Ta bort det som inte är relevant för detta projekt.
```

---

## Checklista efter installation

- [ ] `CLAUDE.md` — Projektbeskrivning ifylld
- [ ] `.claude/docs/project-template.md` — Alla `[FYLL I]`-platshållare ifyllda
- [ ] `.claude/settings.json` — Hooks konfigurerade
- [ ] `.claude/rules/` — Bara relevanta regler (ta bort oanvända)
- [ ] `.claude/agents/` — Bara relevanta agenter
- [ ] `.claude/docs/deployment.md` — Uppdaterad med projektets deploy-info
- [ ] `.gitignore` — Innehåller `CLAUDE.local.md` och `temp/`
- [ ] Skills installerade — Kör installationsscriptet från `.claude/docs/skills.md`

---

## Filöversikt

```
ditt-projekt/
├── CLAUDE.md                          ← Huvudfil (155 rader, laddas alltid)
├── CLAUDE.local.md                    ← Personligt, gitignored (skapa vid behov)
├── .claude/
│   ├── settings.json                  ← Hooks (deterministiska regler)
│   ├── docs/                          ← Referensfiler (laddas vid behov)
│   │   ├── project-template.md        ← Projektspecifik info (FYLL I!)
│   │   ├── conventions.md             ← Kodstil
│   │   ├── security.md                ← Säkerhetsregler
│   │   ├── git.md                     ← Git-konventioner
│   │   ├── testing.md                 ← Testkonventioner
│   │   ├── deployment.md              ← CI/CD och deploy
│   │   ├── workflows.md               ← Hooks, subagenter, plugins
│   │   ├── agents-templates.md        ← Agentmallar (referens)
│   │   └── skills.md                  ← Skills och plugins
│   ├── rules/                         ← Auto-laddas, path-scoped
│   │   ├── security.md                ← *.cs, *.cshtml, *.razor
│   │   ├── dotnet.md                  ← *.cs, *.csproj
│   │   ├── frontend.md                ← *.html, *.css, *.js, *.tsx
│   │   └── wordpress.md               ← *.php, wp-content/**
│   └── agents/                        ← Subagenter
│       ├── dotnet-reviewer.md         ← Kodgranskning (sonnet)
│       ├── security-scanner.md        ← Säkerhetsskanning (sonnet)
│       ├── test-runner.md             ← Testkörning (haiku)
│       └── db-agent.md                ← Databasoperationer (inherit)
```

---

## Vanliga frågor

**Måste jag fylla i alla platshållare?**
Ja. Repo-specifik anpassning ger 2x bättre resultat enligt Arize ML-forskning. Ju mer konkret information Claude har om ditt projekt, desto bättre kod produceras.

**Kan jag ta bort filer jag inte behöver?**
Absolut. Ta bort allt som inte är relevant. En WordPress-regel i ett rent .NET-projekt tar bara plats utan att bidra.

**Ska .claude/settings.json committas?**
Ja, den delas med teamet. Personliga inställningar läggs i `.claude/settings.local.json` (gitignored).

**Vad är skillnaden mellan rules/ och docs/?**
- `rules/` auto-laddas varje session med hög prioritet, filtrerat på vilka filer du arbetar med
- `docs/` laddas bara när Claude bedömer att de behövs (eller du refererar dem med `@`)
