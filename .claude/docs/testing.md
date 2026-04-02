# Testing conventions

## Testing philosophy

Tests are an **insurance policy**, not a checklist. An insurance policy that only covers "the house is still standing" is worthless — it should cover fire, flood, burglary, and the neighbor driving into the wall.

**Every test should try to break the application.**

The starting point is a hostile, unpredictable user who:

- Enters garbage, SQL injections, `<script>` tags, and emoji orgies in every field
- Clicks in the wrong order, double-clicks submit, presses back mid-flow
- Skips mandatory steps and tries to reach the final step directly via URL
- Leaves fields empty, enters 10,000 characters, pastes binary data
- Submits forms before the page has finished loading
- Uses keyboard navigation and tab order no one thought of

If a test only verifies that "the page loads" or "the form submits with valid data" — that test lacks value. Happy path tests are necessary but NOT sufficient.

## General

- All new features must have tests.
- Tests should be isolated and reproducible.
- Naming: `MethodName_Scenario_ExpectedResult` (e.g., `GetUser_WithValidId_ReturnsUser`).

## .NET projects

- Use **xUnit** as test framework.
- Use **Moq** or similar for mocking when needed.
- Separate unit tests in a dedicated project: `<ProjectName>.Tests`.

## UI tests (Playwright)

- Use **Playwright** with **.NET** (Microsoft.Playwright) for UI and end-to-end tests.
- Playwright tests run with **xUnit** as test runner.
- Place UI tests in `<ProjectName>.Tests.UI` or similar.
- UI tests must be green before anything is reported as "done".

## Install Playwright browsers

```bash
pwsh bin/Debug/net*/playwright.ps1 install
```

## Running tests

```bash
# Unit tests
dotnet test

# E2E tests
dotnet test --filter "Category=UI"

# Single test (faster feedback)
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"
```

## Destructive browser tests (MANDATORY)

Every spec/feature involving UI **MUST** end with destructive Playwright tests. These tests should actively try to break the application, not just confirm that it works.

### Attack categories — every UI spec should cover ALL relevant categories

#### 1. Invalid input (Garbage In)

- Empty fields — submit form without filling in anything
- Extremely long input — 10,000+ characters in text fields, 999999999 in number fields
- Unicode/emoji — `💩🍆👻`, Chinese characters, Arabic (RTL), zero-width spaces (`\u200B`)
- Special characters — `<script>alert('xss')</script>`, `'; DROP TABLE users;--`, `../../../etc/passwd`
- Negative numbers, decimals with comma and period, dates in wrong format
- HTML in text fields — `<b>bold</b>`, `<img src=x onerror=alert(1)>`
- Whitespace-only input — only spaces, only tabs, only newlines

#### 2. Wrong order and unexpected behavior

- Double-click the submit button quickly (should not create duplicate records)
- Press back (browser back) mid-flow in a multi-step process and then forward again
- Navigate directly to step 3 via URL without going through steps 1-2
- Refresh the page mid-form — is state preserved?
- Open the same view in two tabs and submit in both

#### 3. Skip steps

- Try to reach a protected page without being logged in
- Call API endpoints directly without going through the UI
- Skip mandatory fields by manipulating the DOM (remove `required` attribute)
- Submit form via the JavaScript console

#### 4. Boundary values and edge cases

- Exactly at max length, exactly one character over max length
- Fields with only spaces (should not be accepted as valid input)
- Dates: February 31, January 1 year 0000, dates far in the future
- Negative numbers where only positive are expected
- Empty list/zero results — what does the UI look like?

#### 5. Timing and race conditions

- Click buttons before the page has finished loading
- Submit form multiple times quickly in succession
- Abort an ongoing operation (navigate away mid-save)

#### 6. Accessibility and keyboard

- Tab through all form elements — is the order logical?
- Enter in text field — does it trigger submit?
- Escape — does it close modals/dialogs?

### Naming of destructive tests

Use prefixes that clearly show the test is destructive:

```csharp
SubmitForm_WithEmptyRequiredFields_ShowsValidationErrors
SubmitForm_WithXssPayload_SanitizesInput
SubmitForm_DoubleClick_CreatesOnlyOneRecord
Checkout_NavigateDirectlyToStep3_RedirectsToStep1
LoginForm_With10000CharacterPassword_ShowsError
UserProfile_WithUnicodeEmoji_DisplaysCorrectly
```

### Test structure per spec

Every spec involving UI should have tests in this order:

1. **Happy path** (1-2 tests) — confirm the basic flow works
2. **Invalid input** (3-5 tests) — garbage, empty fields, extreme values
3. **Wrong order** (2-3 tests) — double-click, back button, URL jumping
4. **Boundary values** (2-3 tests) — max length, edge cases
5. **Security** (1-2 tests) — XSS, injection, unauthorized access

Minimum **8 destructive tests** per spec. If a feature has forms, multi-step flows, or authentication — more.

## Verification order

Before anything is declared "done":

1. `dotnet build` — no compilation errors
2. `dotnet test` — all unit tests pass
3. `dotnet test --filter "Category=UI"` — all E2E tests pass (including destructive tests)
