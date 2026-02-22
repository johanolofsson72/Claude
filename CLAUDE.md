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
**Designdokument**: [Sökväg till grafisk profil, om tillämpligt]

> Fyll i arkitektur, kataloger, nyckelmönster och lokal dev-miljö enligt @.claude/docs/project-template.md

## Språk

- Kommunicera alltid på **svenska** i konversationer och commit-meddelanden.
- Kod, variabelnamn och tekniska termer skrivs på **engelska**.
- Kommentarer i kod skrivs på **engelska**.

## Teknikstack

- **.NET** (Blazor, MVC, Razor Pages, Web API) — senaste stabila versionen
- **SQLite** som databas (om inget annat anges)
- **WordPress** (PHP, teman, plugins)
- **HTML, CSS, JavaScript, jQuery** (frontend)

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
- Använd `/compact <fokus>` för kontrollerad komprimering, t.ex. `/compact Fokusera på API-ändringarna`.

## Frontend design skill (BLOCKERANDE KRAV)

> **CRITICAL — BLOCKING REQUIREMENT:** Innan du skriver EN ENDA RAD UI-kod MÅSTE du anropa `frontend-design`-skillen via Skill-verktyget. Oavsett omfattning — en knapp, en färg, en margin. Triggerord och detaljer: @.claude/docs/workflows.md

## Kommandon

```bash
dotnet build                           # Bygg projektet
dotnet test                            # Kör enhetstester
dotnet run --project src/<ProjektNamn> # Kör applikationen
dotnet test --filter "Category=UI"     # Playwright E2E-tester
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"  # Enskilt test
```

## Principer

- **YAGNI** — bygg bara det som behövs nu. Tre liknande rader > prematur abstraktion.
- **Fail fast** — tydliga felmeddelanden med kontext. Aldrig tysta fallbacks.
- **DX** — kod ska vara läsbar utan kommentarer. Bra namngivning räcker oftast.

## Skräddarsy för ditt projekt

> **VIKTIGT:** Repository-specifik anpassning ger dubbelt så stor förbättring som generella regler (källa: Arize ML-forskning). Fyll i alla `[platshållare]` i denna fil med projektspecifik information. Ju mer konkret — desto bättre resultat.

## Detaljerade referensfiler

Följande filer innehåller detaljerad information och laddas vid behov:

- Projektmall (arkitektur, kataloger, dev-miljö): @.claude/docs/project-template.md
- Kodstil, filstruktur, databas och förbjudna impl.: @.claude/docs/conventions.md
- Säkerhet: @.claude/docs/security.md
- Git-konventioner: @.claude/docs/git.md
- Arbetsflöden, hooks, subagenter, sessions-tips: @.claude/docs/workflows.md
- Skills-installation: @.claude/docs/skills.md
- Testkonventioner: @.claude/docs/testing.md
- CI/CD och deployment: @.claude/docs/deployment.md

## Övrigt

- Redigera befintliga filer framför att skapa nya.
- Håll denna fil fokuserad — om en instruktion kan tas bort utan att Claude gör fel, ta bort den.
