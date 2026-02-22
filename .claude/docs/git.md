# Git-konventioner

## Commit-meddelanden

Skriv commit-meddelanden på **svenska** med följande format:


<typ>: <kort beskrivning>
<valfri längre förklaring>

### Typer

- `feat`: Ny funktionalitet
- `fix`: Buggfix
- `refactor`: Omstrukturering utan beteendeförändring
- `test`: Tillägg eller ändring av tester
- `docs`: Dokumentation
- `style`: Formatering, semikolon, etc. (ingen kodändring)
- `chore`: Byggscript, beroenden, konfiguration

### Exempel


feat: Lägg till inloggningssida med formulärvalidering
Implementerar inloggningsformuläret med klient- och servervalidering.
Använder ASP.NET Identity för autentisering.

## Branches

- `main` — stabil produktionskod
- `develop` — aktiv utveckling
- `feature/<beskrivning>` — ny funktionalitet
- `fix/<beskrivning>` — buggfix

## Pull requests

- Titel på svenska, kort och beskrivande.
- Beskriv vad och varför i PR-beskrivningen.
- Länka till relevanta issues om sådana finns.