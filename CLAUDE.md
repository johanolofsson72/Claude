# CLAUDE.md

## Kritiska regler (LÄS FÖRST)

- **ALWAYS** läs koden först — basera ALLA slutsatser på bevis från kodbasen, inte antaganden.
- **ALWAYS** verifiera med `dotnet build` och `dotnet test` innan du säger att något är "klart".
- **ALWAYS** använd Edit-verktyget för kirurgiska ändringar — kopiera aldrig hela filer.
- **ALWAYS** anropa `frontend-design`-skillen via Skill-verktyget INNAN du skriver UI-kod (HTML, CSS, JS, design, layout, utseende). Detta är ett **BLOCKERANDE KRAV**.
- **ALWAYS** kör genererad text genom `humanizer`-skillen via Skill-verktyget INNAN leverans till människor (dokumentation, commit-meddelanden, PR-beskrivningar, mejl, README). Detta är ett **BLOCKERANDE KRAV**.
- **ALWAYS** följ befintliga mönster i kodbasen — titta på liknande komponenter först.
- **ALWAYS** avsluta varje spec/feature som involverar UI med **destruktiva browsertester** (Playwright). Målet är **99% E2E-täckning**. Tester som bara verifierar happy path räcker INTE. INNAN du skriver en spec/task-fil: läs `.claude/docs/spec-testing-checklist.md` och inkludera destruktiva tester som en egen fas i task-filen.

## Exekveringsläge

### Autonomt läge (NON-INTERACTIVE)

- Agera direkt utan att vänta på bekräftelse.
- Saknad information är inte ett hinder — gör rimliga antaganden och fortsätt.
- Fel ska hanteras och fixas självständigt.
- Frågor är tillåtna BARA vid arkitekturbeslut eller kravtolkning som inte rimligt kan antas.
- **Max 3 försök per problem** — om samma approach misslyckas 3 gånger, kör `/clear` och prova en helt annan strategi med en bättre prompt.

### Anti-stall regel

Om ingen tydlig uppgift hittas — välj den mest sannolika uppgiften och agera. Stagnation betraktas som misslyckande.

### Interview-mönstret

För större features: intervjua utvecklaren med `AskUserQuestion` innan implementation. Fråga om teknisk implementation, edge cases och tradeoffs. Skriv sedan en spec innan kodning börjar.

## Prioritetsordning

1. **Säkerhet** — aldrig kompromissa
2. **Korrekthet** — koden ska göra rätt sak
3. **Enkelhet** — minsta möjliga komplexitet
4. **Läsbarhet** — tydlig kod framför smart kod
5. **Prestanda** — optimera bara vid behov

## Projektbeskrivning

Detta är ett **mallrepo för Claude Code-konfiguration** — en återanvändbar uppsättning regler, agents, hooks och skills för .NET/fullstack-projekt. Repot kopieras som utgångspunkt vid nya projektstart.

> **Vid projektstart:** Fyll i kärnprinciper, arkitektur och dev-miljö i `.claude/docs/project-template.md`

## Språk

- Kommunicera alltid på **svenska** i konversationer och commit-meddelanden.
- **ALWAYS** använd korrekta svenska tecken: **å, ä, ö** (INTE a/o som ersättning). Text utan åäö är oacceptabel.
- Kod, variabelnamn och tekniska termer skrivs på **engelska**.
- Kommentarer i kod skrivs på **engelska**.

## Teknikstack

- **.NET** (Web API, Blazor, MVC, Razor Pages) — senaste stabila versionen
- **React** (förstahandsval för frontend i nya projekt) — byggs till wwwroot i .NET-projektet för en enda Docker-image
- **SQLite** som databas (om inget annat anges)
- **WordPress** (PHP, teman, plugins)
- **HTML, CSS, JavaScript, jQuery** (äldre projekt/enklare sidor)

## CI/CD och deployment

Docker Swarm-kluster på Azure (live4.se). För IP-adresser, pipeline, kommandon och checklista, se `.claude/docs/deployment.md`

## Arbetsflöde

### Komplexitetsbedömning

- **Trivial** (en fil, uppenbar fix) → exekvera direkt
- **Medel** (2–5 filer, tydligt scope) → kort planering, sedan exekvera
- **Komplex** (arkitekturpåverkan, oklara krav) → fullständig utforskning och plan först

### Planera → Implementera → Verifiera

1. **Utforska** — läs befintlig kod, förstå mönster och beroenden.
2. **Planera** — vid medel/komplex: använd Plan Mode (Shift+Tab) för att skriva plan innan implementation.
3. **Implementera** — växla till Normal Mode, skriv kod enligt planen. Följ befintliga mönster.
4. **Verifiera** — kör alla tester, typechecka, bekräfta att allt fungerar.
5. **Committa** — commit på svenska: `<typ>: <beskrivning>` (feat/fix/refactor/test/docs/style/chore). Detaljer i `.claude/docs/git.md`

## Verifiering och grundning

> Att ge Claude sätt att verifiera sitt eget arbete är den enskilt viktigaste åtgärden för kvalitet. — Anthropic Best Practices

- **IMPORTANT:** Läs ALLTID relevanta filer INNAN du svarar om kodbasen. Gissa ALDRIG.
- Kör tester efter varje implementation.
- Kör enskilda tester framför hela sviten för snabbare feedback.

### Definition av "implementerat"

Säg **aldrig** att något är "implementerat" eller "klart" förrän:

1. Alla **enhetstester** passerar (`dotnet test`).
2. Alla **E2E-tester i Playwright** passerar (`dotnet test --filter "Category=UI"`).
3. För UI-features: **destruktiva browsertester** har skrivits och passerar. Målet är **99% E2E-täckning** — varje spec ska täcka alla relevanta attackkategorier (se `.claude/docs/spec-testing-checklist.md` och `.claude/docs/testing.md`).
4. För webbprojekt: **visuellt verifierad** i webbläsaren.
5. Koden bedöms fungera till **100%**.

Om tester inte kan köras (saknad infrastruktur), informera tydligt om detta.

## Kontexthantering

- Vid kompaktering: bevara ALLTID modifierade filer, felmeddelanden ordagrant, felsökningssteg och testkommandon. Komprimerings-instruktion: `"When compacting, always preserve the full list of modified files and any test commands"`.
- Använd subagenter för utforskning och research — håll huvudkontexten ren.
- Använd `/clear` mellan orelaterade uppgifter — blanda aldrig orelaterade uppgifter i samma session.
- Använd `/compact <fokus>` för kontrollerad komprimering, t.ex. `/compact Fokusera på API-ändringarna`.
- Bryt ner stora uppgifter i diskreta deluppgifter — begär aldrig 5+ features i ett steg.
- Efter 2 misslyckade rättningar av samma problem: `/clear` och skriv en bättre prompt från början.

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

## Referensfiler (laddas vid behov)

Läs dessa filer NÄR du behöver dem — ladda inte allt i förväg:

- **Ny projektstart** eller arkitekturfrågor → `.claude/docs/project-template.md`
- **Kodstil, namngivning, förbjudna mönster** → `.claude/docs/conventions.md`
- **Säkerhetsfrågor** (SQL injection, XSS, secrets) → `.claude/docs/security.md`
- **Git commit/branch/PR** → `.claude/docs/git.md`
- **Hooks, subagenter, plugins, sessions** → `.claude/docs/workflows.md`
- **Skapa nya agenter** → `.claude/docs/agents-templates.md`
- **Skills, SKILL.md-format, Agent Skills-standarden** → `.claude/docs/skills.md`
- **Tester (xUnit, Playwright)** → `.claude/docs/testing.md`
- **Spec-testchecklista (destruktiva tester)** → `.claude/docs/spec-testing-checklist.md`
- **Deploy, Docker, CI/CD** → `.claude/docs/deployment.md`

## Filorganisation

- **`scripts/`** — Underhållsscript (`update-template.sh` för att hålla mallrepot uppdaterat, `sync-prompt.md` med prompt för att synka andra projekt).
- **`.claude/skills/`** — projektskills med SKILL.md (code-review, explore-codebase, deploy-checklist, update-template). Följer Agent Skills-standarden (agentskills.io).
- **`.claude/agents/`** — subagenter (dotnet-reviewer, security-scanner, test-runner, db-agent). Stödjer `isolation: worktree`, `background`, `hooks` i frontmatter.
- **`.claude/rules/`** — regler som auto-laddas varje session. Stödjer path-scoping med YAML-frontmatter.
- **`.claude/docs/`** — referensmaterial som laddas vid behov. Referera UTAN `@`-prefix för att undvika auto-expansion.
- **`CLAUDE.local.md`** — personliga projektinställningar som inte committas (auto-gitignored).

## Iterativ förbättring

- Om samma misstag upprepas: föreslå en ny regel för CLAUDE.md eller en hook som förhindrar det.
- Varje kodgranskningskommentar är en signal att agenten saknade kontext — uppdatera CLAUDE.md.
- Redigera befintliga filer framför att skapa nya.
- Håll denna fil fokuserad — om en instruktion kan tas bort utan att Claude gör fel, ta bort den.
