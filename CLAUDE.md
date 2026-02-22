# CLAUDE.md

## Kritiska regler (LÄS FÖRST)

- **NEVER** gissa på orsaker utan bevis från kodbasen — läs alltid koden först.
- **NEVER** säg att något är "klart" utan att ALLA tester passerar och koden verifierats.
- **NEVER** kopiera hela filer — använd Edit-verktyget för kirurgiska ändringar.
- **NEVER** skriv eller ändra UI-kod (HTML, CSS, JS, design, layout, utseende, färger, typografi) utan att FÖRST anropa `frontend-design`-skillen via Skill-verktyget. Detta är ett BLOCKERANDE KRAV.
- **ALWAYS** följ befintliga mönster i kodbasen — titta på liknande komponenter först.
- **ALWAYS** kör `dotnet build` och `dotnet test` efter implementation.

## Exekveringsläge

### Autonomt läge (NON-INTERACTIVE)

- Agera direkt utan att vänta på bekräftelse.
- Saknad information är inte ett hinder — gör rimliga antaganden och fortsätt.
- Fel ska hanteras och fixas självständigt.
- Frågor är tillåtna BARA vid arkitekturbeslut eller kravtolkning som inte rimligt kan antas.
- **Max 3 försök per problem** — om samma approach misslyckas 3 gånger, prova en helt annan strategi.

### Anti-stall regel

Om ingen tydlig uppgift hittas — välj den mest sannolika uppgiften och agera. Stagnation betraktas som misslyckande.

### Interview-mönstret

För större features: intervjua utvecklaren med `AskUserQuestion` innan implementation. Fråga om teknisk implementation, edge cases och tradeoffs. Skriv sedan en spec innan kodning börjar.

### Behörigheter

```text
/permissions allow bash
/permissions allow edit
/permissions allow mcp
```

## Prioritetsordning

1. **Säkerhet** — aldrig kompromissa
2. **Korrekthet** — koden ska göra rätt sak
3. **Enkelhet** — minsta möjliga komplexitet
4. **Läsbarhet** — tydlig kod framför smart kod
5. **Prestanda** — optimera bara vid behov

## Kärnprinciper (icke-förhandlingsbara)

Projektspecifika principer som ALDRIG får brytas. Lägg till vid behov:

1. [T.ex. "All dataåtkomst MÅSTE vara tenant-scopad" (ICKE-FÖRHANDLINGSBAR)]
2. [T.ex. "JWT-tokens MÅSTE lagras i sessionStorage, aldrig cookies" (ICKE-FÖRHANDLINGSBAR)]

## Projektbeskrivning

**Projektnamn**: [Namn]
**Syfte**: [En kort beskrivning av vad systemet gör och för vem]
**Designdokument**: [Sökväg till grafisk profil, varumärkesriktlinjer etc., om tillämpligt]

### Arkitektur

```text
[ASCII-diagram som visar systemets komponenter och hur de hänger ihop]

Exempel:
┌─────────────┐     ┌─────────────┐
│  Frontend   │────▶│   Backend   │
│  (Blazor)   │     │  (Web API)  │
└─────────────┘     └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   SQLite    │
                    └─────────────┘
```

### Obligatoriska kataloger

- `src/` — all källkod
- `tests/` — alla tester
- `legacy/` — gamla filer och kod som fasas ut
- `artifacts/` — build-output, rapporter och genererade filer
- `temp/` — temporära filer (ska ligga i `.gitignore`)

### Typiska projektprofiler

Projekten är ofta stora fullstack-applikationer med frontend, backend, databaser och autentisering. .NET backend + SQLite, ofta kopplad till kurs-/projektwebb.

**Learnways-integration**: Backend kopplas ofta till webbplats byggd av [Learnways](https://learnways.com) (partner) i ren HTML, CSS och JavaScript.

### Nyckelmönster

Dokumentera projektets centrala mönster så att Claude skriver idiomatisk kod:

- **Autentisering**: [T.ex. JWT i sessionStorage, Identity + cookies, OAuth]
- **Databasaccess**: [T.ex. EF Core repositories, `$wpdb->prepare()`, direkt SQL]
- **API-mönster**: [T.ex. Minimal API med `Result<T>`, MVC controllers]
- **Felhantering**: [T.ex. `Result<T, Exception>`, ProblemDetails]
- **State management**: [T.ex. Blazor cascading parameters, Redux]

## Språk

- Kommunicera alltid på **svenska** i konversationer och commit-meddelanden.
- Kod, variabelnamn och tekniska termer skrivs på **engelska**.
- Kommentarer i kod skrivs på **engelska**.

## Teknikstack

- **.NET** (Blazor, MVC, Razor Pages, Web API) — senaste stabila versionen
- **SQLite** som databas (om inget annat anges)
- **WordPress** (PHP, teman, plugins)
- **HTML, CSS, JavaScript, jQuery** (frontend)

## Lokal utvecklingsmiljö

**Startkommando:**

```bash
# [Projektspecifikt startkommando, t.ex. dotnet run --project src/AppHost]
```

**URL:er:**

- Frontend: [URL, t.ex. https://localhost:5001]
- Admin: [URL, om tillämpligt]

**Kända workarounds:**

- [Eventuella problem med IPv6, minne, portar, certifikat etc.]

## CI/CD och deployment

Alla projekt driftas på Docker Swarm-klustret live4.se (Azure). Fullständig CI/CD-dokumentation: @.claude/docs/deployment.md

Kort sammanfattning:

- **Kluster**: 1 manager + 3 workers, privat registry `10.2.0.4:5000`
- **Pipeline**: GitHub Actions → Docker build → SCP till manager → `docker stack deploy`
- **Storage**: NFS på `/mnt/nfs/[projektnamn]/`
- **Deploy-trigger**: `workflow_dispatch` med `confirm_deploy: "deploy"`

## Arbetsflöde

### Komplexitetsbedömning

- **Trivial** (en fil, uppenbar fix) → exekvera direkt
- **Medel** (2–5 filer, tydligt scope) → kort planering, sedan exekvera
- **Komplex** (arkitekturpåverkan, oklara krav) → fullständig utforskning och plan först

### Planera → Implementera → Verifiera

1. **Utforska** — läs befintlig kod, förstå mönster och beroenden.
2. **Planera** — vid medel/komplex: skriv plan innan implementation.
3. **Implementera** — skriv kod enligt planen. Följ befintliga mönster.
4. **Verifiera** — kör alla tester, typechecka, bekräfta att allt fungerar.

### Thinking triggers

- `think` → ~4 000 tokens tankebudget
- `think hard` → ~10 000 tokens
- `ultrathink` → ~32 000 tokens (rekommenderas för arkitekturbeslut och svår felsökning)

## Verifiering och grundning

> Att ge Claude sätt att verifiera sitt eget arbete är den enskilt viktigaste åtgärden för kvalitet. — Anthropic Best Practices

- **IMPORTANT:** Läs ALLTID relevanta filer INNAN du svarar om kodbasen. Gissa ALDRIG.
- Kör tester efter varje implementation.
- Kör enskilda tester framför hela sviten för snabbare feedback.

### Definition av "implementerat"

Säg **aldrig** att något är "implementerat" eller "klart" förrän:

1. Alla **enhetstester** passerar (`dotnet test`).
2. Alla **E2E-tester i Playwright** passerar (`dotnet test --filter "Category=UI"`).
3. För webbprojekt: **visuellt verifierad** i webbläsaren.
4. Koden bedöms fungera till **100%**.

Om tester inte kan köras (saknad infrastruktur), informera tydligt om detta.

## Kontexthantering

- Vid kompaktering: bevara ALLTID modifierade filer, felmeddelanden ordagrant, felsökningssteg och testkommandon.
- Använd subagenter för utforskning och research — håll huvudkontexten ren.
- Använd `/clear` mellan orelaterade uppgifter.

### Sessions-hantering

- `claude --continue` — återuppta senaste sessionen
- `claude --resume` — välj bland tidigare sessioner
- `/rewind` eller `Esc+Esc` — gå tillbaka till tidigare checkpoint
- `/rename` — ge sessionen beskrivande namn för enkel återfinnbarhet

## Interaktionsregler

### Spec-driven arbetsmodell

Om projektet använder ett spec-kit eller liknande:

- Prioritera spec-kitets arbetsmodell i första hand.
- Alla implementationer utgår från specifikationen.
- Avvikelser kräver explicit godkännande.
- Standarduppgift: [T.ex. "Hitta högst numrerade ofullständiga spec och implementera den."]

### Frontend design skill (BLOCKERANDE KRAV)

> **CRITICAL — BLOCKING REQUIREMENT:** Innan du skriver EN ENDA RAD UI-kod (HTML, CSS, JS, layout, design, styling) MÅSTE du anropa `frontend-design`-skillen via Skill-verktyget. Det spelar ingen roll hur liten ändringen är — en knapp, en färg, en rubrik, en margin, en font-storlek — skillen ska ALLTID anropas FÖRST.

**Triggerord som kräver frontend-design skill:**

- Design, utseende, layout, styling, CSS, färg, font, typografi
- Knapp, formulär, navbar, footer, header, sidebar, modal, kort/card
- Responsivt, mobil, dark mode, tema, animation
- "Snyggare", "finare", "modernare", "proffsigare", "bättre utseende"

**Korrekt ordning:**

1. Användaren frågar om något UI-relaterat
2. **FÖRST:** Anropa `Skill`-verktyget med `skill: "frontend-design"`
3. **SEDAN:** Följ instruktionerna från skillen för implementation

### Hooks (deterministiska regler)

Överväg Claude Code hooks (`.claude/settings.json`) för regler som MÅSTE efterlevas utan undantag. Till skillnad från CLAUDE.md-instruktioner som är rådgivande är hooks deterministiska och garanterade. Exempel:

- Post-edit hook: kör linter efter varje filändring
- Pre-commit hook: kör `dotnet build` innan commit
- Blockerings-hook: förhindra skrivning till skyddade kataloger

### Subagenter

Skapa dedikerade subagenter i `.claude/agents/` för isolerade uppgifter som inte ska fylla huvudkontexten. Subagenter körs i egna kontextfönster och rapporterar tillbaka sammanfattningar.

### Iterativ förbättring

Om samma misstag upprepas, föreslå en ny regel för CLAUDE.md eller en hook som förhindrar det.

## Säkerhet

- Parametriserade queries alltid — aldrig string concatenation för SQL.
- Sanera all användarinput (XSS-skydd).
- HTTPS, CSRF-skydd, CORS-konfiguration.
- Hemligheter i `appsettings.json` (lokalt) / miljövariabler (produktion) — **aldrig i kod**.
- Committa inte `.env`, `appsettings.Development.json` eller liknande.
- Alla API-endpoints kräver autentisering om inget annat anges.

## Förbjudna implementationer

- **String concatenation i SQL** — använd parametriserade queries.
- **Hemligheter i kod** — inga API-nycklar, lösenord eller tokens.
- **`var` i JavaScript** — använd `const`/`let`.
- **Business-logik i UI** — håll UI tunt, logik i services.
- **`#region` i C#** — aldrig.
- **Modifiering av framework/CMS-core** — använd extensions, hooks, child themes eller överlagring.
- **Inline styles** — använd CSS-filer eller CSS-klasser, aldrig `style="..."` i HTML.
- **`eval()` eller `extract()`** — aldrig, varken i PHP eller JavaScript.
- **UI-kod utan `frontend-design` skill** — anropa ALLTID skillen först.

## Kommandon

```bash
dotnet build                           # Bygg projektet
dotnet test                            # Kör enhetstester
dotnet run --project src/<ProjektNamn> # Kör applikationen
dotnet test --filter "Category=UI"     # Playwright E2E-tester
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"  # Enskilt test
```

## Filstruktur

- Separera concerns: Models, Views, Controllers, Services.
- Delade komponenter i `Shared/` eller `Components/`.
- I .NET-projekt: `wwwroot/` för webbspecifika filer.

## Databas (SQLite)

- Entity Framework Core med SQLite-provider.
- Code-first med migrations.
- Inkludera inte `.db`-filen i git.
- Seed-data via migrations eller separat seed-metod.

## Principer

- **YAGNI** — bygg bara det som behövs nu. Tre liknande rader > prematur abstraktion.
- **Fail fast** — tydliga felmeddelanden med kontext. Aldrig tysta fallbacks.
- **DX** — kod ska vara läsbar utan kommentarer. Bra namngivning räcker oftast.

## Detaljerade referensfiler

Följande filer innehåller detaljerad information och laddas vid behov:

- Kodstil och konventioner: @.claude/docs/conventions.md
- Git-konventioner: @.claude/docs/git.md
- Skills-installation: @.claude/docs/skills.md
- Testkonventioner: @.claude/docs/testing.md
- CI/CD och deployment: @.claude/docs/deployment.md

## Övrigt

- Redigera befintliga filer framför att skapa nya.
- Håll denna fil fokuserad — om en instruktion kan tas bort utan att Claude gör fel, ta bort den.
