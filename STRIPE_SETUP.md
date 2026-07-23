# Stripe payments setup (EBTL)

This repo now supports **Stripe** as a checkout provider alongside the existing
Geidea integration, selected with a single env flag. The mobile app presents
Stripe's **native Payment Sheet** (cards, and Apple/Google Pay once configured),
and orders are confirmed by a signed Stripe webhook — the same
session → gateway → webhook → poll flow the Geidea path uses.

```
customer-app (Flutter)                 admin-dashboard (Express + Supabase)
──────────────────────                 ────────────────────────────────────
place order ─────────────────────────▶ create PaymentIntent + ephemeral key
present Payment Sheet (client_secret) ◀ returns stripe{} block
confirm on Stripe ──────────────────▶  Stripe
poll /payment-status  ◀── webhook ◀──  /api/payments/stripe/webhook (marks paid)
```

## 1. Backend env (`admin-dashboard/.env`)

```
PAYMENT_MODE=live
PAYMENT_PROVIDER=stripe          # flip to `geidea` to switch back instantly
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...  # from the webhook you create in step 2
STRIPE_API_VERSION=2024-06-20    # must match the flutter_stripe SDK's version
STRIPE_MERCHANT_DISPLAY_NAME=EBTL
STRIPE_MERCHANT_COUNTRY=US
STRIPE_APPLE_PAY_MERCHANT_ID=    # leave blank until Apple Pay is set up
STRIPE_GOOGLE_PAY_ENABLED=false  # set true once the Android app is configured
```

Secrets stay server-only (delivered to the app per-checkout). Set the same
values in the Render dashboard for the deployed backend. In particular, remove
or replace any existing `PAYMENT_MODE=demo`; demo mode always bypasses Stripe.

## 2. Create the webhook in the Stripe Dashboard

- Endpoint URL: `https://ebtl-admin-dashboard.onrender.com/api/payments/stripe/webhook`
- Events to send: `payment_intent.succeeded` and `payment_intent.payment_failed`
- Copy the signing secret (`whsec_...`) into `STRIPE_WEBHOOK_SECRET`.

The webhook route receives the **raw** request body (wired in `server/app.js`)
so the signature can be verified in `server/lib/stripe.js`.

## 3. Currency ⚠️

The app charges in **EGP**. Confirm in **test mode** that the US Stripe account
accepts EGP as a charge currency (make a real test PaymentIntent). If Stripe
rejects EGP, switch the charge currency to USD (the amount is converted to minor
units in `server/lib/stripe.js` → `stripeMinorUnits`).

## 4. Flutter app

`flutter_stripe` is already added to `pubspec.yaml`. Run:

```bash
cd customer-app
flutter pub get
cd ios && pod install && cd ..   # macOS only
flutter run
```

Native config already applied in this repo:

- **Android** — `MainActivity` extends `FlutterFragmentActivity`; `NormalTheme`
  is a MaterialComponents theme; `minSdk` is pinned to ≥ 21.
- **iOS** — deployment target is already 13.0 (meets the SDK minimum).

The publishable key is delivered by the backend at checkout, so no key is
compiled into the app.

## 5. Wallets (optional, when ready)

- **Apple Pay** — register an Apple Merchant ID, enable the Apple Pay capability
  in Xcode, add it in the Stripe Dashboard, then set `STRIPE_APPLE_PAY_MERCHANT_ID`.
- **Google Pay** — set `STRIPE_GOOGLE_PAY_ENABLED=true` once the Android app is
  ready. Both surface automatically inside the Payment Sheet.

## 6. Test

Use Stripe test cards, e.g. `4242 4242 4242 4242` (any future expiry / CVC), and
`4000 0000 0000 3220` for the 3-D Secure challenge flow. Watch the order flip to
`paid`/`confirmed` after the webhook is processed.

## Rollback

Set `PAYMENT_PROVIDER=geidea` (or `PAYMENT_MODE=demo`) and redeploy. No code
change or migration is required — the Geidea path is untouched.
