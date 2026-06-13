# Spec Testing Checklist — Destructive Tests (native mobile: React Native / Expo · Flutter)

> This is the **mobile** variant of `spec-testing-checklist.md`, covering both native toolchains. A native app has no browser — "browser tests" map to component/widget tests (**React Native Testing Library** or **Flutter widget tests**) and native E2E flows (**Maestro** for RN, **Patrol** / `integration_test` for Flutter). The attack categories are platform-level and identical across both frameworks; only the test tooling differs. Read `.claude/docs/testing-mobile.md` for full detail. Backend-agnostic — pair with the backend's own checklist. Web/.NET projects use `spec-testing-checklist.md` instead.

This checklist MUST be completed for every spec/feature that involves **interactive UI** (forms, user input, state-mutating buttons, multi-step flows, authentication, file/photo pickers, search/filter, gestures, map interaction, offline sync). Does NOT apply to static content screens, onboarding slides, or read-only display screens.

## When to use

- Writing a new spec (`spec.md`, `spec-*.md`)
- Writing task breakdowns (`tasks.md`, `tasks-*.md`)
- Writing implementation plans (`plan.md`, `plan-*.md`)
- Reviewing existing specs for completeness

## Mandatory structure in task files

Every task file with UI features MUST include TWO dedicated test phases: functional coverage FIRST, then destructive tests. The #1 failure mode is testing 3 out of 12 features and calling it done.

### Phase N-1: Functional Coverage Tests (BEFORE destructive tests)

```markdown
## Phase N-1: Functional Coverage Tests

### Functional inventory (list ALL implemented functions)
- [ ] T0XX: [Function 1] — e.g., Sign in with email/password, error on bad credentials (widget test + E2E)
- [ ] T0XX: [Function 2] — e.g., Map pins render, tapping a pin opens detail sheet (E2E)
- [ ] T0XX: [Function 3] — e.g., Category chips filter visible pins (component/widget)
- [ ] T0XX: [Function 4] — e.g., Favourite toggles and persists across relaunch (E2E)
- [ ] T0XX: [Function 5] — e.g., Pull-to-refresh refetches the list (component/widget)
- [ ] T0XX: [Function 6] — e.g., Deep link myapp://place/123 opens the right screen (E2E)
- [ ] T0XX: [Function N] — ... (continue until ALL functions are listed)

Every function above MUST have at least one test — a component/widget test (RNTL or Flutter `WidgetTester`)
or a native E2E flow (Maestro, or Patrol / integration_test for Flutter) — that verifies it works
end-to-end. If you implemented 12 functions, you need at least 12 functional tests. No exceptions.
```

### Phase N: Destructive Tests

> **The destructive quota is PER interactive UI function (≥8 each), and every scenario MUST run as a native E2E flow — Maestro (`.maestro/*-destructive.yaml`) for React Native / Expo, Patrol (`integration_test/`) for Flutter.** This is the mobile mirror of web running its 8 destructive scenarios per function in Playwright. The count is per function, NOT per spec: a screen with 12 interactive functions needs 12 × ≥8 = ≥96 destructive flows. A widget/component test (RNTL or `WidgetTester`) does NOT satisfy a destructive scenario: it cannot send the app to background, kill the process, press the OS hardware back button, deny a permission dialog, toggle airplane mode, or follow a deep link on cold start — and those are exactly the destructive categories. Widget tests are for **functional coverage** (Phase N-1); the destructive quota is a native-E2E quota. The block below is the template for ONE function — repeat it per interactive function. One destructive Maestro flow per scenario, each saved with a `-destructive` suffix.

```markdown
## Phase N: Destructive Tests — Function: [Function 1] (repeat this whole block per interactive function)
<!-- Every scenario below is a native E2E flow: Maestro for RN, Patrol for Flutter. NOT a widget test. Repeat the whole block for EACH interactive function. -->

### Category 1: Invalid Input (Garbage In)
- [ ] T0XX: Empty required fields — submit with all required fields empty, verify validation errors
- [ ] T0XX: Injection payload — `<script>alert(1)</script>` / `'; DROP TABLE--` in text + deep-link params, verify safe handling
- [ ] T0XX: Extreme length — 10,000+ characters in text fields, verify truncation or error
- [ ] T0XX: Unicode/emoji — enter `💩🍆👻`, RTL text, zero-width spaces, verify correct display

### Category 2: Lifecycle / Wrong Order
- [ ] T0XX: Double-tap submit — rapid double-tap, verify only one record created
- [ ] T0XX: Background & resume mid-flow — send app to background mid-form, resume, verify state preserved
- [ ] T0XX: Process kill & relaunch — stopApp/launchApp mid-flow, verify sane restore (no corrupt half-state)
- [ ] T0XX: Android hardware back — press back mid-flow, verify no data loss / no skipped validation

### Category 3: Skip Steps / Navigation Guards
- [ ] T0XX: Deep link to protected screen — myapp://account without auth, verify redirect to login
- [ ] T0XX: Deep link to step 3 — open a later wizard step directly, verify guard sends back to step 1
- [ ] T0XX: Direct API call — hit the backend without the UI, verify server-side authz still blocks

### Category 4: Boundary Values
- [ ] T0XX: Max length boundary — input exactly at max length and one character over
- [ ] T0XX: Whitespace-only — fields with only spaces must not pass validation
- [ ] T0XX: Empty state — verify the screen handles zero results (empty state, not blank void)
- [ ] T0XX: Huge list — 10,000 rows in FlatList/FlashList, verify scroll perf and no OOM

### Category 5: Network / Timing / Race Conditions
- [ ] T0XX: Tap before load — interact with UI before its data has loaded
- [ ] T0XX: Rapid repeated submit — submit 5 times in quick succession
- [ ] T0XX: Offline mid-save — toggle airplane mode mid-save, verify queue/error/retry
- [ ] T0XX: Navigate away mid-request — unmount during fetch, verify no setState-on-unmounted (stale closure)

### Category 6: Permissions / Platform / Accessibility
- [ ] T0XX: Permission denied — deny location/camera/photos/notifications at prompt, verify graceful degraded UX
- [ ] T0XX: Permission revoked while backgrounded — revoke in OS Settings, return, trigger feature
- [ ] T0XX: Notification tap routing — tap a push notification, verify deep route on cold AND warm start
- [ ] T0XX: Accessibility — VoiceOver/TalkBack reaches all controls; largest Dynamic Type doesn't clip critical UI
```

## Extra categories for offline/sync features

If the spec involves offline functionality, local persistence (AsyncStorage / SQLite / MMKV / WatermelonDB), or data synchronization, add:

```markdown
### Category 7: Offline / Sync Destruction
- [ ] T0XX: Kill mid-write — kill the app during a local write, relaunch, verify store not corrupted
- [ ] T0XX: Kill mid-sync — kill during a sync push, verify outbox not corrupted / not double-sent
- [ ] T0XX: Network drop mid-push — airplane mode during sync, verify retry and error state
- [ ] T0XX: Conflict scenario — edit same record on two devices, verify conflict resolution
- [ ] T0XX: Token expiry offline — expire token while offline, trigger sync, verify silent refresh or login prompt
- [ ] T0XX: Retry after error — verify manual retry works after a sync failure
- [ ] T0XX: Storage quota — fill local storage, verify graceful degradation (no silent data loss)
- [ ] T0XX: Multi-device — same record edited on two devices, verify UUID-based conflict handling
```

## Minimum requirements

**The counts below are PER interactive UI function, NOT per spec.** Each function in the functional inventory gets its own native-E2E destructive suite (Maestro/Patrol) at the minimum for its type. A screen with 12 interactive functions multiplies out: e.g. 12 simple-form functions = 12 × 8 = 96 destructive flows minimum. A flat 8-per-spec is NOT compliant.

| Function type (per interactive function) | Min destructive tests **per function** | Required categories |
|---------------------------------|----------------------|---------------------|
| Simple form                     | 8                    | 1, 2, 4, 5         |
| Multi-step flow / wizard        | 10                   | 1, 2, 3, 4, 5      |
| Auth-related                    | 10                   | 1, 2, 3, 5, 6      |
| Offline/sync                    | 15                   | 1–7 (all)           |
| Map / location / camera feature | 10                   | 2, 4, 5, 6         |
| List / data display            | 8                    | 2, 4, 5, 6          |

## Validation

A spec is NOT complete unless:

1. A "Functional Coverage Tests" phase exists with an inventory of ALL implemented functions
2. Every function in the inventory has at least one test (component/widget test or native E2E flow)
3. A dedicated "Destructive Tests" phase exists AFTER functional coverage
4. Each test has a unique task ID (T0XX)
5. Minimum destructive test count met **per interactive function** (NOT a flat count for the whole spec — multiply the per-function minimum by the number of interactive functions)
6. **The destructive tests are native E2E flows — Maestro (RN/Expo) or Patrol (Flutter), NOT widget tests.** Mirror of web's "8 destructive scenarios per function in Playwright". A spec whose destructive quota is filled with widget tests is NOT complete.
7. All relevant attack categories covered per function — including the mobile-specific Category 2 (lifecycle) and Category 6 (permissions/platform)
8. Tests describe what they verify, not just what they do

**The functional coverage check is the most important item.** A spec with 8 destructive tests but only 3 out of 12 functions tested is NOT complete — and note that 8 destructive flows for a 12-function screen is itself non-compliant: the minimum is 12 × 8 = 96, because the destructive quota is per interactive function, not per spec.
