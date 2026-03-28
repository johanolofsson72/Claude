# Testkonventioner

## Testfilosofi

Tester är en **försäkring**, inte en checklista. En försäkring som bara täcker "huset står kvar" är värdelös — den ska täcka brand, översvämning, inbrott och att grannen kör in i väggen.

**Varje test ska försöka förstöra applikationen.**

Utgångspunkten är en fientlig, oförutsägbar användare som:

- Matar in skräp, SQL-injektioner, `<script>`-taggar och emoji-orgier (💩🍆👻) i varje fält
- Klickar i fel ordning, dubbeklickar submit, trycker tillbaka mitt i ett flöde
- Hoppar över obligatoriska steg och försöker nå slutsteget direkt via URL
- Lämnar fält tomma, fyller i 10 000 tecken, klistrar in binärdata
- Skickar formulär innan sidan laddats klart
- Använder tangentbordsnavigering och tab-ordning ingen tänkt på

Om ett test bara verifierar att "sidan laddar" eller "formuläret skickas med giltig data" — det testet saknar värde. Happy path-tester är nödvändiga men INTE tillräckliga.

## Allmänt

- Alla nya funktioner ska ha tester.
- Tester ska vara isolerade och reproducerbara.
- Namngivning: `MetodNamn_Scenario_FörväntatResultat` (t.ex. `GetUser_WithValidId_ReturnsUser`).

## .NET-projekt

- Använd **xUnit** som testramverk.
- Använd **Moq** eller liknande för mocking vid behov.
- Separera enhetstester i ett eget projekt: `<ProjektNamn>.Tests`.

## UI-tester (Playwright)

- Använd **Playwright** med **.NET** (Microsoft.Playwright) för UI- och end-to-end-tester.
- Playwright-tester körs med **xUnit** som testrunner.
- Placera UI-tester i `<ProjektNamn>.Tests.UI` eller liknande.
- UI-tester ska vara gröna innan något rapporteras som "klart".

## Installera Playwright-browsers

```bash
pwsh bin/Debug/net*/playwright.ps1 install
```

## Köra tester

```bash
# Enhetstester
dotnet test

# E2E-tester
dotnet test --filter "Category=UI"

# Enskilt test (snabbare feedback)
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"
```

## Destruktiva browsertester (OBLIGATORISKT)

Varje spec/feature som involverar UI **MÅSTE** avslutas med destruktiva Playwright-tester. Dessa tester ska aktivt försöka knäcka applikationen, inte bara bekräfta att den fungerar.

### Attackkategorier — varje UI-spec ska täcka ALLA relevanta kategorier

#### 1. Ogiltig input (Garbage In)

- Tomma fält — skicka formulär utan att fylla i något
- Extremt lång input — 10 000+ tecken i textfält, 999999999 i nummerfält
- Unicode/emoji — `💩🍆👻`, kinesiska tecken, arabiska (RTL), zero-width spaces (`\u200B`)
- Specialtecken — `<script>alert('xss')</script>`, `'; DROP TABLE users;--`, `../../../etc/passwd`
- Negativa tal, decimaler med komma och punkt, datum i fel format
- HTML i textfält — `<b>bold</b>`, `<img src=x onerror=alert(1)>`
- Whitespace-only input — bara mellanslag, bara tabs, bara newlines

#### 2. Fel ordning och oväntat beteende

- Dubbelklicka på submit-knappen snabbt (ska inte skapa dubbla poster)
- Trycka tillbaka (browser back) mitt i ett flerstegsflöde och sedan framåt igen
- Navigera direkt till steg 3 via URL utan att ha gått igenom steg 1-2
- Refresha sidan mitt i ett formulär — är state bevarat?
- Öppna samma vy i två flikar och submitta i båda

#### 3. Hoppa över steg

- Försöka nå en skyddad sida utan att vara inloggad
- Anropa API-endpoints direkt utan att gå via UI
- Skippa obligatoriska fält genom att manipulera DOM (ta bort `required`-attribut)
- Submitta formulär via JavaScript-konsolen

#### 4. Gränsvärden och edge cases

- Exakt på maxlängd, exakt ett tecken över maxlängd
- Fält med bara mellanslag (bör inte godkännas som giltig input)
- Datum: 31 februari, 1 januari år 0000, datum långt i framtiden
- Negativa siffror där bara positiva förväntas
- Tom lista/noll resultat — hur ser UI:t ut?

#### 5. Timing och race conditions

- Klicka knappar innan sidan laddats klart
- Skicka formulär flera gånger snabbt i följd
- Avbryt en pågående operation (navigera bort mitt i en save)

#### 6. Tillgänglighet och tangentbord

- Tab genom alla formulärelement — är ordningen logisk?
- Enter i textfält — triggar det submit?
- Escape — stänger det modaler/dialoger?

### Namngivning av destruktiva tester

Använd prefix som tydligt visar att testet är destruktivt:

```csharp
SubmitForm_WithEmptyRequiredFields_ShowsValidationErrors
SubmitForm_WithXssPayload_SanitizesInput
SubmitForm_DoubleClick_CreatesOnlyOneRecord
Checkout_NavigateDirectlyToStep3_RedirectsToStep1
LoginForm_With10000CharacterPassword_ShowsError
UserProfile_WithUnicodeEmoji_DisplaysCorrectly
```

### Teststruktur per spec

Varje spec som involverar UI ska ha tester i denna ordning:

1. **Happy path** (1-2 tester) — bekräfta att grundflödet fungerar
2. **Ogiltig input** (3-5 tester) — skräp, tomma fält, extremvärden
3. **Fel ordning** (2-3 tester) — dubbelklick, tillbaka-knapp, URL-hopp
4. **Gränsvärden** (2-3 tester) — maxlängd, edge cases
5. **Säkerhet** (1-2 tester) — XSS, injection, obehörig åtkomst

Minimum **8 destruktiva tester** per spec. Om en feature har formulär, flerstegsflöden eller autentisering — fler.

## Verifieringsordning

Innan något deklareras som "klart":

1. `dotnet build` — inga kompileringsfel
2. `dotnet test` — alla enhetstester passerar
3. `dotnet test --filter "Category=UI"` — alla E2E-tester passerar (inklusive destruktiva tester)
