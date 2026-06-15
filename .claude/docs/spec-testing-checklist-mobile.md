# Spec Testing Checklist — Destructive Tests (native mobile: React Native / Expo · Flutter)

> This is the **mobile** variant of `spec-testing-checklist.md`, covering both native toolchains. A native app has no browser — "browser tests" map to component/widget tests (**React Native Testing Library** or **Flutter widget tests**) and native E2E flows (**Maestro** for RN, **Patrol** / `integration_test` for Flutter). The attack categories are platform-level and identical across both frameworks; only the test tooling differs. Read `.claude/docs/testing-mobile.md` for full detail. Backend-agnostic — pair with the backend's own checklist. Web/.NET projects use `spec-testing-checklist.md` instead.

This checklist MUST be completed for every spec/feature that involves **interactive UI** (forms, user input, state-mutating buttons, multi-step flows, authentication, file/photo pickers, search/filter, gestures, map interaction, offline sync). Does NOT apply to static content screens, onboarding slides, or read-only display screens.

> **Scenarios come from the living scenario map.** The functional inventory below is derived from the `happy` rows of `specs/SCENARIOS.md`, and the destructive suite from its `edge` / `adversarial` / `error` / `offline` rows (see `.claude/rules/scenarios.md`). If a function or destructive case here has no matching `SC-id`, the scenario was never mapped — add it (or run the scenario interview) before writing the flow.

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

> **The destructive suite is sized PER interactive UI function (not per spec), and every scenario MUST run as a native E2E flow — Maestro (`.maestro/*-destructive.yaml`) for React Native / Expo, Patrol (`integration_test/`) for Flutter.** This is the mobile mirror of web running its per-function Playwright destructive suite. The *size* of each function's suite is derived from its input domain, not a flat constant: `(one flow per invalid equivalence class) + (3-value boundary-value analysis per bounded field) + (applicable cross-cutting attack scenarios)`. A status toggle lands around 2-3 flows; a 12-field wizard lands at 20-30+ (see the floor table below). The count is per function, NOT per spec. A widget/component test (RNTL or `WidgetTester`) does NOT satisfy a destructive scenario: it cannot send the app to background, kill the process, press the OS hardware back button, deny a permission dialog, toggle airplane mode, or follow a deep link on cold start — and those are exactly the destructive categories. Widget tests are for **functional coverage** (Phase N-1); the destructive suite is native-E2E only. The block below is the template for ONE function — repeat it per interactive function and prune/expand each category to fit that function's domain. One destructive Maestro/Patrol flow per scenario, each saved with a `-destructive` suffix.

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

## Sizing the destructive suite (per interactive function, input-domain-derived)

**The size is decided PER interactive UI function, NOT per spec — but it is derived from each function's input domain, not stapled on as a constant.** For every function in the inventory, the destructive count (in native-E2E flows — Maestro/Patrol) is:

```
(one flow per invalid equivalence class)
  + (3-value boundary-value analysis per bounded field — value + both neighbours)
  + (applicable cross-cutting attack scenarios — lifecycle/background, process kill, hardware back,
     skip-step/deep-link guards, permissions, offline, a11y that apply regardless of field count)
```

A status toggle has ~1 invalid class and no bounded fields, so it lands low; an email + password + date form multiplies partitions and boundaries across three fields, so it lands high. The table below is a **floor and a guide — a sanity check, not a gate.** Its only job is to fight the well-documented positive-test bias (developers under-write negatives). The "Required categories" column still tells you which attack categories apply to each shape — that part is load-bearing.

| Function shape (per interactive function) | Destructive floor (guide, not gate) | Required categories |
|---|---|---|
| Trivial interactive — toggle, single non-input button, pure navigation | **~2-3** (mostly lifecycle/order + a11y; almost no input partitions) | 2, 5, 6 |
| Simple form — 1-3 input fields | **~6-10** (a handful of invalid partitions + boundaries) | 1, 2, 4, 5 |
| Moderate form / filterable list / map / camera — 4-8 fields or platform surface | **~12-20** (partitions multiply across fields; add permissions/platform) | 1, 2, 4, 5, 6 |
| Multi-step flow / wizard / auth / money / state machine | **~20-30+** (add skip-step/deep-link guards, lifecycle, race on top of per-field partitions) | 1, 2, 3, 4, 5, 6 |
| Offline/sync | the matching tier above **+** the offline/sync category | tier's categories + 7 |

Every flow is still native E2E (Maestro/Patrol), never a widget test — sizing changes the count, not the tooling. Do not pad a toggle to hit a number, and do not stop a wizard at the simple-form floor. The old flat "8" survives only as roughly the simple-form case — it was never a universal constant.

### The real gate is mutation kill rate, not the count

The destructive count is a **floor to fight positive-test bias** — it proves the negative flows *exist*. It is NOT the definition of done. The actual quality gate is the **mutation kill rate** (StrykerJS for the RN/JS logic, run nightly / on-demand per `github-actions.md`, target **~80% on critical modules** — auth, money, state machines, sync/conflict resolution, parsers). A function can have 30 green destructive flows and still let a flipped `>`/`<` through; the count says flows exist, the mutation score says they *bite*. A spec that hits its count but whose tests don't kill mutants is NOT done.

## Validation

A spec is NOT complete unless:

1. A "Functional Coverage Tests" phase exists with an inventory of ALL implemented functions
2. Every function in the inventory has at least one test (component/widget test or native E2E flow)
3. A dedicated "Destructive Tests" phase exists AFTER functional coverage
4. Each test has a unique task ID (T0XX)
5. The destructive suite **per interactive function** is sized to its input domain (equivalence partitions + boundaries + applicable categories), not a flat quota — sized individually per function, NOT a single number for the whole spec
6. **The destructive tests are native E2E flows — Maestro (RN/Expo) or Patrol (Flutter), NOT widget tests.** Mirror of web running its destructive suite per function in Playwright. A spec whose destructive suite is filled with widget tests is NOT complete.
7. All relevant attack categories covered per function — including the mobile-specific Category 2 (lifecycle) and Category 6 (permissions/platform)
8. Tests describe what they verify, not just what they do

**The functional coverage check is the most important item.** A spec with a destructive suite but only 3 out of 12 functions tested is NOT complete — and a single destructive block covering the whole screen is itself non-compliant: each interactive function gets its own native-E2E suite, sized to its own input domain. And remember the count is only the floor: the actual gate is the mutation kill rate (~80% on critical modules) — a spec that hits its counts but whose flows don't kill mutants is NOT done.
