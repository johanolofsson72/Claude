# Testing conventions — React Native / Expo (mobile)

> This is the **mobile** variant of `testing.md`. A native app has no browser, so "browser tests" do not apply — the equivalents are **Maestro** flows (E2E) and **React Native Testing Library** (component/integration). Use this file on Expo / React Native projects. Web/.NET projects use `testing.md` instead.

## Testing philosophy

Tests are an **insurance policy**, not a checklist. An insurance policy that only covers "the app still launches" is worthless — it should cover the app being backgrounded mid-save, the OS killing the process under memory pressure, the user revoking location permission, and the network dropping halfway through a sync.

**Every test should try to break the app.**

The starting point is a hostile, unpredictable user on an unreliable device who:

- Enters garbage, injection payloads, `<script>` tags, and emoji orgies in every field
- Taps in the wrong order, double-taps submit, presses the Android hardware back button mid-flow
- Opens a deep link straight to a guarded screen without going through the steps before it
- Backgrounds the app mid-form, gets a phone call, comes back five minutes later
- Toggles airplane mode mid-save, rides into a tunnel, hops between WiFi and 5G
- Revokes a permission you already asked for, then triggers the feature that needs it
- Rotates the device, bumps the system font to the largest size, turns on the screen reader

If a test only verifies that "the screen renders" or "the form submits with valid data" — that test lacks value. Happy path tests are necessary but NOT sufficient.

## General

- All new features must have tests.
- Tests should be isolated and reproducible.
- Naming: `subject_scenario_expectedResult` (e.g., `submitProfile_withEmptyName_showsValidationError`).

## Test layers

| Layer | Tool | What it covers |
|---|---|---|
| **Unit / logic** | Jest (`jest-expo` preset) | Pure functions, reducers, hooks-in-isolation, stores, mappers |
| **Component / integration** | `@testing-library/react-native` (RNTL) | Rendering, user events (`fireEvent`, `userEvent`), state changes, conditional UI, accessibility queries |
| **E2E flows** | **Maestro** (`.maestro/*.yaml`) | Real device/simulator flows: navigation, multi-step journeys, deep links, lifecycle, permissions |

- Component tests query by **accessibility role/label/text**, never by test-internal implementation detail. If you cannot select an element by what the user sees, the screen is not accessible — fix the screen, not the test.
- E2E flows live in `.maestro/` at the repo root (or `app/.maestro/`), one `.yaml` per flow. Destructive flows get a `-destructive` suffix.
- E2E flows must be green before anything is reported as "done".

## Running tests

```bash
# Typecheck — the cheapest signal, run first
npx tsc --noEmit

# Unit + component tests (jest-expo)
npm test
npx jest path/to/file.test.tsx          # single file, faster feedback
npx jest -t "withEmptyName"              # single test by name

# E2E flows (Maestro) — simulator/emulator or device must be running
maestro test .maestro/                   # whole suite
maestro test .maestro/login-destructive.yaml   # single flow
```

If Maestro is not installed: `curl -fsSL https://get.maestro.mobile.dev | bash` (cross-platform; on Windows run under WSL or Git Bash). E2E flows require a running iOS Simulator (`xcrun simctl`) or Android emulator.

## Functional coverage (MANDATORY — before destructive tests)

Before writing any destructive tests, you MUST first ensure **every implemented function has at least one test** (RNTL for components, Maestro for flows). This is the #1 failure mode: tests cover 3 out of 12 features and the work is called done.

### Step 1: Create a functional inventory

List EVERY user-facing function that was implemented or changed. Put this as a comment block at the top of the test file (or the Maestro flow):

```tsx
// ===== FUNCTIONAL COVERAGE INVENTORY =====
// Every function listed here MUST have at least one test (RNTL or Maestro).
//
// 1. Sign in — email + password, error on bad credentials
// 2. Map view — pins render, tapping a pin opens the detail sheet
// 3. Filter by category — chips narrow the visible pins
// 4. Favourite — tap heart toggles state, persists across relaunch
// 5. Offline banner — shows when network drops, hides on reconnect
// 6. Pull-to-refresh — refetches the list
// 7. Deep link — myapp://place/123 opens the right detail screen
// ... (list ALL functions, not just the "main" ones)
// =============================================
```

### Step 2: Write one test per function (MINIMUM)

Each inventory item needs at least one test that verifies the function **actually works end-to-end** with realistic data — not a render-smoke test. A component test proves the interaction; a Maestro flow proves the journey on a real runtime.

### Step 3: Verify coverage

Count inventory items. Count functional tests. If tests < items, you are NOT done. Move to destructive tests only after 100% functional coverage.

**What counts as a function:** any user-visible behavior — taps/gestures, navigation (stack/tab/deep link), data operations (CRUD, filter, sort, search, paginate), state changes (loading, error, empty, success), and persistence (does it survive a relaunch?).

## Destructive tests (MANDATORY)

Every spec/feature involving **interactive UI** MUST include destructive tests AFTER functional coverage is complete. These tests actively try to break the app.

**Interactive UI** = forms, user input, buttons that mutate state, multi-step flows, authentication, file/photo pickers, modals/sheets with actions, search/filter, gestures, map interaction, real-time/offline sync. Static content screens, marketing/onboarding slides, and read-only display screens do NOT require destructive tests.

Destructive tests without functional coverage are worthless — you are stress-testing a building where half the rooms were never inspected.

### Attack categories — every interactive spec should cover ALL relevant categories

#### 1. Invalid input (Garbage In)

- Empty fields — submit a form with nothing filled in
- Extremely long input — 10,000+ characters in text fields, huge numbers in number fields
- Unicode/emoji — `💩🍆👻`, CJK, Arabic (RTL), zero-width spaces (`​`)
- Injection payloads — `<script>alert(1)</script>`, `'; DROP TABLE users;--`, `../../../etc/passwd` (relevant for WebViews, deep-link params, and anything forwarded to a backend)
- Negative numbers, decimals with comma vs period, dates in the wrong format
- Whitespace-only input — only spaces, only tabs, only newlines

#### 2. Lifecycle & wrong order (the mobile-specific killer)

- Double-tap the submit button fast (must NOT create duplicate records)
- **Background the app mid-flow** (Home / app switcher) and resume — is in-progress state preserved?
- **Process kill & relaunch mid-flow** (`maestro` `stopApp`/`launchApp`, or OS low-memory kill) — does the app restore to a sane screen, not a corrupt half-state?
- **Android hardware back** mid-flow — does it lose data, skip validation, or escape a modal it shouldn't?
- Rotate the device mid-form (if rotation is allowed) — is input kept?
- Receive an interrupt (incoming call / system dialog) during a write

#### 3. Skip steps & navigation guards

- **Deep link straight to a protected screen** (`myapp://account`) without auth — redirect to login?
- Deep link to step 3 of a wizard without completing steps 1–2
- Navigate to a guarded route via the router/tab bar directly
- Call the backend API directly (no UI) — server-side authz must still hold

#### 4. Boundary values and edge cases

- Exactly at max length, exactly one character over
- Fields with only spaces (must not pass validation)
- Dates: Feb 31, year 0000, dates far in the future
- Empty list / zero results — what does the screen look like? (skeleton, empty state, not a blank white void)
- **Very large lists** — 10,000 rows in a `FlatList`/`FlashList`: scroll perf, no jank, no OOM

#### 5. Network, timing & race conditions

- Tap a button before its data has loaded
- Submit the same form 5× in quick succession
- **Airplane mode / offline mid-save** — queued? error shown? retry available?
- Slow network (throttle) — does a spinner hang forever, or time out gracefully?
- Navigate away mid-request — the unmounted screen must not `setState` on a stale closure (the classic RN warning and a real bug source)
- Auth token expires mid-request — silent refresh or a clean re-login, never an infinite spinner

#### 6. Permissions, platform & accessibility

- **Permission denied** at the prompt (location, camera, photos, notifications) — graceful degraded UX, not a crash or dead screen
- **Permission revoked in OS Settings while the app was backgrounded**, then the feature is triggered
- Low-memory pressure (simulator "Simulate Memory Warning") — no crash
- Notification tap routes to the correct deep screen (cold start AND warm)
- OS theme change (light/dark) and locale/RTL change while running
- Screen reader (VoiceOver / TalkBack) reaches every interactive element; largest Dynamic Type / font scale does not clip critical UI; `prefers-reduced-motion` (Reduce Motion) is respected

### Naming of destructive tests

Use prefixes/suffixes that clearly show the test is destructive:

```
submitProfile_withEmptyRequiredFields_showsValidationErrors   (RNTL)
submitProfile_doubleTap_createsOnlyOneRecord                  (RNTL)
login-destructive.yaml            → deep link to /account without auth → redirect
checkout-background-resume.yaml   → background mid-step → relaunch → state intact
sync-airplane-mode.yaml           → toggle airplane mid-push → outbox not corrupted
```

### Test structure per spec

Every spec involving interactive UI should have tests in this order:

1. **Functional inventory** — list ALL implemented functions in a comment block
2. **Functional tests** (1 per function, MINIMUM) — RNTL and/or Maestro, verify each works end-to-end
3. **Invalid input** (3–5 tests) — garbage, empty, extreme values
4. **Lifecycle / wrong order** (2–3 tests) — double-tap, background/resume, hardware back
5. **Boundary values** (2–3 tests) — max length, empty/huge lists
6. **Network & permissions** (2–3 tests) — offline mid-save, denied permission, deep-link authz

Minimum **1 functional test per implemented function** + **8 destructive tests** per spec. Features with auth, offline sync, permissions, or multi-step flows need more.

## Verification order

Before anything is declared "done":

1. `npx tsc --noEmit` — no type errors
2. `npm test` — all unit + component (RNTL) tests pass
3. `maestro test .maestro/` — all E2E flows pass (including destructive flows)
