# EBTL Customer App

Flutter app for **EBTL**, a beach-side cocktail-kit service
("You bring the bottle. We bring the magic."). Customers pick a beach cart,
browse cocktails and shop products, filter cocktails by a liquor bottle they
already own (the **Cocktail Finder**), customize a kit, and check out with
pickup or delivery. There is **no customer login** — an anonymous session token
is created by the backend and stored on-device. Prices are in EGP.

The app is a thin client over the `/api/customer/*` endpoints of the
`ebtl-admin-dashboard` backend (hosted on Render). See
[`AGENTS.md`](AGENTS.md) for architecture, conventions, and contributor
guidance.

## Requirements

- Flutter (stable channel), Dart SDK `^3.12.0`
- Android SDK / Xcode for device builds (the product targets Android + iOS)

## Commands

Run from this directory (`customer-app/`):

```bash
flutter pub get      # install dependencies
flutter analyze      # static analysis — must pass cleanly
flutter test         # widget/unit tests
flutter run          # launch on a connected device/emulator
flutter build apk    # release Android build
```

## Build-time configuration

These integrations are inert unless configured, so the app builds and runs
without any of them:

| Flag / file | Purpose | Default |
| --- | --- | --- |
| `--dart-define=API_BASE_URL=...` | Point at a different backend (e.g. staging) | Production Render URL |
| `--dart-define=CLARITY_PROJECT_ID=...` | Microsoft Clarity session replay (release builds only); empty disables it | EBTL project |
| `--dart-define=ANALYTICS_ENABLE_DEBUG=true` | Enables Firebase Analytics and Meta App Events during a debug validation run | Disabled in debug |
| `google-services.json` / `GoogleService-Info.plist` | Enables Firebase push, Crashlytics, and Analytics | Firebase integrations disabled |

Payments use Stripe's native Payment Sheet; the backend delivers the
per-checkout Stripe keys. See the root [`STRIPE_SETUP.md`](../STRIPE_SETUP.md).

## iOS releases from GitHub Actions

`.github/workflows/ios-release.yml` builds a signed App Store IPA on a macOS
runner and ships it to TestFlight, so cutting a build needs no Mac. Run it from
the **Actions** tab (optional version / build-number / backend overrides, and an
"upload" toggle if you only want the IPA as an artifact), or push an `ios-v*`
tag. It is deliberately not part of PR CI: macOS minutes bill at 10x and an
archive takes roughly 20 minutes.

One-time setup — add these repository secrets under
*Settings → Secrets and variables → Actions*:

| Secret | Where it comes from |
| --- | --- |
| `IOS_DIST_CERTIFICATE_P12_BASE64` | Apple Distribution certificate **with its private key**, exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `IOS_DIST_CERTIFICATE_PASSWORD` | the password you set during that export |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store provisioning profile for `wtf.ebtl.app` (Push Notifications capability enabled), base64-encoded |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect → Users and Access → Integrations → Keys |
| `APP_STORE_CONNECT_API_ISSUER_ID` | same page (a UUID) |
| `APP_STORE_CONNECT_API_KEY` | contents of the downloaded `AuthKey_*.p8`, BEGIN/END lines included — downloadable only once |
| `IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64` | optional; base64 of `GoogleService-Info.plist` from Firebase project `ebtl-37ddb` |

You also need the app record for `wtf.ebtl.app` to exist in App Store Connect
before the first upload. Every upload needs a build number higher than the last
one accepted for that version — bump `version:` in `pubspec.yaml`, or pass a
one-off override to the workflow.

The build lands in App Store Connect the same way whether it is destined for
TestFlight or the App Store; the difference is only what you do with it after
processing (5–15 minutes). Internal testers get it immediately. The first build
you send to an *external* group goes through Beta App Review, which wants test
notes and a contact email filled in first. `ITSAppUsesNonExemptEncryption` is
declared in `Info.plist`, so builds are not held in "Missing Compliance";
revisit that declaration if the app ever adds non-standard cryptography.

TestFlight builds are signed for **production** APNs (Xcode swaps
`aps-environment` at export). Push that works in a debug build will still be
silent in TestFlight until the APNs auth key is uploaded to the Firebase
console and `IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64` is set.

The Firebase plist is gitignored, so it cannot be a permanent reference in the
Xcode project (a missing build input breaks the build for everyone without it).
CI decodes it from the secret and runs `ios/scripts/add_google_service_info.rb`
to attach it to the Runner target for that build. Locally, drag the plist into
the Runner group in Xcode once, with the Runner target ticked. Without it the
build still succeeds — Firebase push, Crashlytics, and Analytics just stay off,
silently, because `FirebaseBootstrap` swallows the initialization failure.

Signing settings (team, identity, profile) are passed to `xcodebuild` on the
command line instead of being committed to the Xcode project, so a developer's
Mac keeps working with automatic signing.

## Notes for release

- The iOS deployment target is **15.0** — the floor imposed by the Firebase
  plugins, which are linked through Swift Package Manager (there is no
  `Podfile`). Lowering it breaks package resolution.
- **Android release signing** is wired up but needs your keystore: create
  `android/key.properties` from `android/key.properties.example` and point it
  at your upload keystore (or set the `ANDROID_KEYSTORE_*` env vars in CI).
  Without it, release builds fall back to the debug key — fine for
  `flutter run --release`, but Play uploads require the real key.
- **iOS push** is wired: the `aps-environment` entitlement
  (`ios/Runner/Runner.entitlements`) and the `remote-notification` background
  mode are set, and `CODE_SIGN_ENTITLEMENTS` is applied to all Runner build
  configs. The entitlement ships as `development`; Xcode injects `production`
  for App Store / TestFlight distribution builds. To deliver pushes you still
  need to (1) add the app's APNs auth key to the Firebase console and
  (2) enable the **Push Notifications** capability on the App ID / provisioning
  profile in the Apple Developer portal.
- Microsoft Clarity session replay ships **on by default** in release builds;
  disclose it in the store privacy labels and verify PII masking against a real
  recording.
- Customer product analytics uses Firebase project `ebtl-37ddb`. It records
  PII-free screen and commerce events through `AnalyticsService`; customer
  names, phone numbers, addresses, and payment details must never be added to
  event parameters.
- Native Meta App Events uses Meta Developer App `1611789933929380` through
  the same `AnalyticsService` boundary. The App ID and Client Token are public
  native client configuration; the Meta App Secret must never be committed.
- The app does not currently show Apple's App Tracking Transparency prompt.
  Meta events still work, but iOS advertising-ID attribution remains subject
  to the device's system permission.
