# Testkonventioner

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

Köra tester
# Enhetstester
dotnet test

# E2E-tester
dotnet test --filter "Category=UI"

# Enskilt test (snabbare feedback)
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"

Verifieringsordning
Innan något deklareras som "klart":
dotnet build — inga kompileringsfel
dotnet test — alla enhetstester passerar
dotnet test --filter "Category=UI" — alla E2E-tester passerar