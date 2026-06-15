# Testing conventions — native mobile (React Native / Expo · Flutter)

> This is the **mobile** variant of `testing.md`, covering both native toolchains: **React Native / Expo** and **Flutter**. A native app has no browser, so "browser tests" do not apply. The backend is irrelevant here — this file is about the client; pair it with whatever backend testing doc fits (`testing.md` for a .NET/web API).
>
> **The destructive discipline is the same for both frameworks** — the attack categories below (lifecycle, permissions, offline, deep links) are platform-level and identical whether the app is RN or Flutter. Only the **tooling** differs:
>
> | | React Native / Expo | Flutter |
> |---|---|---|
> | Unit / logic | Jest (`jest-expo`) | `flutter test` (`flutter_test`) |
> | Component / widget | React Native Testing Library | `flutter test` widget tests (`WidgetTester`) |
> | E2E (in-process) | — | `integration_test` (`flutter test integration_test/`) |
> | E2E (native, destructive) | **Maestro** (`.maestro/*.yaml`) | **Patrol** (`patrol test`) — native dialogs, permissions, deep links; Maestro also works |
> | Lint / typecheck | `npx tsc --noEmit` | `flutter analyze` |
>
> Read the section for your framework where they differ; everything else applies to both. Web/.NET projects use `testing.md` instead.

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

## Test layers — every feature gets ALL of them (not just E2E)

A feature is not covered by destructive native-E2E flows alone. The mix follows the architecture (the broad base is pure-logic unit tests, more weight on component/widget integration for screen-heavy code — there's no universal ratio, the shape follows the code), but every behaviour-changing feature carries all three layers:

| Layer | Tool (RN / Flutter) | Covers | Rule of thumb |
|---|---|---|---|
| **Unit / logic** | Jest (`jest-expo`) / `flutter test` (`flutter_test`) | Pure functions, reducers, hooks/notifiers, stores, mappers, money/date math — fast, no I/O | The broad base. Every non-trivial function with a decision in it. |
| **Integration (component/widget + API)** | RNTL (`@testing-library/react-native`) / `WidgetTester` | Rendering + user events, state changes, conditional UI, navigation wiring, plus any API-integration tests against a real (test) backend — the seams between units | **Mandatory** — AI-written code passes unit tests but fails at the seams (this is where the real bugs concentrate). |
| **E2E (destructive)** | **Maestro** (RN) / **Patrol** (Flutter) | Full user journeys on a real runtime + the destructive suite below + visual regression | Critical journeys + adversarial input. Thin but vicious. |

Unit + integration are **always required**, not optional extras on top of E2E. For mobile, the **integration** layer means component/widget integration (RNTL / `WidgetTester`) plus any API-integration tests — it is the layer AI code most often fails (units pass, the seams don't), so never skip it. The destructive E2E layer is the native flows (Maestro/Patrol) described below.

- Component/widget tests query by **accessibility role/label/text/semantics**, never by test-internal implementation detail. If you cannot select an element by what the user sees, the screen is not accessible — fix the screen, not the test.
- Native E2E flows must be green before anything is reported as "done". Destructive flows get a `-destructive` suffix.

### React Native / Expo

| Layer | Tool | What it covers |
|---|---|---|
| **Unit / logic** | Jest (`jest-expo` preset) | Pure functions, reducers, hooks-in-isolation, stores, mappers |
| **Component / integration** | `@testing-library/react-native` (RNTL) | Rendering, user events (`fireEvent`, `userEvent`), state changes, conditional UI, accessibility queries |
| **E2E flows** | **Maestro** (`.maestro/*.yaml`) | Real device/simulator flows: navigation, deep links, lifecycle, permissions |

E2E flows live in `.maestro/` at the repo root (or `app/.maestro/`), one `.yaml` per flow.

Notes (current as of 2026):
- **Maestro is the default**; **Detox** is the alternative when you need app-synchronized, JS-driven flows (more setup, native build required). Expo supports Maestro first-class — in CI, prefer the **EAS Workflows `maestro_test` job** over a hand-rolled runner.
- **RNTL version boundary:** v13 = React 18 / synchronous render; **v14 = React 19 + RN New Architecture, where `render`/`fireEvent`/`renderHook` are async and must be `await`ed.** New Architecture is now the default on recent Expo SDKs, so new projects are on the v14 async API. Pin deliberately and match your RN/React version.
- Prefer **`userEvent.setup()` + the `screen` API** over `fireEvent` for new tests — it models real interaction (focus, press timing) more faithfully.

### Flutter

| Layer | Tool | What it covers |
|---|---|---|
| **Unit / logic** | `flutter test` (`flutter_test`) | Pure Dart, providers/blocs/notifiers, mappers, repositories with mocks |
| **Widget** | `flutter test` + `WidgetTester` | `pumpWidget`, `tester.tap/enterText`, `find.bySemanticsLabel`, golden tests for visual regressions |
| **Integration / E2E (in-process)** | `integration_test` | Whole-app flows driven on a real device/emulator via `flutter test integration_test/` |
| **E2E (native, destructive)** | **Patrol** (`patrol test`) | Native permission dialogs, notifications, deep links, background/foreground, hardware back — the things `integration_test` alone cannot touch. Maestro also drives Flutter via the semantics tree |

Widget tests live next to the code under `test/`; integration/Patrol tests under `integration_test/`.

## Running tests

### React Native / Expo

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

If Maestro is not installed: `curl -fsSL https://get.maestro.mobile.dev | bash` (cross-platform; on Windows run under WSL or Git Bash).

### Flutter

```bash
# Static analysis — the cheapest signal, run first
flutter analyze

# Unit + widget tests
flutter test
flutter test test/login_test.dart          # single file
flutter test --name "withEmptyName"        # single test by name

# Integration / E2E on a device or emulator
flutter test integration_test/             # in-process integration tests
patrol test                                 # native E2E (permissions, deep links, lifecycle)
```

If Patrol is not installed: `dart pub global activate patrol_cli` then `patrol doctor`. E2E in either framework requires a running iOS Simulator (`xcrun simctl`) or Android emulator.

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

Each inventory item needs at least one test that verifies the function **actually works end-to-end** with realistic data — not a render-smoke test. A component/widget test proves the interaction; a native E2E flow (Maestro for RN, Patrol or `integration_test` for Flutter) proves the journey on a real runtime. (Flutter uses the same inventory in a `//` Dart comment block at the top of the test file.)

### Step 3: Verify coverage

Count inventory items. Count functional tests. If tests < items, you are NOT done. Move to destructive tests only after 100% functional coverage.

**What counts as a function:** any user-visible behavior — taps/gestures, navigation (stack/tab/deep link), data operations (CRUD, filter, sort, search, paginate), state changes (loading, error, empty, success), and persistence (does it survive a relaunch?).

## Every interactive function must prove all four states at runtime (MANDATORY)

Same rule as web (`.claude/rules/scenarios.md` → post-implementation validation): for every interactive/async function, observe **all four states actually working** — success (the tap/gesture actually does the thing), a **specific visible error** (never silent, never a blank screen — a failed sign-in must say why), empty (zero results → real empty state), loading (feedback that resolves, no infinite spinner). Validate the **real behaviour** on a real runtime (Maestro/Patrol drive the actual app), not a stub or a render-smoke. Validate prerequisite/critical-path flows FIRST — if sign-in or the primary gesture is broken, everything behind it is untestable; fix the prerequisite before fanning out.

## Destructive tests (MANDATORY)

Every spec/feature involving **interactive UI** MUST include destructive tests AFTER functional coverage is complete. These tests actively try to break the app.

> **Parity with web (non-negotiable): the destructive suite runs at the native E2E layer — Maestro for React Native / Expo, Patrol for Flutter — exactly as web runs its destructive scenarios in Playwright.** A widget/component test (RNTL or `WidgetTester`) does NOT count toward the destructive quota: it cannot background the app, kill the process, press the OS hardware back button, deny a permission dialog, toggle airplane mode, or open a deep link on cold start — and those ARE the destructive categories below. Widget tests cover functional coverage; the per-function destructive scenarios are Maestro/Patrol flows, each suffixed `-destructive`. The *number* of those flows scales with the function's input domain (next section) — it is not a flat constant.

**Interactive UI** = forms, user input, buttons that mutate state, multi-step flows, authentication, file/photo pickers, modals/sheets with actions, search/filter, gestures, map interaction, real-time/offline sync. Static content screens, marketing/onboarding slides, and read-only display screens do NOT require destructive tests.

Destructive tests without functional coverage are worthless — you are stress-testing a building where half the rooms were never inspected.

### How many destructive flows? Derive the count from the input domain — do NOT staple a constant to every function

There is no magic number. A flat "N per function" over-tests a toggle and under-tests a multi-step auth+permissions wizard — the count must scale with how much surface each function actually exposes. Derive it the way ISTQB does, per function:

1. **Equivalence partitioning** — one destructive flow per *invalid* input class. A status toggle has ~1 invalid class; an email+password+date form has many.
2. **Boundary value analysis** — ISTQB 3-value BVA: for each boundary, test the value plus both neighbours (so ~2-3 boundary flows per bounded field).
3. **Cross-cutting attack scenarios** — the mobile categories below that apply *regardless* of input count: lifecycle/order (double-tap, background-resume, process-kill, hardware back), skip-step/deep-link, race/network (offline mid-save, slow network, token expiry), permissions/a11y.

Sum those three and you get a count that fits the function. As a sanity-check floor (the real reason a minimum exists at all is to fight the well-documented *positive-test bias* — developers naturally under-write negatives):

| Function shape | Destructive floor (guide, not gate) |
|---|---|
| Trivial interactive — toggle, single tap, pure navigation | **2-3** (mostly lifecycle/order + a11y; almost no input partitions) |
| Simple form — 1-3 input fields | **~6-10** (a handful of invalid partitions + boundaries) |
| Moderate form / list-with-filters — 4-8 fields | **~12-20** (partitions multiply across fields) |
| Multi-step / auth / map / permissions-heavy | **~20-30+** (add skip-step, lifecycle, race on top of per-field partitions) |
| Offline / sync | the relevant tier **+** the offline/network category |

The old flat "8" survives only as roughly the *simple-form* case — it was never a universal constant. **The count is a floor and a guide. It is NOT the definition of done.** The actual quality gate is the mutation kill rate (see below): a function can have 30 destructive flows that all pass and still let a flipped `>`/`<` through. Count proves flows *exist*; mutation score proves they *bite*.

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
submitProfile_withEmptyRequiredFields_showsValidationErrors   (RNTL / Flutter widget test)
submitProfile_doubleTap_createsOnlyOneRecord                  (RNTL / Flutter widget test)
login-destructive.yaml            (Maestro)  → deep link to /account without auth → redirect
checkout-background-resume.yaml   (Maestro)  → background mid-step → relaunch → state intact
sync_airplane_mode_test.dart      (Patrol)   → toggle airplane mid-push → outbox not corrupted
permission_denied_test.dart       (Patrol)   → deny location at native dialog → graceful UX
```

### Test structure per spec

Every spec involving interactive UI should have tests in this order:

1. **Functional inventory** — list ALL implemented functions in a comment block
2. **Functional tests** (1 per function, MINIMUM) — RNTL and/or Maestro, verify each works end-to-end
3. Then, **for EACH interactive function**, a native-E2E destructive suite (Maestro/Patrol) sized to that function's input domain (see "How many destructive flows?" above), spanning the relevant categories:
   - **Invalid input** — one flow per invalid equivalence class (garbage, empty, extreme, injection)
   - **Boundary values** — 3-value BVA per bounded field (value + both neighbours); empty/huge lists
   - **Lifecycle / wrong order** — double-tap, background/resume, process-kill, hardware back
   - **Skip steps / navigation guards** — deep-link to a protected screen, deep-link past wizard steps, direct backend authz
   - **Network & permissions** — offline mid-save, slow network, token expiry, denied/revoked permission, a11y (screen reader, Dynamic Type, Reduce Motion)

The minimum is **1 functional test per implemented function** plus a per-function destructive floor scaled to its shape (trivial ~3 → multi-step/auth/permissions-heavy ~20-30+), all as native E2E flows. Don't pad a toggle to hit a quota and don't stop a wizard at 8.

The destructive scenarios are not invented from scratch each time — they derive from the project's living scenario map at `specs/SCENARIOS.md` (see `.claude/rules/scenarios.md`): happy-path rows become functional tests, the edge / adversarial / error / offline rows become destructive flows.

## Property-based tests (RECOMMENDED — the rung between example tests and TLA+)

For logic with a wide input space, hand-picked example tests sample a few points and miss the rest. Property-based testing (PBT) asserts an *invariant* and lets the framework generate hundreds of inputs (including the nasty boundaries it shrinks toward). It's the broadly-adopted "semi-formal" middle ground — lighter than TLA+, far stronger than a dozen hand-written cases — and combined PBT + example testing measurably out-detects either alone.

- **React Native / JS-TS:** **fast-check** — wire into the existing Jest (`jest-expo`) project. Best ROI on: parsers / serializers (round-trip: `parse(render(x)) === x`), money & date math, sorting/dedup/merge, reducers, and any pure function with algebraic invariants.
- **Flutter / Dart:** **kiri_check** or **glados** are the Dart options — note they are **less mature** than fast-check, so treat them as nice-to-have rather than a default reach.
- **Recommended, not blocking.** Inventing a meaningful property is real work — apply PBT where the input space is wide and the invariant is clear; skip it where example tests already pin the behaviour.

## Visual regression tests (REQUIRED for UI — AI writes code, not pixels)

Functional and destructive tests pass while the screen still looks broken: AI reasons over code tokens, not rendered output, so it ships wrong spacing, dead design tokens, and collapsed responsive layouts that no role/label assertion catches. Screenshot baselines close that gap, and one framework already has it built in — **local-only** (respects `github-actions.md` CI-minimalism).

- **Flutter:** **golden tests** are native VRT. Pump the widget to a state, then `await expectLater(find.byType(MyWidget), matchesGoldenFile('my_widget.png'))`. First run writes baselines with `flutter test --update-goldens`; commit them, later runs diff and fail on drift. Use golden tests for the key widget states.
- **React Native / Expo:** no built-in golden support — use **Maestro screenshots** in a flow (`- takeScreenshot: dashboard-loaded`) or **jest-image-snapshot** for component-level capture. Update baselines deliberately when a design change is intended.
- Capture the *states that matter* (empty / loading / error / loaded, plus dark mode and one device size), not every pixel of every screen. A baseline update is a reviewable diff, never an automatic overwrite.

## Mutation testing (THE quality gate — replaces "count the tests" as proof of done)

Line coverage proves a line *executed*; it says nothing about whether a test would *notice* if that line were wrong. Mutation testing injects deliberate bugs (flip `>` to `>=`, `&&` to `||`, delete a statement) and checks your tests kill them. The kill rate is the only metric that measures whether tests actually bite — Google, Meta, and AWS all converge on this over coverage %.

- **React Native / TS-JS:** **StrykerJS** (`@stryker-mutator/core`) — run `npx stryker run` over the changed module.
- **Flutter / Dart:** **`mutation_test`** or **`mutest`** are the Dart options — note their **relative immaturity** compared to StrykerJS; treat the Flutter side as best-effort on critical modules.
- **NEVER in CI per push** (see `github-actions.md` — it's minutes-expensive and was a budget incident). Run it **nightly or on-demand**, and incrementally (changed files) on a branch.
- **Thresholds:** `break: 60, low: 60, high: 80`. Target **~80% kill on critical modules** (auth, money, state machines, parsers, sync/outbox). Don't chase 100% — the last 20% buys fragile tests for vanishing return. The mutation kill rate is the gate; the test count is not.
- Flaky tests poison the score (a flaky test "survives" mutants at random) — stabilize flakiness first.

## Verification order

Before anything is declared "done":

**React Native / Expo**
1. `npx tsc --noEmit` — no type errors
2. `npm test` — all unit + component (RNTL) tests pass (incl. any fast-check property tests)
3. `maestro test .maestro/` — all E2E flows pass (functional + destructive + visual-regression screenshots)
4. `npx stryker run` on the changed critical module(s) — **nightly/on-demand, never in per-push CI** — kill rate ≥ target (80% on critical modules). This is the gate that proves the tests above actually catch bugs.

**Flutter**
1. `flutter analyze` — no analyzer errors
2. `flutter test` — all unit + widget tests pass (incl. golden tests and any kiri_check/glados property tests)
3. `flutter test integration_test/` and/or `patrol test` — all E2E flows pass (functional + destructive)
4. `mutation_test` / `mutest` on the changed critical module(s) — **nightly/on-demand, never in per-push CI** — kill rate ≥ target (80% on critical modules). This is the gate that proves the tests above actually catch bugs.
