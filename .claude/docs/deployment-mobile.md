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

- **iOS:** an App Store Connect API key (App Manager role) lets `eas submit` upload without an interactive Apple login. Store it as an EAS secret, not in the repo.
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

Per `.claude/rules/github-actions.md`, store builds are the one mobile case that genuinely cannot run locally on the cluster, so a **single `workflow_dispatch` build/submit workflow is allowed**. EAS runs the actual build on Expo's servers — the GitHub Action only triggers it, so it consumes almost no Actions minutes. No push/schedule triggers, no per-spec workflows. See the mobile carve-out in `github-actions.md`.

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
      - uses: expo/expo-github-action@v8
        with: { eas-version: latest, token: ${{ secrets.EXPO_TOKEN }} }
      - run: eas build --platform ${{ inputs.platform }} --profile ${{ inputs.profile }} --non-interactive --no-wait
```

> **Flutter note:** if a project uses Flutter instead, the equivalent is `flutter build ipa` / `flutter build appbundle` + fastlane (or `flutter build` + manual upload) to the same TestFlight/Play tracks, under the same `workflow_dispatch`-only CI carve-out. This doc documents the chosen EAS/RN path; add a Flutter deploy doc when a Flutter app reaches release.
