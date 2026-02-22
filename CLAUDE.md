# CLAUDE.md

## Kritiska regler (LÄS FÖRST)

- **NEVER** gissa på orsaker utan bevis från kodbasen — läs alltid koden först.
- **NEVER** säg att något är "klart" utan att ALLA tester (enhet + E2E/Playwright) passerar.
- **NEVER** kopiera hela filer — använd Edit-verktyget för kirurgiska ändringar.
- **ALWAYS** läs befintliga filer innan du föreslår förändringar.
- **ALWAYS** kör `dotnet build` och `dotnet test` efter implementation.
- **ALWAYS** följ befintliga mönster i kodbasen — titta på liknande komponenter först.
- **NEVER** skriv eller ändra UI-kod (HTML, CSS, JS, design, layout, utseende, färger, typografi) utan att FÖRST anropa `frontend-design`-skillen via Skill-verktyget. Detta är ett BLOCKERANDE KRAV — ingen UI-ändring utan skill-anrop.

## Exekveringsläge

### Autonomt läge (NON-INTERACTIVE)

- Agera direkt utan att vänta på bekräftelse.
- Fråga INTE om lov att skapa filer, redigera kod eller köra kommandon.
- Saknad information är inte ett hinder — gör rimliga antaganden och fortsätt.
- Fel ska hanteras och fixas självständigt.
- Fortsätt tills uppgiften är helt slutförd.
- Stagnation är värre än att agera på ofullständig information.
- Frågor är tillåtna BARA vid arkitekturbeslut eller kravtolkning som inte rimligt kan antas.
- **Max 3 försök per problem** — om samma approach misslyckas 3 gånger, stanna, omvärdera och prova en helt annan strategi. Gräv inte djupare i samma hål.

### Anti-stall regel

Om ingen tydlig uppgift hittas — välj den mest sannolika uppgiften och agera. Stagnation betraktas som misslyckande.

### Behörigheter

Följande behörigheter ska vara aktiverade:

/permissions allow bash
/permissions allow edit
/permissions allow mcp

## Prioritetsordning

Vid konflikter, följ denna rangordning:

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

Följande kataloger ska **alltid** skapas i nya projekt:

- `src/` — all källkod
- `tests/` — alla tester
- `legacy/` — gamla filer och kod som fasas ut
- `artifacts/` — build-output, rapporter och genererade filer
- `temp/` — temporära filer (ska ligga i `.gitignore`)

### Typiska projektprofiler

Projekten är ofta stora fullstack-applikationer med:

- Frontend, backend, databaser, autentisering
- Domändriven affärslogik (DDD-mönster)
- .NET backend + SQLite, kopplad till kurs-/projektwebb

**Learnways-integration**: Backend i .NET + SQLite kopplas ofta till kurs- eller projektwebb byggd av [Learnways](https://learnways.com) (partner) i ren HTML, CSS och JavaScript.

### Nyckelmönster

Dokumentera projektets centrala mönster här så att Claude skriver idiomatisk kod:

- **Autentisering**: [T.ex. JWT i sessionStorage, Identity + cookies, OAuth etc.]
- **Databasaccess**: [T.ex. EF Core repositories, $wpdb->prepare(), direkt SQL etc.]
- **API-mönster**: [T.ex. Minimal API med `Result<T>`, MVC controllers, REST-konventioner]
- **Felhantering**: [T.ex. `Result<T, Exception>`, ProblemDetails, try-catch-mönster]
- **State management**: [T.ex. Blazor cascading parameters, Redux, server-sessions]

## Språk

- Kommunicera alltid på **svenska** i konversationer och commit-meddelanden.
- Kod, variabelnamn och tekniska termer skrivs på **engelska**.
- Kommentarer i kod skrivs på **engelska**.

## Teknikstack

Primära tekniker:

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

### Klusterinfrastruktur (live4.se)

Alla projekt driftas på ett Docker Swarm-kluster på Azure:

| Nod            | Publik IP      | Intern IP | Roll    |
| -------------- | -------------- | --------- | ------- |
| live4-mgr-01   | 51.12.246.54   | 10.2.0.4  | Manager |
| live4-wkr-01   | 51.12.246.201  | 10.2.0.5  | Worker  |
| live4-wkr-02   | 51.12.247.158  | 10.2.0.6  | Worker  |
| live4-wkr-03   | 51.12.247.189  | 10.2.0.7  | Worker  |
| live4-wkr-04   | 20.240.160.138 | 10.2.0.8  | Worker  |
| live4-wkr-05   | 20.240.160.144 | 10.2.0.9  | Worker  |

**SSH-åtkomst:**

```bash
ssh -i ~/ubuntu/ubuntu ubuntu@51.12.246.54     # Manager (port 22 eller 7222)
```

**Privat Docker Registry:** `10.2.0.4:5000`
**NFS-mount:** `/mnt/nfs/` (delad storage mellan alla noder)
**Reverse proxy:** Nginx Proxy Manager (extern overlay-nätverket `nginx_npm_network`)

### Pipeline-arkitektur

```text
GitHub Actions (workflow_dispatch med bekräftelse)
         │
    Build & Test (.NET)
         │
    Docker Build (multi-stage: sdk → aspnet runtime)
         │
    Spara images som TAR → SCP till manager (port 7222)
         │
    Load images → Push till privat registry (10.2.0.4:5000)
         │
    Deploy via docker stack deploy (Swarm)
         │
    Verifiering + Mailjet email-notifikation
```

### GitHub Actions workflow

- **Workflow-fil**: `.github/workflows/deploy-[projektnamn].yml`
- **Trigger**: `workflow_dispatch` med `confirm_deploy: "deploy"` som säkerhetsmekanism
- **Runner**: `ubuntu-latest`
- **Image-tagg**: `YYYY.MM.DD-HHMM` (datetime-baserad)

### Docker

- **Dockerfiler**: Multi-stage builds med `mcr.microsoft.com/dotnet/sdk:10.0` (build) och `aspnet:10.0` (runtime)
- **Registry**: Privat på `10.2.0.4:5000`
- **Image-namngivning**: `10.2.0.4:5000/2154/[projektnamn]_[service]:TAG`
- **Exponerade portar**: Konfigureras per projekt i docker-compose-stack

### Deploy-konfiguration

- **Docker Compose/Stack**: `deploy/docker-compose-stack-[projektnamn].yml`
- **Deploy-script**: `deploy/deploy_[projektnamn].sh` (ersätter image-placeholders, deployar stack, skickar email)
- **Persistent storage**: `/mnt/nfs/[projektnamn]/` (databaser, seed-data, compose-filer)
- **Nätverk**: Projekt-internt overlay-nätverk + `nginx_npm_network` (extern, för reverse proxy)

### Miljövariabler och secrets

**GitHub Secrets (konfigureras i repo-settings):**

- `LIVE4_SSH_KEY` — SSH-nyckel för deployment till manager-noden
- `MAILJET_APIKEY` / `MAILJET_SECRET` — Email-notifikationer vid deploy

**Produktionsmiljö (i appsettings.Production.json):**

- `ASPNETCORE_ENVIRONMENT=Production`
- `ConnectionStrings` pekar på `/data/` (monterad via NFS)

### NFS-struktur per projekt

```text
/mnt/nfs/[projektnamn]/
├── app.db (+ shm, wal)          # Huvuddatabas
├── tenants/                     # Per-tenant databaser (om tillämpligt)
│   └── {tenantId}/tenant.db
├── seed-data/                   # Initial seed-data
├── temp/                        # Staging för Docker images
└── docker-compose-stack-*.yml   # Resolved compose-fil
```

### Docker Swarm-kommandon

```bash
docker stack ls                                          # Lista alla stacks
docker stack services [projektnamn]                      # Status för services
docker stack ps [projektnamn]                            # Detaljerad status
docker service logs [projektnamn]_[service]              # Visa loggar
docker service update --image [ny_image] [service]       # Uppdatera image
docker service rollback [projektnamn]_[service]          # Rollback
docker stack rm [projektnamn]                            # Ta bort stack
```

### Deployment-checklista

1. Alla tester passerar lokalt
2. Koden är pushad till rätt branch
3. Workflow triggad manuellt med `confirm_deploy: "deploy"`
4. Verifiera att images byggts och pushats till registry
5. Kontrollera Docker Swarm services: `docker stack services [projektnamn]`
6. Verifiera email-notifikation (Mailjet)
7. Testa applikationen via dess publika URL

## Arbetsflöde

### Komplexitetsbedömning

Innan start, klassificera uppgiften:

- **Trivial** (en fil, uppenbar fix) → exekvera direkt
- **Medel** (2–5 filer, tydligt scope) → kort planering, sedan exekvera
- **Komplex** (arkitekturpåverkan, oklara krav) → fullständig utforskning och plan först

### Planera → Implementera → Verifiera

1. **Utforska** — läs befintlig kod, förstå mönster och beroenden.
2. **Planera** — vid medel/komplex: skriv plan innan implementation.
3. **Implementera** — skriv kod enligt planen. Följ befintliga mönster.
4. **Verifiera** — kör alla tester, typechecka, bekräfta att allt fungerar.

### Thinking triggers

För komplexa uppgifter, använd utökat resonemang:

- `think` → ~4 000 tokens tankebudget
- `think hard` → ~10 000 tokens
- `ultrathink` → ~32 000 tokens (rekommenderas för arkitekturbeslut och svår felsökning)

## Verifiering och grundning

> Att ge Claude sätt att verifiera sitt eget arbete är den enskilt viktigaste åtgärden för kvalitet. — Anthropic Best Practices

- **IMPORTANT:** Läs ALLTID relevanta filer INNAN du svarar om kodbasen. Gissa ALDRIG.
- Om du är osäker — säg det istället för att gissa.
- Kör tester efter varje implementation.
- Vid nya komponenter: titta på befintliga liknande komponenter först och följ mönstret.
- Typechecka efter kodändringar (`dotnet build`).
- Kör enskilda tester framför hela sviten för snabbare feedback.

### Definition av "implementerat"

Säg **aldrig** att något är "implementerat" eller "klart" förrän:

1. Alla **enhetstester** passerar (`dotnet test`).
2. Alla **E2E-tester i Playwright** passerar (`dotnet test --filter "Category=UI"`).
3. För webbprojekt: **visuellt verifierad** i webbläsaren — sidan laddas utan fel och funktionaliteten fungerar som förväntat.
4. Koden bedöms fungera till **100%**.

Om tester inte kan köras (saknad infrastruktur), informera tydligt om detta.

## Kontexthantering

- Vid kompaktering: bevara ALLTID listan över modifierade filer, felmeddelanden ordagrant, felsökningssteg som tagits, och alla testkommandon.
- Använd subagenter för utforskning och research — håll huvudkontexten ren.
- Använd `/clear` mellan orelaterade uppgifter.

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
- Alla HTML-element med visuell påverkan

**Korrekt ordning:**

1. Användaren frågar om något UI-relaterat
2. **FÖRST:** Anropa `Skill`-verktyget med `skill: "frontend-design"`
3. **SEDAN:** Följ instruktionerna från skillen för implementation

**ALDRIG:**

- Skriv UI-kod direkt utan skill-anrop
- Svara med designförslag utan att först ladda skillen
- Gör "snabba" CSS-fixar utan skillen — det finns inga undantag

### Iterativ förbättring

Om samma misstag upprepas, föreslå en ny regel för CLAUDE.md som förhindrar det.

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
- **Modifiering av framework/CMS-core** — använd extensions, hooks, child themes eller överlagring. Aldrig ändra core-filer.
- **Inline styles** — använd CSS-filer eller CSS-klasser, aldrig `style="..."` i HTML.
- **`eval()` eller `extract()`** — aldrig, varken i PHP eller JavaScript.
- **UI-kod utan `frontend-design` skill** — anropa ALLTID skillen innan du skriver HTML/CSS/JS med visuell påverkan.

## Kommandon

```bash
dotnet build                           # Bygg projektet
dotnet test                            # Kör enhetstester
dotnet run --project src/<ProjektNamn> # Kör applikationen
dotnet test --filter "Category=UI"     # Playwright E2E-tester

Filstruktur
Separera concerns: Models, Views, Controllers, Services.
Delade komponenter i Shared/ eller Components/.
Statiska assets alltid i assets/ i projektroten.
I .NET-projekt: wwwroot/ för webbspecifika filer.
Databas (SQLite)
Entity Framework Core med SQLite-provider.
Code-first med migrations.
Inkludera inte .db-filen i git.
Seed-data via migrations eller separat seed-metod.
Principer
YAGNI — bygg bara det som behövs nu. Tre liknande rader > prematur abstraktion.
Robusthet — validera indata vid systemgränser. Intern kod behöver inte defensiv validering.
Fail fast — tydliga felmeddelanden med kontext. Aldrig tysta fallbacks som döljer buggar.
DX — kod ska vara läsbar utan kommentarer. Bra namngivning räcker oftast.
Detaljerade referensfiler
Följande filer innehåller detaljerad information och laddas vid behov:
Kodstil och konventioner: @.claude/docs/conventions.md
Git-konventioner: @.claude/docs/git.md
Skills-installation: @.claude/docs/skills.md
Testkonventioner: @.claude/docs/testing.md
Övrigt
Redigera befintliga filer framför att skapa nya.
Håll denna fil fokuserad — om en instruktion kan tas bort utan att Claude gör fel, ta bort den.
