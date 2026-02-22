# Projektmall

Mall för projektspecifika sektioner. **VIKTIGT:** Fyll i ALLA sektioner nedan vid projektstart — repo-specifik anpassning ger 2x bättre resultat (källa: Arize ML).

## Kärnprinciper (icke-förhandlingsbara)

Projektspecifika principer som ALDRIG får brytas:

1. [FYLL I: t.ex. "All dataåtkomst MÅSTE vara tenant-scopad"]
2. [FYLL I: t.ex. "JWT-tokens MÅSTE lagras i sessionStorage, aldrig cookies"]

## Projektbeskrivning

**Projektnamn**: [FYLL I]
**Syfte**: [FYLL I: kort beskrivning av vad systemet gör och för vem]
**Designdokument**: [FYLL I: sökväg till grafisk profil, eller ta bort raden]

## Arkitektur

Beskriv systemets komponenter med ett ASCII-diagram:

```text
[FYLL I: ASCII-diagram]

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

## Obligatoriska kataloger

Följande kataloger ska **alltid** skapas i nya projekt:

- `src/` — all källkod
- `tests/` — alla tester
- `legacy/` — gamla filer och kod som fasas ut
- `artifacts/` — build-output, rapporter och genererade filer
- `temp/` — temporära filer (ska ligga i `.gitignore`)

## Typiska projektprofiler

Projekten är ofta stora fullstack-applikationer med frontend, backend, databaser och autentisering. .NET backend + SQLite, ofta kopplad till kurs-/projektwebb.

**Learnways-integration**: Backend kopplas ofta till webbplats byggd av [Learnways](https://learnways.com) (partner) i ren HTML, CSS och JavaScript.

## Nyckelmönster

Dokumentera projektets centrala mönster så att Claude skriver idiomatisk kod:

- **Autentisering**: [FYLL I: t.ex. JWT i sessionStorage, Identity + cookies, OAuth]
- **Databasaccess**: [FYLL I: t.ex. EF Core repositories, `$wpdb->prepare()`, direkt SQL]
- **API-mönster**: [FYLL I: t.ex. Minimal API med `Result<T>`, MVC controllers]
- **Felhantering**: [FYLL I: t.ex. `Result<T, Exception>`, ProblemDetails]
- **State management**: [FYLL I: t.ex. Blazor cascading parameters, Redux]
- **Domäntermer**: [FYLL I: affärstermer och akronymer som används i kodbasen]

## Lokal utvecklingsmiljö

**Startkommando:**

```bash
# [FYLL I: t.ex. dotnet run --project src/AppHost]
```

**URL:er:**

- Frontend: [FYLL I: t.ex. https://localhost:5001]
- Admin: [FYLL I: om tillämpligt]

**Kända workarounds:**

- [FYLL I: eventuella problem med IPv6, minne, portar, certifikat etc.]
