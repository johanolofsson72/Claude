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

## Test layers — every feature gets ALL of them (not just E2E)

A feature is not covered by destructive E2E tests alone. The mix follows the architecture (pyramid for backend/domain logic, more integration weight for service-heavy code — there's no universal ratio, the shape follows the code), but every behaviour-changing feature carries all three layers:

| Layer | Tool (.NET) | Covers | Rule of thumb |
|---|---|---|---|
| **Unit** | xUnit (+ Moq), FsCheck/CsCheck for wide-input logic | Pure functions, domain rules, validators, mappers, calculations — fast, no I/O | The broad base. Every non-trivial function with a decision in it. |
| **Integration** | xUnit + `WebApplicationFactory` / Testcontainers | API endpoints against a real (test) DB, EF Core queries, middleware, auth, transactions, the wiring between units | **Mandatory** — AI-written code passes unit tests but fails at the seams (this is where the real bugs concentrate). |
| **E2E (destructive)** | Playwright | Full user journeys + the destructive suite below + visual regression | Critical journeys + adversarial input. Thin but vicious. |

Unit + integration are **always required**, not optional extras on top of E2E. Integration tests are the layer AI code most often fails (units pass, the seams don't) — never skip them. Keep the full suite fast enough to run locally in one go (if it creeps past ~5 min you have too many high-level tests — push coverage down the pyramid).

## .NET projects

- Use **xUnit** as test framework.
- Use **Moq** or similar for mocking when needed.
- Separate unit tests in a dedicated project: `<ProjectName>.Tests`.

### xUnit v3 4.0 (2026-08-15, 4.0.1 on 2026-09-12) — breaking changes to know on upgrade

- **Microsoft.Testing.Platform v1 is no longer supported**; MTP v2 is the default. A project still pinning MTP v1
  packages has to move to v2 in the same change as the xUnit bump.
- **Report switches renamed:** `-report-junit` → `-report-xunit-junit`, `-report-xunit` → `-report-xunit-xml`
  (likewise ctrf/nunit), and default extensions changed (`.junit` → `.junit.xml`). Any script that globs report files
  must be updated with the bump, or it silently finds nothing.
- **Parallelization:** `DisableTestParallelization`, `MaxParallelThreads` and `ParallelAlgorithm` on
  `[assembly: CollectionBehavior]` are obsolete — use `[assembly: Parallelization]`.
- **Custom orderers:** ordering now has class and method levels, which likely breaks an existing `ITestCaseOrderer`.
- **Mono is dropped.**

## UI tests (Playwright)

- Use **Playwright** with **.NET** (Microsoft.Playwright) for UI and end-to-end tests.
- Playwright tests run with **xUnit** as test runner.
- Place UI tests in `<ProjectName>.Tests.UI` or similar.
- UI tests must be green before anything is reported as "done".

## Install Playwright browsers

Build the test project first — the script is generated into its output folder. Current: Microsoft.Playwright
**1.63.0** (2026-09-21).

```bash
dotnet build
# macOS / Windows (Git Bash or PowerShell): browsers only, no system packages needed
pwsh bin/Debug/net*/playwright.ps1 install chromium
# Linux: browsers as your user, then the system libraries once as root
pwsh bin/Debug/net*/playwright.ps1 install chromium
sudo pwsh bin/Debug/net*/playwright.ps1 install-deps chromium   # run this yourself — the template denies Bash(sudo *)
```

- `install --with-deps` does both in one step, but on Linux it needs root and will try to escalate on its own, so
  Claude cannot run it. The split above keeps the browser download unprivileged; the developer runs the one `sudo`
  line by hand (or installs the packages it lists with dnf/pacman on non-Debian distros).
- Debian 11 (since 1.62) and Ubuntu 20.04 (since 1.63) are no longer supported hosts.
- `install --no-remove` (1.63) keeps browsers that other Playwright versions on the machine still use — useful when
  two projects pin different Playwright versions.
- Isolated retries (`retryStrategy`, 1.62) and test locks (`lock`, 1.63) are **@playwright/test (Node) runner**
  features. Microsoft.Playwright tests run under xUnit, which has neither; in .NET, use an xUnit collection for tests
  that share a resource.

### The app under test starts from one declared port (row 063)

Without a pattern, every project invents its own startup. agentcrm kept its web port in four places:
`vite.config.ts`, an appsettings key, `playwright.config.ts` and a test helper. It had no `webServer`
key, so the server was started by hand and the four values were kept in sync from memory. Vite also
needed `--host`, because without it vite listens on `::1` only and an IPv4 hostname gets ECONNREFUSED.
That cost four runs in one evening. With the `@playwright/test` runner:

```ts
// e2e/port.ts — the only place the number is written; vite.config.ts and the tests import it
export const WEB_PORT = Number(process.env.WEB_PORT ?? 5173);

// playwright.config.ts
import { WEB_PORT } from './e2e/port';
export default defineConfig({
  use: { baseURL: `http://localhost:${WEB_PORT}` },
  webServer: {
    command: `npm run dev -- --host --port ${WEB_PORT} --strictPort`,
    url: `http://localhost:${WEB_PORT}`,
    reuseExistingServer: !process.env.CI, // use a dev server that is already running
    timeout: 120_000,
  },
});
```

- **One declaration, many readers.** A backend setting that has to know the web port (a public-link
  base, CORS) gets it from the same env var, never from a second literal.
- `--strictPort` makes a taken port fail loudly instead of moving to the next free one, where the
  tests would not look.
- `reuseExistingServer` means the suite starts what it needs and does not fight a dev server the
  developer already has running.
- A .NET backend the UI calls is a second `webServer` entry (it takes an array), with its own `url`
  health check, so the suite never runs against a half-started API.

## Running tests

```bash
# Unit tests
dotnet test

# E2E tests
dotnet test --filter "Category=UI"

# Single test (faster feedback)
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"
```

## Acceptance cases name their tests (full and hardened specs)

A full or hardened spec's `acceptance.md` holds 3-5 cases the developer confirmed
(`.claude/rules/spec-interview.md`). Write one test per case **before** production code, and put the
case id in the test: `// 080-AC-2` in a comment, or the name (`Checkout_080_AC_2_...` does not match;
keep the literal `080-AC-2` somewhere in the file). `spec-interview-guard-hook.sh` keeps production
source locked until every case is named by a test file. `bash scripts/acceptance-cases.sh --coverage
<spec-dir>` lists which cases still have no test.

## Functional coverage (MANDATORY — before destructive tests)

Before writing any destructive tests, you MUST first ensure **every implemented function has at least one browser test**. This is the #1 failure mode: Claude writes tests for 3 out of 12 features and calls it done.

### Step 1: Create a functional inventory

List EVERY user-facing function that was implemented or changed. Put this as a comment block at the top of the test file:

```csharp
// ===== FUNCTIONAL COVERAGE INVENTORY =====
// Every function listed here MUST have at least one browser test.
//
// 1. Search — user can search by keyword, results update live
// 2. Filter by category — dropdown filters results  
// 3. Pagination — navigate between pages
// 4. Sort by column — clicking header sorts asc/desc
// 5. Detail view — clicking item opens detail panel
// 6. Edit inline — double-click to edit in place
// 7. Breadcrumbs — reflect current path, clickable
// ... (list ALL functions, not just the "main" ones)
// =============================================
```

### Step 2: Write one test per function (MINIMUM)

Each inventory item needs at least one test that verifies the function **actually works end-to-end** with realistic data. Not a smoke test. Not "page loads". A test that proves the feature does what it should.

### Step 3: Verify coverage

Count inventory items. Count functional tests. If tests < items, you are NOT done. Move to destructive tests only after 100% functional coverage.

**What counts as a function:** Any user-visible behavior — UI interactions, navigation, data operations (CRUD, filter, sort, search, paginate, export), state changes (loading, error, empty, success), responsive behavior.

## Every interactive function must prove all four states at runtime (MANDATORY)

Functional coverage is not "the happy path renders". For every interactive/async function, a test must observe **all four states actually working** — a missing one is a failed validation, not a cosmetic gap (see `.claude/rules/scenarios.md` → post-implementation validation):

1. **Success** — the action actually happens (submit creates the record; clicking the map fires the pin/sheet/action). Assert the real outcome, not that a function was called.
2. **Error** — a **specific, visible** message. Never silent, never blank, never a raw stack trace. A failed login MUST say *why*. "There must never be a missing error message" is the canonical case.
3. **Empty** — zero results renders a real empty state, not a blank void.
4. **Loading** — feedback during async, and it resolves (no infinite spinner).

And validate the **real behaviour**: a test that asserts on a stub, never invokes the function, or only checks "page loaded" gives false confidence (high coverage, zero bite — the mutation gate is the backstop). Validate critical-path/prerequisite functions FIRST — if login or the primary interaction is broken, everything behind it is untestable, so fix the prerequisite before fanning out to deeper scenarios.

## Destructive browser tests (MANDATORY)

Every spec/feature involving **interactive UI** MUST include destructive Playwright tests AFTER functional coverage is complete. These tests should actively try to break the application.

**Interactive UI** = forms, user input, buttons that mutate state, multi-step flows, authentication, file uploads, modals with user actions, search/filter, drag-and-drop, real-time updates. Static pages, landing pages, content display, styling/CSS, i18n/translations, layout changes, and read-only dashboards do NOT require destructive tests.

Destructive tests without functional coverage are worthless — you're stress-testing a building where half the rooms were never inspected.

### How many destructive tests? Derive the count from the input domain — do NOT staple a constant to every function

There is no magic number. A flat "N per function" over-tests a toggle and under-tests a 12-field wizard — the count must scale with how much surface each function actually exposes. Derive it the way ISTQB does, per function:

1. **Equivalence partitioning** — one destructive test per *invalid* input class. A status toggle has ~1 invalid class; an email+password+date form has many.
2. **Boundary value analysis** — ISTQB 3-value BVA: for each boundary, test the value plus both neighbours (so ~2-3 boundary tests per bounded field).
3. **Cross-cutting attack scenarios** — the order/race/skip-step/auth/accessibility categories below that apply *regardless* of input count (double-submit, back-button, direct-URL, tab-order…).

Sum those three and you get a count that fits the function. As a sanity-check floor (the real reason a minimum exists at all is to fight the well-documented *positive-test bias* — developers naturally under-write negatives; the one solid empirical figure is Infosys' ~29%-of-tests-but-71%-of-defects result):

| Function shape | Destructive floor (guide, not gate) |
|---|---|
| Trivial interactive — toggle, single non-input button, pure navigation | **2-3** (mostly order/race + a11y; almost no input partitions) |
| Simple form — 1-3 input fields | **~6-10** (a handful of invalid partitions + boundaries) |
| Moderate form / filterable dashboard — 4-8 fields | **~12-20** (partitions multiply across fields) |
| Multi-step flow / auth / money / state machine | **~20-30+** (add skip-step, order, race on top of per-field partitions) |
| Offline/sync | the relevant tier **+** the offline/sync category |

The old flat "8" survives only as roughly the *simple-form* case — it was never a universal constant. **The count is a floor and a guide. It is NOT the definition of done.** The actual quality gate is the mutation kill rate (see below): a function can have 30 destructive tests that all pass and still let a flipped `>`/`<` through. Count proves tests *exist*; mutation score proves they *bite*.

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

1. **Functional inventory** — list ALL implemented functions in a comment block
2. **Functional tests** (1 per function, MINIMUM) — verify each function works end-to-end
3. Then, **for EACH interactive function**, a destructive suite sized to that function's input domain (see "How many destructive tests?" above), spanning the relevant attack categories:
   - **Invalid input** — one test per invalid equivalence class (garbage, empty, extreme, injection)
   - **Boundary values** — 3-value BVA per bounded field (value + both neighbours)
   - **Wrong order / race** — double-click, back button, URL jumping, rapid re-submit
   - **Skip steps / security** — XSS, injection, unauthorized access, DOM tampering
   - **Accessibility** — tab order, Enter-to-submit, Escape-closes-modal

The minimum is **1 functional test per implemented function** plus a per-function destructive floor scaled to its shape (trivial ~3 → multi-step/auth ~20-30+). Don't pad a toggle to hit a quota and don't stop a wizard at 8.

## Property-based tests (RECOMMENDED — the rung between example tests and TLA+)

For logic with a wide input space, hand-picked example tests sample a few points and miss the rest. Property-based testing (PBT) asserts an *invariant* and lets the framework generate hundreds of inputs (including the nasty boundaries it shrinks toward). It's the broadly-adopted "semi-formal" middle ground — lighter than TLA+, far stronger than a dozen `[Theory]` rows — and combined PBT + example testing measurably out-detects either alone.

- **.NET:** **FsCheck** (`FsCheck.Xunit`, callable from C#) or **CsCheck** (C#-native, less ceremony). Wire into the existing xUnit project.
- Best ROI on: parsers / serializers (round-trip: `parse(render(x)) == x`), money & date math, sorting/dedup/merge, any pure function with algebraic invariants, and stateful models (CsCheck/FsCheck command-based testing).
- **Recommended, not blocking.** Inventing a meaningful property is real work — apply PBT where the input space is wide and the invariant is clear; skip it where example tests already pin the behaviour.

## Visual regression tests (REQUIRED for UI — AI writes code, not pixels)

Functional and destructive tests pass while the page still looks broken: AI reasons over code tokens, not rendered output, so it ships wrong spacing, dead design tokens, and collapsed responsive layouts that no `getByRole` assertion catches. Screenshot baselines close that gap, **local-only** (respects `github-actions.md` CI-minimalism). How you get them depends on the runner.

**Node (`@playwright/test`)** has the comparison built in. `toHaveScreenshot` diffs against a committed PNG, and `npx playwright test --update-snapshots` writes the baselines:

```ts
// Baseline the key states of each screen (default, empty, error, loaded, dark mode).
// The width comes from the shared suite (see Viewports below), not from this test.
await expect(page).toHaveScreenshot('dashboard-default.png');
```

**.NET (`Microsoft.Playwright`)** has no screenshot assertion. `ToHaveScreenshotAsync` exists only in the JS runner, and a test that calls it does not compile. The .NET suite takes the picture with `ScreenshotAsync` and does the diff itself, against a PNG committed next to the tests:

```csharp
// Inside a ScreenTest-derived fixture (see Viewports below); Width is the fixture's width.
// using Codeuctivity.SkiaSharpCompare;  (Apache-2.0, ships its Linux native assets)
// Baselines live in the test project's source tree, not in bin/ (TestDirectory is bin/<config>/<tfm>).
var os       = OperatingSystem.IsMacOS() ? "macos" : OperatingSystem.IsWindows() ? "windows" : "linux";
var dir      = Path.GetFullPath(Path.Combine(TestContext.CurrentContext.TestDirectory, "..", "..", "..", "Baselines", os));
var baseline = Path.Combine(dir, $"dashboard-default-{Width}.png");
var actual   = Path.Combine(TestContext.CurrentContext.WorkDirectory, $"dashboard-default-{Width}.png");
await Page.ScreenshotAsync(new() { Path = actual, Animations = ScreenshotAnimations.Disabled });

if (Environment.GetEnvironmentVariable("VRT_UPDATE") == "1")
{
    Directory.CreateDirectory(dir);
    File.Copy(actual, baseline, overwrite: true);   // review the diff, then commit it
    Assert.Inconclusive($"baseline written: {baseline}");
}
Assert.That(File.Exists(baseline), $"no baseline at {baseline} — run once with VRT_UPDATE=1 and commit it");

var diff = Compare.CalcDiff(actual, baseline);
Assert.That(diff.PixelErrorPercentage, Is.LessThanOrEqualTo(0.1), $"{baseline}: {diff.PixelErrorCount} pixels differ");
```

- The comparer can be any pixel diff. `Codeuctivity.ImageSharpCompare` has the same API, but its ImageSharp dependency has a commercial licence above a revenue threshold. You can also skip the package and draw both PNGs onto a `<canvas>` in the page, then count differing pixels with `getImageData` (teach's `VisualBaseline`).
- `Animations = ScreenshotAnimations.Disabled` jumps running CSS transitions to their final frame. Without it a baseline can record the middle of a transition, and it fails randomly under load.
- Baselines are per platform. Font rendering differs between macOS and Linux, so keep one baseline set per OS (the `os` folder above) or render in the same container everywhere. Don't loosen the threshold until it stops catching real changes.
- A missing baseline fails the test. If it quietly wrote a new one, a fresh clone would pass with nothing to compare against.
- Capture the *states that matter* (empty / loading / error / loaded, plus dark mode), not every pixel of every page. The shared suite runs each of them at every viewport.
- The first run writes baselines (`--update-snapshots` on Node, `VRT_UPDATE=1` in the .NET sketch above); commit them. Later runs diff against them and fail on drift.
- Update baselines **deliberately** when a design change is intended — a baseline update is a reviewable diff, never an automatic overwrite.
- For component-level isolation (fewer false positives on churny output) a Storybook + Chromatic setup is the heavier alternative; default to Playwright screenshots first.

### Viewports — a dimension of the shared suite, not a line in one spec

A suite that runs at Playwright's default 1280px never sees phone width. fundit's HealthStrip overflowed horizontally at 375px from spec 001 until spec 004 set that width by hand in its own test (F024). A width set inside one test protects that test's screen and nothing else. It belongs in the shared configuration, so every a11y and visual test runs at every width without a spec asking.

```ts
// playwright.config.ts: one project per width, and every a11y/visual test runs in both
projects: [
  { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } } },
  { name: 'phone',   use: { ...devices['Desktop Chrome'], viewport: { width: 375,  height: 812 } } },
],
```

```csharp
// .NET (NUnit): the shared base fixture takes the width as a parameter, so each test runs once per
// width. Derived fixtures pass (width, height) through their own primary constructor.
[TestFixture(1280, 800)]
[TestFixture(375, 812)]
public abstract class ScreenTest(int width, int height) : PageTest
{
    protected int Width => width;   // for baseline names; a derived class reading `width` gets CS9107
    public override BrowserNewContextOptions ContextOptions() =>
        new() { ViewportSize = new() { Width = width, Height = height } };
}
```

Every screen also asserts **no horizontal overflow** at every width. A screenshot diff catches overflow only after a baseline exists, and the first baseline records the overflow as correct:

```ts
const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
expect(overflow, 'page scrolls horizontally').toBeLessThanOrEqual(0);
```

`scripts/project-maintenance.sh` (section 6d) reports a `[VIEWPORT]` finding for each Playwright config with no width below 480px and no phone device. A .NET suite has no config file to read, so there any test file setting a narrow width is accepted. A product that never renders on a phone (a kiosk, a fixed wall display) states it with a `narrow-viewport: not-applicable` comment in the config, followed by the reason.

## Mutation testing (THE quality gate — replaces "count the tests" as proof of done)

Line coverage proves a line *executed*; it says nothing about whether a test would *notice* if that line were wrong. Mutation testing injects deliberate bugs (flip `>` to `>=`, `&&` to `||`, delete a statement) and checks your tests kill them. The kill rate is the only metric that measures whether tests actually bite — Google, Meta, and AWS all converge on this over coverage %.

- **.NET:** **Stryker.NET** — `dotnet tool install -g dotnet-stryker`. Current: **5.0.0** (2026-09-11), which breaks
  two things on upgrade:
  - It **runs on the .NET 10 runtime**. A machine with only an older runtime cannot run the tool, whatever the
    project under test targets.
  - The **baseline disk provider now follows the output path**, so incremental runs (`--since`, `--with-baseline`)
    look for their baseline somewhere new. The first 5.0 run after the upgrade is effectively a full run; do not read
    its duration or its score change as a regression, and update any script that reads the baseline by path.
  - New in 5.0: `perTest` / `perTestInIsolation` coverage analysis under the MTP runner, timeouts computed from
    measured mutant runtimes, and `--diag` for when the mutated compilation fails.
- **A score counts only once it has reproduced.** Run the gate **three times** and compare
  *per-mutant* verdicts, not percentages: two runs in one project both reported 90.91% while
  disagreeing on seven mutants. Equal totals hiding different kills is a coin toss with a
  confident face. (Reference implementation: `scripts/mutation-gate-repeat.sh 3` in the msroute
  project — a repo without it should wrap its own runner the same way.)
- **Two instruments, one gate.** Gate on a **unit-only** project set; keep the wider set (unit +
  integration) for *attribution* and never tick a register row against it. A mutant "killed" by a
  hosted test with no stake in the mutated line is arithmetic, not evidence — measured at **38%**
  of one project's kills before the split.
- **NEVER in CI per push** (see `github-actions.md` — it's minutes-expensive and was a budget incident). Run it **nightly or on-demand**, and incrementally (changed files) on a branch.
- **"Nightly" needs a body, not just an intention.** Nothing schedules itself, and an unscheduled nightly gate runs never. `bash scripts/project-maintenance.sh --full` is the local pass that actually executes it (plus the secret/CVE scan and register drift checks), reporting only when it finds something. Attach it to a `/schedule` routine, `/loop 7d`, or crontab — never to a GitHub Action `schedule:` trigger.
- **A declared suite beats a guessed one.** `bash scripts/project-maintenance.sh --suite` runs the first non-comment line of `.claude/.suite-command`. Without that file it falls back to a root `npm test`, then `dotnet test`. A project with neither (bare `node tests/*.mjs`, PHP) can only clear the due job by declaring its suite. A .NET root with a nested `package.json` test script is never stamped green until the whole suite is declared. For mutation, a stack with no runner declares `scripts/run-mutation-gate.sh`. The nightly (`--unattended`) runs either declaration only after `--trust` has recorded its hash (spec 082).
- **Two solutions and no declaration is not a guess either.** When the fallback would be `dotnet test` or a bare `dotnet stryker` and the tree holds more than one `.sln`/`.slnx`, the pass refuses to run it and names the declaration to write. It will not quietly build whichever solution sits at the root. On ighweld-2026 that meant a dead root solution, and a green project read red (row 052).
- **Ratchets run whether anyone remembers them or not.** Every maintenance pass runs each `scripts/check-*.sh` from the repo root, with no arguments and a 300 s limit (`MAINTENANCE_RATCHET_TIMEOUT`). A non-zero exit is a finding. A ratchet that cannot run unattended opts out with `# maintenance: skip <reason>` in its first 30 lines, and the pass prints the reason.
- **Stryker does not tell you when it measured nothing.** Three ways, all measured on one project
  (row 047):
  - A span is `{start..end}` with two dots. `'**/X.cs{845-1080}'` is not an error. The braces become
    part of the glob, the glob matches no file, and the run still prints a score.
  - A span counts **characters**, not lines. The docs say "the indices of the first character and
    the last character" under a heading that says "lines". A span also did not shrink the run, so
    mutate the whole file and read that file's score from the JSON report.
  - **Stryker runs alone.** A `dotnet build` or `dotnet test` in the same project overwrites the
    mutated assembly, and the run scores about 0% with no warning.

  `project-maintenance.sh` checks every committed config's `mutate` patterns on each pass and will
  not start `--full` beside a live build. `scripts/stryker-guard-hook.sh` refuses both shapes when
  Claude issues the command. The overrides are `STRYKER_SPANS_ARE_CHARACTERS=1` and
  `STRYKER_GUARD=off`. On Windows Git Bash `ps` cannot see `dotnet.exe`, so there the run-alone
  rule is yours to keep.
- **An abandoned StrykerJS sandbox is removed when the next run starts** (row 053). StrykerJS
  deletes `.stryker-tmp` (or your `tempDirName`) only after a successful run, so a killed or failed
  run leaves a copy of the project in the tree. The guard hook and `--full` sweep it before a run,
  but only when no Stryker run is live and every entry is a `sandbox-*` directory. A directory
  holding anything else, one git tracks, or one whose config sets `cleanTempDir: false` is kept and
  reported. A `backup-*` entry comes from an interrupted `inPlace` run and may be the only copy of
  your original sources. It is never removed, and the next run is refused until you restore it.
- **A timeout is not a kill.** Stryker scores `Killed + Timeout`, gremlins' efficacy can rise as
  timeouts rise, and the percentage is not comparable run to run. Read the score by
  `.claude/rules/mutation-timeouts.md` (five traps, with the measurements).
- **Thresholds:** `break: 60, low: 60, high: 80`. Target **~80% kill on critical modules** (auth, money, state machines, parsers). Don't chase 100% — the last 20% buys fragile tests for vanishing return.
- **Flaky tests poison the score, and they poison it upward.** Stryker counts a failing test as a
  kill, so a test failing for its own reasons credits whichever mutant happened to be live. The
  score comes out *too high*, and fixing the flakiness *lowers* it — one project measured a
  polluted 86.11% becoming an honest 77.78%. Stabilize flakiness first, and read a drop
  afterwards as the truth arriving, not as a regression.

## Verification order

Before anything is declared "done":

1. `dotnet build` — no compilation errors
2. `dotnet test` — all unit tests pass (incl. any property-based tests)
3. `dotnet test --filter "Category=UI"` — all E2E tests pass (functional + destructive + visual-regression)
4. Stryker on the changed critical module(s), **three runs** — **nightly/on-demand, never in per-push CI** — kill rate ≥ target (80% on critical modules) **and reproduced**: zero mutants differing across the runs. This is the gate that proves the tests above actually catch bugs, and the repeat is what proves the gate itself is a measurement rather than a coin toss.
