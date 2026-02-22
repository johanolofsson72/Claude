# Projektmall

Mall för projektspecifika sektioner i CLAUDE.md. Fyll i vid projektstart.

## Arkitektur

Beskriv systemets komponenter med ett ASCII-diagram:

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

- **Autentisering**: [T.ex. JWT i sessionStorage, Identity + cookies, OAuth]
- **Databasaccess**: [T.ex. EF Core repositories, `$wpdb->prepare()`, direkt SQL]
- **API-mönster**: [T.ex. Minimal API med `Result<T>`, MVC controllers]
- **Felhantering**: [T.ex. `Result<T, Exception>`, ProblemDetails]
- **State management**: [T.ex. Blazor cascading parameters, Redux]

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
