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
  cocktail-finder/options, shop, cart, checkout, orders, favorites, profile).
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
- Dependencies are deliberately minimal: `http`, `google_fonts`,
  `flutter_secure_storage`, `flutter_markdown`, `flutter_svg`,
  `cupertino_icons`. **Do not add packages** (state management, DI, routing,
  codegen, etc.) unless the task explicitly calls for it.
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
- `test/widget_test.dart` is the **stale Flutter template counter test** and
  does not reflect the app (it pumps an empty `Scaffold` and expects a
  counter). It fails as written. Do not treat it as a regression baseline;
  if you touch tests, replace it with something meaningful rather than
  patching it to keep failing template assertions.
- Some CI/agent environments do not have the Flutter SDK installed. If
  `flutter` is unavailable, say so explicitly in your report instead of
  claiming analysis/tests passed.

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
  features/<feature>/       # One folder per screen/flow:
                            # home, finder, shop, cocktail_detail, cart,
                            # checkout (includes OrderConfirmedScreen),
                            # profile (orders, favorites, edit sheet), onboarding
    .../widgets/            # Feature-private widgets, when split out
  shared/widgets/           # Reusable UI: loading/error/empty states, cards,
                            # bottom nav, NetworkOrAssetImage, ingredient icons,
                            # brand widgets, section blocks
assets/                     # images, ingredient SVGs, banners, onboarding,
                            # order-confirmation art, profile avatars, loader
test/                       # widget_test.dart (stale template — see above)
```

The root `*.patch` files that used to live here
(`ebtl_app_demo_order_confirmed_notifications.patch`,
`ebtl_customer_app_customization_update.patch`) were stale artifacts and have
been removed: the customization patch's changes were already applied to the
code, and the notifications patch (customer notifications screen + push
service) was never applied — no notification/push code exists in `lib/`. If
that feature is wanted, implement it fresh against the current code rather
than resurrecting the patch from git history.

## Runtime architecture

### Startup and navigation

1. `main()` → `EbtlApp` builds the `MaterialApp` theme (Material 3, Manrope
   font via `google_fonts`, `EbtlColors.cream` scaffold background).
2. `AppStartupGate` checks `ApiService.hasCompletedOnboarding()` (secure
   storage flag `onboarding_completed_v1`) and shows `OnboardingScreen` on
   first launch, else `RootShell`.
3. `RootShell` owns `appDataFuture = ApiService.fetchAppData()` and the
   bottom-nav index. Tabs (fixed order): **0 Home, 1 Cocktail Finder,
   2 Shop, 3 Cart, 4 Profile**. Detail screens (cocktail detail, checkout)
   are pushed on top with `Navigator.push`.

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
- **Payment methods** — provided by the backend per checkout; known keys are
  `geidea_card` (card session + payment-status polling in
  `checkout_screen.dart`) and `demo_checkout`. Orders use an
  `idempotency_key` on placement; payment status is polled via
  `fetchOrderPaymentStatus`.
- **Favorites** — per-anonymous-customer favorite cocktails
  (`/api/customer/favorites`), surfaced on profile and cocktail cards.

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
