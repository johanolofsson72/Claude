# Mobile deployment (React Native / Expo — EAS)

> This is the **mobile app** deployment doc. It covers shipping a React Native / Expo app to the App Store and Google Play via **EAS** (Expo Application Services). It is separate from `deployment.md`, which deploys a backend to the live4 cluster — a mobile project usually has BOTH concerns: the app ships to the stores (this doc), and any backend it talks to ships to live4 (`deployment.md`). The two are independent deploy targets.

## The model

- **EAS Build** compiles the native binaries (`.ipa` / `.aab`) on Expo's servers — no local Xcode/Android Studio toolchain required, and no cluster minutes burned. Local builds are still possible (`eas build --local`) when needed.
- **EAS Submit** uploads a built binary to App Store Connect (→ TestFlight) and Google Play (→ internal/closed/production track).
- **EAS Update** pushes over-the-air JS/asset updates to already-installed apps without a new store review — for anything that is not a native change.

Native change (new native module, permission, SDK bump, icon, splash) → **new build + submit**. JS-only change (logic, screens, styles) → **EAS Update** is enough.

## eas.json — build + submit profiles

```jsonc
{
  "cli": { "version": ">= 12.0.0", "appVersionSource": "remote" },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal"
    },
    "preview": {
      "distribution": "internal",          // ad-hoc / internal testers, no store
      "channel": "preview",                // EAS Update channel this build listens on
      "ios": { "simulator": false }
    },
    "production": {
      "channel": "production",
      "autoIncrement": true,               // bumps buildNumber / versionCode automatically
      "env": { "APP_ENV": "production" }
    }
  },
  "submit": {
    "production": {
      "ios": {
        "appleId": "ci@yourorg.se",
        "ascAppId": "1234567890",
        "appleTeamId": "ABCDE12345"
      },
      "android": {
        "serviceAccountKeyPath": "./secrets/play-service-account.json",
        "track": "internal"                // promote internal → production in Play console
      }
    }
  }
}
```

## Versioning

- Marketing version lives in `app.config.ts` (`version`).
- Build numbers (`ios.buildNumber`, `android.versionCode`) are bumped by `autoIncrement: true` with `appVersionSource: "remote"` so EAS owns the counter — no manual edits, no collisions between machines/CI.

## Credentials

Let EAS manage signing credentials; do not hand-roll certificates.

```bash
eas credentials                 # interactive — generates/stores iOS certs + provisioning, Android keystore
```

- **iOS:** an App Store Connect API key (`ascApiKeyPath`/`ascApiKeyIssuerId`/`ascApiKeyId`) is the **preferred** submit credential — it uploads without an interactive Apple login or 2FA friction in CI. (Apple ID + app-specific password via `EXPO_APPLE_APP_SPECIFIC_PASSWORD` still works but is the fallback.) Store the key as an EAS secret, not in the repo.
- **Android:** a Google Play service-account JSON with the "Release" permission. Keep it under `secrets/` (gitignored) or, better, an EAS secret.

## Build → submit → update

```bash
# One-time
npm i -g eas-cli && eas login
eas build:configure

# Native build + store submit (run when native code/config changed)
eas build   --platform all --profile production
eas submit  --platform ios --profile production    # → TestFlight
eas submit  --platform android --profile production # → Play internal track

# JS/asset-only change to live apps (no store review)
eas update --branch production --message "fix: filter reset on tab change"
```

`eas update` only reaches builds whose `channel` matches the update `branch` mapping — so a `production` build receives `production` updates. Never push an update that assumes a native capability the installed build does not have; that is the one way OTA bricks a screen.

## Runtime versions (OTA governance)

An OTA update must only land on a build whose **native layer** is compatible — pushing a JS update that assumes a native module the installed binary lacks is the one way `eas update` bricks a screen. The runtime version is the compatibility key.

Set a **fingerprint** policy for any app with native modules:

```jsonc
// app.config.ts / app.json
{ "runtimeVersion": { "policy": "fingerprint" } }
```

`fingerprint` hashes the native project, so the runtime version bumps **automatically and only when native code actually changes** — graduated from experimental and now the recommended policy. The `appVersion` policy (the `eas update:configure` default) has a documented footgun: forget to bump the version after a native change and you ship an incompatible JS update. The invariant either way: **native change → new build + submit; JS/asset-only change → `eas update`.**

Deployment governance the pipeline should use:
- **Gradual rollouts** — publish an update to a percentage of users, watch crash/error rates, then ramp to 100%.
- **Emergency rollback** — `eas update:roll-back-to-embedded` reverts live apps to the JS bundle baked into the binary when a bad update ships.

## Secrets / config

- **Build-time secrets** (API keys baked into the binary, signing): `eas secret:create` / EAS environment variables. Never commit them.
- **Runtime public config** (API base URL, feature flags): `app.config.ts` reading `process.env.*`, or `expo-constants`. The API base URL points at the backend on live4 (e.g. `https://projectname.live4.se`) — the app and backend deploy independently, so a backend deploy never requires an app rebuild as long as the API contract holds.

## Definition of "deployed" (mobile)

A mobile release is not "done" until:

1. `npx tsc --noEmit`, `npm test`, and `maestro test .maestro/` are green (per `testing.md`).
2. Mobile performance checks pass (per `stress-testing.md` → native performance section).
3. `eas build --profile production` succeeds for both platforms.
4. The build is on **TestFlight** and the **Play internal track**, installed on a real device, and the critical flow smoke-tested on-device.
5. Only then promote: submit to App Store review / promote the Play track to production.

## CI/CD

Two paths. **Prefer EAS Workflows** for an Expo-centric project; use the GitHub Actions form only if the team is already standardized on GHA.

**EAS Workflows (preferred).** Expo's own CI/CD — YAML in `.eas/workflows/`, with pre-packaged job types (`build`, `submit`, `update`, `maestro_test`, `deploy`) that chain build → submit → update without hand-wiring `EXPO_TOKEN` into a third-party runner. It runs on Expo's infrastructure, so it does not touch the org's GitHub Actions minutes at all — which also keeps it clear of the `github-actions.md` budget rule.

```yaml
# .eas/workflows/release.yml
name: Mobile release
on:
  workflow_dispatch: {}
jobs:
  build_ios:     { type: build,  params: { platform: ios, profile: production } }
  build_android: { type: build,  params: { platform: android, profile: production } }
  submit_ios:    { needs: [build_ios],     type: submit, params: { platform: ios } }
  submit_android:{ needs: [build_android], type: submit, params: { platform: android } }
```

Trigger with `eas workflow:run release.yml` (or a `workflow_dispatch`/manual trigger — keep it off push per the same on-demand principle as the cluster deploy).

**GitHub Actions (fallback).** Per `.claude/rules/github-actions.md`, store builds are the one mobile case that genuinely cannot run locally on the cluster, so a **single `workflow_dispatch` build/submit workflow is allowed**. EAS runs the actual build on Expo's servers — the Action only triggers it, so it consumes almost no Actions minutes. No push/schedule triggers, no per-spec workflows.

```yaml
# .github/workflows/mobile-release.yml — workflow_dispatch only
name: Mobile release
on:
  workflow_dispatch:
    inputs:
      profile: { description: "EAS profile", default: "production" }
      platform: { description: "ios | android | all", default: "all" }
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npx tsc --noEmit && npm test    # gate: don't ship a broken build
      - uses: expo/expo-github-action@v9
        with: { eas-version: latest, token: ${{ secrets.EXPO_TOKEN }} }
      - run: eas build --platform ${{ inputs.platform }} --profile ${{ inputs.profile }} --non-interactive --no-wait
```

> **Flutter note:** if a project uses Flutter instead, the equivalent is `flutter build ipa` / `flutter build appbundle` + fastlane (or `flutter build` + manual upload) to the same TestFlight/Play tracks, under the same `workflow_dispatch`-only CI carve-out. This doc documents the chosen EAS/RN path; add a Flutter deploy doc when a Flutter app reaches release.
