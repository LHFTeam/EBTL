# AGENTS.md

Guidance for AI coding agents (and new contributors) working in this repository.

## What this app is

**EBTL customer app** — a Flutter app for a beach-side cocktail-kit service
("You bring the bottle. We bring the magic."). Customers pick a beach cart
(service location), browse cocktails and shop products, filter cocktails by
the liquor bottle they already own (the "Cocktail Finder"), customize a kit
(remove recipe items, add extras), add to cart, and check out with pickup or
delivery. There is **no customer login**: an anonymous session token is
created by the backend and stored on-device. Prices are in EGP.

The app is a thin client over the **customer API** of a separate backend
(`ebtl-admin-dashboard`, hosted on Render):

- Base URL: `https://ebtl-admin-dashboard.onrender.com` (hardcoded in
  `lib/core/network/api_config.dart` — there is no env/flavor switching).
- All endpoints live under `/api/customer/...` (session, home, cocktails,
  cocktail-finder/options, shop, cart, checkout, orders, favorites, spirits,
  profile).
- **There is no demo/offline fallback data.** Every screen loads from the
  backend; if it is unreachable the app shows `AppErrorScreen` with retry.
  Do not invent local mock data when fixing bugs — surface errors instead.

## Tech stack and constraints

- Flutter (Material 3), Dart SDK `^3.12.0`, stable channel. All platform
  folders exist (android/ios/web/linux/macos/windows) but the product targets
  mobile. The shipping platforms (Android/iOS, and web) use the real bundle
  ID `wtf.ebtl.app` and display name **EBTL**; the non-shipping desktop
  folders (linux/macos/windows) are still on the template `com.example.*`
  identity. Note the **Dart package name stays `ebtl_customer_app`** (the
  `name:` in `pubspec.yaml`, imported as `package:ebtl_customer_app/...`) —
  that is independent of the store bundle ID and is not renamed.
- Dependencies are deliberately lean. Core UI/networking: `http`,
  `google_fonts`, `flutter_secure_storage`, `flutter_markdown`, `flutter_svg`,
  `cupertino_icons`, `visibility_detector` (tells the Home hero carousel when
  it is off screen so it stops auto-rotating — see the note in
  `home_hero_carousel.dart` about why its callback must not be a tear-off).
  Payments: `flutter_stripe` (native Payment Sheet).
  Analytics/telemetry: `clarity_flutter` (session replay), `firebase_core` +
  `firebase_messaging` (push), `firebase_crashlytics` (crash/error reporting).
  The Firebase and Clarity integrations are **inert unless configured at build
  time** (see the service classes below), so the app still builds and runs
  without any of their credentials. **Do not add further packages** (state
  management, DI, routing, codegen, etc.) unless the task explicitly calls for
  it.
- **No state-management library and no code generation.** State is plain
  `StatefulWidget` + `FutureBuilder`, with data and callbacks passed down as
  constructor parameters. JSON mapping is hand-written. Keep it that way.
- Navigation is manual: `Navigator.push(MaterialPageRoute(...))` for detail
  flows; there is no named-route table.

## Commands

Run from the repo root:

```bash
flutter pub get          # install dependencies
flutter analyze          # lint / static analysis (flutter_lints defaults)
flutter test             # run widget tests
flutter run              # launch on a connected device/emulator
flutter build apk        # release Android build
```

Notes:

- Lints come from `package:flutter_lints/flutter.yaml` via
  `analysis_options.yaml` with no custom rules. `flutter analyze` must pass
  cleanly for any change.
- `flutter test` is green and **is** a regression baseline. The suite covers
  the app shell smoke test (`widget_test.dart`), JSON parsing
  (`notification_models_test.dart`), the checkout result states, the bottom
  nav's tab set and badge placement (`ebtl_bottom_nav_test.dart`), and the
  Explore hero/badges (`explore_widgets_test.dart`), the spirit-profile
  payloads (`spirit_models_test.dart`), and the Golden Hour launch modal's
  parsing and pill row (`golden_hour_test.dart`). Screens that call
  `ApiService` statics directly are not testable without a backend — test the
  widgets they compose instead, as those files do.
- Some CI/agent environments do not have the Flutter SDK installed. If
  `flutter` is unavailable, say so explicitly in your report instead of
  claiming analysis/tests passed.
- **Never put `GoogleFonts.manropeTextTheme()` in a test's `MaterialApp`.**
  Building the whole text theme kicks off a font load per style during paint,
  and under `flutter test` that deadlocks — the test hangs until the harness
  kills it with `Bad state: Cannot close sink while adding stream`, which
  reads like a tooling failure rather than the test's own scaffold. Give test
  harnesses a plain `ThemeData`; the letter spacing that affects layout comes
  from the default `Typography` either way. Individual `GoogleFonts.manrope(...)`
  calls inside widgets are fine. To render with the real fonts (golden tests),
  preload only the weights in play via `GoogleFonts.pendingFonts([...])` inside
  `tester.runAsync` before the first `pumpWidget`, serving the files through
  `GoogleFonts.config.httpClient`.

## Repository layout

```
lib/
  main.dart                 # EbtlApp (theme), AppStartupGate (onboarding gate),
                            # RootShell (bottom-nav tab host + cross-tab callbacks)
  core/
    constants/              # Asset path holders + FulfillmentTypes constants
    network/                # ApiConfig (base URL, endpoint builder), ApiException
    theme/                  # EbtlColors palette, shared TextStyles,
                            # HomeScreenVisuals (layout tuning knobs)
    utils/                  # json_helpers (defensive JSON readers), formatters
                            # (money/date), model_sorters, color_utils
  models/                   # Immutable API models with fromJson factories.
                            # app_data.dart aggregates the home + finder payloads.
  services/
    api_service.dart        # THE single backend gateway. Static methods only.
                            # Session/token/location persistence lives here too.
    firebase_bootstrap.dart # One-time Firebase init shared by push + crash.
    push_notification_service.dart  # FCM registration (inert without config).
    crash_reporting_service.dart    # Crashlytics + global uncaught-error hooks.
    clarity_service.dart    # Microsoft Clarity session replay (release-only).
  features/<feature>/       # One folder per screen/flow:
                            # home, explore, finder, shop, cocktail_detail,
                            # cart, checkout (includes OrderConfirmedScreen),
                            # profile (orders, favorites, spirits, edit sheet),
                            # onboarding
    .../widgets/            # Feature-private widgets, when split out
  shared/widgets/           # Reusable UI: loading/error/empty states, cards,
                            # bottom nav, NetworkOrAssetImage, ingredient icons,
                            # brand widgets, section blocks
assets/                     # images, ingredient SVGs, banners, onboarding,
                            # order-confirmation art, profile avatars, loader
test/                       # widget_test.dart (stale template — see above)
```

The Home tab is the **context-first redesign** (`features/home/home_screen.dart`
plus `features/home/widgets/`): a fixed header (beach-cart chip, notifications,
search) over modules whose order is resolved from the customer's state —
`HomeMode.liveOrder` (an order is being made) → `browsing` (cart open or orders
behind them) → `firstRun`. The live order and past orders come from
`RootShell.customerOrders`; everything else comes from the `AppData` payload.
The previous hero-banner Home is kept, disconnected and unimported, in
`features/home/legacy_home_screen.dart` (`LegacyHomeScreen`) — do not wire it
back in without being asked.

The hero carousel at the top of Home (`widgets/home_hero_carousel.dart`) draws
the centered slide full size with its neighbours at `1/1.3`, so a slide grows as
it arrives and shrinks as it leaves; with more than one slide it pages endlessly
in both directions and advances itself every `AppData.heroRotation` (the
dashboard's rotation setting, default 5 s, clamped to 2–60). A drag cancels the
timer and settling restarts it, so a customer who takes over gets a full
interval on whatever they land on; `MediaQuery.disableAnimations` stops
auto-rotation entirely. It also stops whenever it is off screen — behind a
pushed route or another tab, since `RootShell`'s `IndexedStack` keeps Home
mounted — via `VisibilityDetector`, and starts a fresh interval on return. It is **CMS-driven**: its slides come from `heroBanners`
on the `/home` payload
(image, headline, body, deep link, order), edited in the admin dashboard's
Marketing → Banners tab. Only the image and the order are required, so a slide
may carry no copy and no link; a slide without a deep link is not tappable, and
an empty list falls back to the three bundled slides in that file. Deep links
are the tokens `finder | explore | cart | orders | cocktail/<slug> |
category/<category id>`, parsed by `HeroBannerLink` and followed by
`RootShell.openHeroBanner`. Adding a destination means changing both that
parser and the validation in the backend's `bannerRoutes.js`.

### The Golden Hour launch modal

`features/home/widgets/golden_hour_modal.dart` is the card the app opens with
when the customer **already has a beach cart chosen** — that condition is the
whole point, since the card's one action is Add to Cart and the cart needs a
location. `RootShell._maybeShowGoldenHour` opens it from a post-frame callback
after the first `loadAppData` of a launch, so it lands over a painted Home
rather than the loading scaffold.

Three things about it are easy to get wrong:

- **It is once per launch, not once per load.** `_goldenHourHandled` is set on
  the first load whether or not a card was shown. Every later load — a cart
  change, a location switch, a pull to refresh — runs the same code path, and
  without the flag each would reopen the card.
- **The app does not decide which mode shows.** The backend resolves the four
  time-of-day modes against **Cairo** local time and hands over at most one,
  already picked, on `AppData.goldenHour`. Never re-derive that from the device
  clock, which may be set anywhere in the world.
- **Add to Cart loads the cocktail first.** The card carries a slug, not a
  variant, so it fetches the detail and then adds — the same route Home's
  "Order It Again" takes — which is what makes it add at today's price and
  availability for this beach cart.

Pill colours live in the app (`GoldenHourPillScheme.palette` in
`models/golden_hour_models.dart`) and the payload carries only scheme keys, so
a key this version does not know falls back to `sand` at paint time rather than
dropping the pill. Adding a scheme means changing both the palette here and
`GOLDEN_HOUR_PILL_SCHEMES` in the backend's `lib/goldenHour.js`. Everything
else on the card — copy, image, cocktail, the pills after the first — is edited
in the dashboard's Marketing → Golden Hour tab.

Customer notifications and push are now **implemented** (they were once staged
in a since-removed `*.patch` file and have since been built directly into the
tree):

- In-app notifications: `features/profile/customer_notifications_screen.dart` +
  `models/notification_models.dart`, backed by
  `ApiService.fetchCustomerNotifications`. `RootShell` polls unread count every
  30 s (paused in background) and shows a snackbar + profile-tab dot on new
  ones.
- Push (FCM): `services/push_notification_service.dart` registers the device
  token via `ApiService.registerCustomerPushToken`. Android is wired
  (`google-services.json` materialized in `android/app/build.gradle.kts`); iOS
  still needs an APNs entitlement + `remote-notification` background mode
  before push delivers there.

## Runtime architecture

### Startup and navigation

1. `main()` → `EbtlApp` builds the `MaterialApp` theme (Material 3, Manrope
   font via `google_fonts`, `EbtlColors.cream` scaffold background).
2. `AppStartupGate` checks `ApiService.hasCompletedOnboarding()` (secure
   storage flag `onboarding_completed_v1`) and shows `OnboardingScreen` on
   first launch, else `RootShell`.
3. `RootShell` owns `appDataFuture = ApiService.fetchAppData()` and the
   bottom-nav index. Tabs (fixed order): **0 Home, 1 Explore, 2 Cart,
   3 Profile** — declared once as `EbtlBottomNav.homeIndex` /
   `.exploreIndex` / `.cartIndex` / `.profileIndex`. **Use those constants,
   never bare indices**: the nav positions its cart-count badge and profile
   unread dot by index, so a literal that drifts lands the badge on the wrong
   icon. Detail screens (cocktail detail, checkout) and the **Cocktail
   Finder** — which has no tab of its own; `RootShell.openFinder()` pushes it,
   usually from the Explore hero — go on top with `Navigator.push`.
   `ShopScreen` still exists but is no longer wired into the nav; Explore
   replaced it.

### Data flow pattern (follow it for new screens)

- A screen's `State` creates a `Future<...>` in `initState` by calling a
  static `ApiService` method, renders it with `FutureBuilder`, and exposes a
  `reload()` that re-assigns the future inside `setState`.
- Loading → `theLoadingScaffold()` / `EbtlLoadingSection`; error →
  `AppErrorScreen` or `InlineErrorCard` with a retry callback; empty →
  `EmptyStateCard`. Reuse these from `shared/widgets/app_state_widgets.dart`.
- Cross-screen updates are propagated by **callbacks passed down from
  `RootShell`** (`onCartChanged`, `onOpenCart`, `onOpenFinder`,
  `onBottomNavTap`, `reloadAppData`). There is no global store — when a
  mutation elsewhere must refresh home/cart badges, call the provided
  `onCartChanged`/`reloadAppData` callback rather than adding new state
  machinery.
- Shop products reuse the cocktail detail screen via the
  `Cocktail.fromShopProduct(...)` bridge factory.

### ApiService rules

`lib/services/api_service.dart` is the only place HTTP happens. When adding
an endpoint, copy the existing shape:

- `static Future<SomeResponse> fetchX(...)` → `await ensureSession();` first,
  then `_request(method:, path:, query:, body:, attachToken:)`, then
  `SomeResponse.fromJson(json)`.
- `_request` handles: JSON headers, bearer token attachment, timeouts,
  wrapping every failure in `ApiException` (message + endpoint + status +
  `blocking_reasons`/`details` from the error body), decoding, and **session
  token refresh** — it persists any `x-ebtl-customer-token` response header
  and any top-level `session` object automatically. Don't bypass it.
- Query params: pass nullable strings; `ApiConfig.endpoint` drops null/empty
  values. Path params must go through `Uri.encodeComponent`.
- Timeouts: 45 s default, 90 s for `POST /api/customer/session` — the Render
  backend cold-starts, and the timeout error message tells the user so. Keep
  that behavior.
- Persistence is all `flutter_secure_storage` via ApiService statics:
  session token, customer id, selected location id/name, onboarding flag.
  Add new keys as `static const _fooKey = '...'` alongside the others.
- Quantities are clamped client-side (`1–99` on add, `0–99` on update).

### Model conventions

- Models are immutable: `final` fields, `const` constructor with `required`
  named parameters, plus a `factory X.fromJson(Map<String, dynamic> json)`.
- **Never index raw JSON directly.** Always go through
  `lib/core/utils/json_helpers.dart`: `readString` (with `fallback:`),
  `nullableString`, `readInt`, `readDouble`, `readBool`, `asMap`,
  `readMapList`, `readStringList`. The backend payload is treated as
  untrusted — every field needs a safe default so the UI never crashes on a
  missing/mistyped key.
- Backend JSON keys are `snake_case` (occasionally camelCase on the home
  payload, e.g. `featuredCocktails`) → Dart fields are `lowerCamelCase`.
- Display-oriented helpers (e.g. `priceLabel`, `usingLabel`, `subtitle`)
  live as getters on the model, using `formatters.dart` (`formatMoney`
  prints `EGP 120` / `EGP 120.50`).
- Sorting by `display_order` then name goes through
  `core/utils/model_sorters.dart` — extend that file for new sortable types.

### UI conventions

- Colors come only from `EbtlColors` (navy/coral/cream/sand/seafoam/teal/
  gold/blush/ink/muted/border/white). No ad-hoc `Color(0x...)` in screens.
- Fonts: Manrope via `GoogleFonts.manrope(...)`; shared text styles live in
  `core/theme/ebtl_text_styles.dart` (add there rather than duplicating).
- Home-screen layout tuning constants (card sizes, font sizes, visibility
  toggles) live in `core/theme/home_screen_visuals.dart` — change numbers
  there, not inline.
- Screens are single files with the public `XScreen` widget on top and the
  supporting widget classes below it in the same file (private `_Foo` when
  purely internal). Split into `features/<x>/widgets/` only when a file gets
  unwieldy — several features already do this. Some files are large
  (`checkout_screen.dart` ≈ 2400 lines includes the whole order-confirmed
  flow); prefer following the local structure over refactoring en masse.
- Images: use `NetworkOrAssetImage` (network URL if present, else bundled
  asset, else gradient fallback). Cocktail fallback art is name-matched in
  `CocktailAssets.forName`. Ingredient icons: `IngredientSvgIcon` resolves
  backend `icon_key` → `assets/icons/ingredients/<key>.svg` with validation
  and graceful fallback.
- New asset **folders** must be registered under `flutter/assets:` in
  `pubspec.yaml` (individual files inside registered folders are picked up
  automatically, but subfolders are not).
- User-visible copy is inline English strings; there is no i18n layer.

## Domain glossary

- **ServiceLocation / beach cart** — a physical serving location; the chosen
  one is stored locally and its `location_id` is sent on every request where
  product availability matters.
- **Fulfillment types** — `pickup_at_cart` and `delivery_to_unit`, defined in
  `core/constants/fulfillment_types.dart` (labels/helpers included). Use the
  constants, never raw strings.
- **Cocktail Finder** — filter cocktails by owned liquor bottle
  (`liquor_type_ids`), tags, category, search text.
- **Customization** — cart items carry `removed_recipe_item_ids` and
  `additions` (see `addCocktailToCart`).
- **Payment methods** — provided by the backend per checkout. The default
  provider is **Stripe**: `checkout_screen.dart` presents the native
  `flutter_stripe` Payment Sheet, then reconciles via webhook-backed polling
  (`fetchOrderPaymentStatus`). The older **Geidea** path
  (`startGeideaSdkAndRefresh`) is still a placeholder dialog — no real SDK — so
  keep the backend pinned to Stripe unless that path is finished.
  `demo_checkout` bypasses payment entirely. Orders carry an `idempotency_key`
  on placement. See root `STRIPE_SETUP.md` for the backend/webhook contract.
  Dismissing the Payment Sheet is a no-op: the cart is only emptied server-side
  once payment succeeds, so `onCartChanged` must not fire until the poll
  reports the order paid, and a retry replays the same `idempotency_key`. The
  backend expires an unpaid order after 30 minutes and cancels its payment
  intent; place-order then answers 409 with `ApiException.errorCode ==
  'checkout_expired'`, which `placeOrder` handles by reloading checkout so the
  next attempt starts from a fresh key.
- **Favorites** — per-anonymous-customer favorite cocktails
  (`/api/customer/favorites`), surfaced on profile and cocktail cards.
- **Spirits** — the customer's bottles, as two lists on the profile
  (`/api/customer/spirits`, `models/spirit_models.dart`,
  `features/profile/favorite_spirits_screen.dart`). *My Spirits* is curated by
  the customer (add/remove); *Most Ordered* is computed backend-side from their
  order history on every order confirmation and is read-only here. Both come
  down inside the profile payload too, so the profile screen renders them
  without a second request. Mutations answer with the whole spirits payload —
  render the response rather than patching local state.

## Working agreements for agents

1. **Match the existing style.** Plain Flutter, callbacks over state
   libraries, hand-written `fromJson` with json_helpers, `EbtlColors` +
   Manrope. A change that introduces a new architectural pattern needs an
   explicit request.
2. **Run `flutter analyze` before committing** (and `flutter test` when tests
   exist for what you touched). Report honestly if the SDK is unavailable.
3. **Don't touch** `pubspec.lock` (unless changing dependencies),
   `.metadata`, or generated platform template files unless the task is
   specifically about them.
4. Backend contract changes originate in the admin-dashboard repo — this app
   only consumes `/api/customer/*`. If a task implies a backend change,
   flag it instead of faking the data client-side.
5. Error handling: throw/propagate `ApiException`; let screens render it via
   the shared error widgets. Don't swallow errors or print to console
   (`avoid_print` lint is active).
6. Keep diffs minimal and scoped; the codebase favors readable, explicit
   Flutter code over abstraction.
