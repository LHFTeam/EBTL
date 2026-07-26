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
| `--dart-define=ANALYTICS_ENABLE_DEBUG=true` | Enables Firebase Analytics during a debug validation run | Disabled in debug |
| `google-services.json` / `GoogleService-Info.plist` | Enables Firebase push, Crashlytics, and Analytics | Firebase integrations disabled |

Payments use Stripe's native Payment Sheet; the backend delivers the
per-checkout Stripe keys. See the root [`STRIPE_SETUP.md`](../STRIPE_SETUP.md).

## Notes for release

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
