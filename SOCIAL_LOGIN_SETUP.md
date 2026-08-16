# Social sign-in setup (EBTL)

The customer app offers **Facebook, Google and Apple sign-in** on the order
confirmation screen. The code is merged and the database is migrated; what
remains is credentials and provider-console configuration.

Nothing here blocks ordering. Sign-in is optional everywhere — a customer who
ignores it keeps the anonymous session the app has always used, and every screen
works without it. The only risk of shipping unconfigured is a **visible dead
button** (see [Ship-blocker](#ship-blocker-read-this-first)).

```
customer-app (Flutter)                     admin-dashboard (Express + Supabase)
──────────────────────                     ────────────────────────────────────
tap "Continue with X"
provider SDK returns a token ─────────────▶ POST /api/customer/auth/social
                                            verify token with the provider
                                            link identity to the customer row
stores the new session token ◀───────────── { session, customer, is_new_customer }
```

## Status

| | |
|---|---|
| ✅ Database | Migration `customer_social_identities` applied to **EBTL 1** (`pfcncajijvtvsdwgwbjl`) on 2026-08-16. `facebook_user_id`, `google_user_id`, `apple_user_id` on `public.customers`, each with a partial unique index. Nothing more to do. |
| ✅ App + backend code | Merged in [#129](https://github.com/LHFTeam/EBTL/pull/129). |
| ✅ Native config in repo | Facebook activities in the Android manifest, `LSApplicationQueriesSchemes` and the Sign in with Apple entitlement on iOS. |
| ⬜ **Facebook** | Needs §1 — app secret, console setup, key hashes, data-deletion URL. |
| ⬜ **Apple** | Needs §2 — capability on the App ID, then regenerate provisioning profiles. |
| ⬜ **Google** | Needs §3 — OAuth clients. Optional; the button hides itself until then. |

---

## Ship-blocker (read this first)

**Google and Apple hide their own buttons when unconfigured. Facebook does not.**

The app can tell whether *it* has a Google client ID, and whether it is on iOS
for Apple — so those buttons simply do not render. It cannot tell whether the
**server** has Facebook credentials, so the Facebook button always renders. On a
deployment without `FACEBOOK_APP_ID` and `FACEBOOK_APP_SECRET`, tapping it runs
the whole Facebook flow and then shows an error snackbar from a 503.

So before a build reaches customers, either finish §1, or ask for the Facebook
button to be gated the same way Google's is (a small change in
`customer-app/lib/features/auth/social_sign_in_card.dart`).

---

## 1. Facebook — required

Uses the **existing** Meta Developer App `1611789933929380`, already used for App
Events. Do not create a second app; the App ID and Client Token are already
embedded in the Android and iOS builds.

### 1a. Backend environment

| Variable | Value | Where to get it |
|---|---|---|
| `FACEBOOK_APP_ID` | `1611789933929380` | Already known |
| `FACEBOOK_APP_SECRET` | *(secret)* | Meta dashboard → **App settings → Basic → App secret → Show** |

The secret is **server-only**. It is used solely to build the app access token
that Meta's `/debug_token` endpoint requires when verifying a classic Facebook
login. It must never be shipped in the app or committed.

Set both in the Render dashboard for `ebtl-admin-dashboard` (and in your local
`admin-dashboard/.env` for development). See §4.

### 1b. Add the Facebook Login product

Meta dashboard → **Products → add "Facebook Login"**. App Events alone does not
enable it.

### 1c. Register the platforms

**App settings → Basic → Add Platform.**

- **iOS** — Bundle ID `wtf.ebtl.app`.
- **Android** — Package name `wtf.ebtl.app`, default activity class
  `wtf.ebtl.app.MainActivity`, plus **key hashes**.

Android key hashes are mandatory — Facebook rejects logins from an APK whose
signing key it does not recognise, with a generic failure that looks like a code
bug. Add one for every key that signs a build customers or testers will run.

```bash
# Debug key (local `flutter run` builds). Password is: android
keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore \
  | openssl sha1 -binary | openssl base64

# Upload key (Play Store builds). Alias and passwords come from
# customer-app/android/key.properties
keytool -exportcert -alias <keyAlias> -keystore <storeFile> \
  | openssl sha1 -binary | openssl base64
```

If the app ships through **Play App Signing**, Google re-signs the APK, so also
add the hash of Google's app-signing certificate: Play Console → your app →
**Setup → App integrity → App signing key certificate**, take the SHA-1, and
convert it:

```bash
echo <SHA1_WITH_COLONS> | xxd -r -p | openssl base64
```

Without that last one, Facebook login works in testing and fails only in
production — the most expensive way to find out.

### 1d. Data deletion URL

Meta requires this before Facebook Login passes App Review. The page is already
built and deployed at `admin-dashboard/public/data-deletion.html`.

Meta dashboard → **App settings → Basic → Data Deletion Instructions URL**:

```
https://ebtl-admin-dashboard.onrender.com/data-deletion.html
```

Open it once in a browser first to confirm it serves — it is only reachable on a
deploy that has run `npm run build`.

Check the contact address on that page is one you actually monitor. It currently
says `hello@ebtl.wtf`.

### 1e. Permissions and App Review

The app requests `public_profile` and `email`. Both work immediately for anyone
listed as an **admin, developer or tester** on the Meta app, so you can test
without review. Serving the public requires **Advanced Access** for both, which
means submitting the app for review — allow time for that before launch.

---

## 2. Apple — required for iOS

The entitlement is already in both `Runner.entitlements` and
`RunnerRelease.entitlements`. What is missing is the matching capability on the
App ID, without which the sheet fails at runtime with error 1000.

1. [developer.apple.com](https://developer.apple.com) → **Certificates,
   Identifiers & Profiles → Identifiers →** `wtf.ebtl.app`.
2. Tick **Sign in with Apple**, save.
3. **Regenerate the provisioning profiles** for that App ID and re-download them
   in Xcode. An existing profile does not pick up a new capability, and the build
   will keep failing until it is replaced.

No backend variable is needed. `APPLE_BUNDLE_IDS` defaults to `wtf.ebtl.app`;
set it only if a second bundle ID ever ships against this backend.

**Guideline 4.8.** Apple requires an equivalent privacy-preserving login option
once a third-party social service authenticates the primary account. Sign in with
Apple satisfies it — which means shipping Facebook login on iOS *without* this
step risks App Review rejection, not just a broken button.

---

## 3. Google — optional

The Google button stays hidden until the app is built with a client ID, so this
can be done later without affecting anything. Facebook and Apple work without it.

The Firebase project is **`ebtl-37ddb`** (project number `827280005790`), and its
`google-services.json` currently has an empty `oauth_client` array — no OAuth
client exists yet.

### 3a. Create the OAuth clients

Google Cloud Console → project `ebtl-37ddb` → **APIs & Services → Credentials**.
You need three:

| Client type | Needs | Used by |
|---|---|---|
| **iOS** | Bundle ID `wtf.ebtl.app` | The app on iOS |
| **Android** | Package `wtf.ebtl.app` + SHA-1 of each signing key | The app on Android |
| **Web** | — | The `id_token` audience the backend verifies |

The Android SHA-1 is a *different format* from the Facebook key hash above —
same certificate, different encoding:

```bash
keytool -list -v -alias <keyAlias> -keystore <storeFile> | grep SHA1
```

Include the Play App Signing SHA-1 too, for the same reason as §1c.

### 3b. Refresh `google-services.json`

Re-download it from Firebase after creating the Android client — it will now
contain `oauth_client` entries. Place it at **`customer-app/google-services.json`**
(the Gradle build copies it into `android/app/` from there; see
`customer-app/android/app/build.gradle.kts`). For CI, supply it base64-encoded as
`GOOGLE_SERVICES_JSON_BASE64` instead.

> There is an existing `google-services.json` at the **repo root**, which is not
> where Gradle's fallback looks (`rootProject.file("../google-services.json")`
> resolves to `customer-app/`). It predates this work and only affects Firebase
> push, but do not mistake it for the file this step wants — put the new one in
> `customer-app/`.

### 3c. iOS URL scheme

Add the **reversed iOS client ID** as a third `CFBundleURLTypes` entry in
`customer-app/ios/Runner/Info.plist`. There is a comment marking the spot.

```xml
<dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>google</string>
    <key>CFBundleURLSchemes</key>
    <array>
        <string>com.googleusercontent.apps.827280005790-XXXXXXXX</string>
    </array>
</dict>
```

### 3d. Backend and build flags

Backend — every client ID that may appear in an `id_token` audience, comma
separated:

```
GOOGLE_CLIENT_IDS=<web-client-id>,<ios-client-id>,<android-client-id>
```

App — passed at build time, which is what makes the button appear:

```bash
flutter build appbundle \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id> \
  --dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>
```

`GOOGLE_SERVER_CLIENT_ID` is the **web** client ID on both platforms — it is the
audience the backend checks, not the platform client. Getting this wrong is the
usual cause of "works on device, 401 from the server".

Add these to whatever builds your release artifacts, or the button will be
present locally and absent in the store build.

---

## 4. Where to set the backend variables

Production is Render (`ebtl-admin-dashboard`, defined in `render.yaml`).

**Render dashboard → the service → Environment → Add environment variable.** The
service redeploys automatically.

```
FACEBOOK_APP_ID=1611789933929380
FACEBOOK_APP_SECRET=<from Meta>
GOOGLE_CLIENT_IDS=                 # leave blank until §3
APPLE_BUNDLE_IDS=wtf.ebtl.app      # optional; this is the default
```

For local development put the same keys in `admin-dashboard/.env` — they are
documented at the bottom of `admin-dashboard/.env.example`.

Each provider is independently optional in the config: leaving a block blank
rejects that provider's tokens with a clear 503 rather than breaking the
endpoint or the app.

---

## 5. Verifying it works

Test on a **real device**. The Facebook flow cannot be exercised properly in a
simulator without the Facebook app installed.

1. Place an order and reach the confirmation screen. The sign-in card is below
   the receipt.
2. Tap **Continue with Facebook**, authorise, and expect the card to collapse to
   a teal "Saved to {your name}" strip.
3. Confirm the link landed:

   ```sql
   select id, full_name, email, facebook_user_id, google_user_id, apple_user_id
   from public.customers
   where facebook_user_id is not null
      or google_user_id is not null
      or apple_user_id is not null;
   ```

4. **The real test:** delete and reinstall the app, sign in with the same
   provider, and open Profile → Orders. The earlier order should be there. That
   is the whole point of the feature — everything before it only proves the
   button is wired up.
5. Repeat for Apple on iOS, and Google once §3 is done.

---

## 6. If something fails

The app surfaces the backend's message in a snackbar, so the text below is what
the customer sees.

| Symptom | Cause | Fix |
|---|---|---|
| "Facebook sign-in is not configured on this server." | `FACEBOOK_APP_ID`/`FACEBOOK_APP_SECRET` unset | §1a |
| "Sign-in is not available yet." (503) | Provider columns missing from `customers` | Already applied — if you see this, check you are pointed at the right Supabase project |
| "This Facebook sign-in was not issued for EBTL." | Token from a different Meta app | Check the app is built against `1611789933929380` |
| Facebook login fails only on a signed/store build | Missing key hash for that signing key | §1c, including Play App Signing |
| "Could not verify this google sign-in." | Wrong audience — usually the platform client ID sent instead of the web one | §3d |
| Apple sheet fails with error 1000 | Capability not enabled, or a stale provisioning profile | §2, and regenerate profiles |
| "Another EBTL account already uses that email address." | Two customer rows, one already holds that email | Expected. The two rows need merging by hand |
| Google button missing entirely | No `GOOGLE_SERVER_CLIENT_ID` at build time | §3d — this is deliberate, not a bug |

Backend errors are logged to the Render service log; look for
`verifySocialToken failed` or `linkSocialIdentity failed`.

---

## 7. What is deliberately not done

- **Loyalty points** are advertised on the sign-in card as a live benefit, but
  nothing awards them yet. The `loyalty_accounts` and `loyalty_transactions`
  tables exist with no endpoint behind them. The copy is one string in
  `social_sign_in_card.dart` if you want to soften it before launch.
- **No account merging UI.** If one person ends up with two customer rows —
  ordering anonymously on two devices, then signing in on both — the second
  sign-in moves the session to the row the identity matched. Nothing combines the
  orders. Rare, and fixable by hand in Supabase.
- **No sign-out of a social identity.** The Profile screen's "Log Out" clears the
  local session token, as it always has; it does not unlink the provider. Signing
  in again on the same device returns the same account.
