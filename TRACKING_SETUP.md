# EBTL customer tracking setup

This document is the operational source of truth for public/customer tracking.
Employee login, dashboard, admin, and prep screens are intentionally excluded.

## Architecture

| Surface | Integration |
| --- | --- |
| Public landing page (`admin-dashboard/public/landing.html`) | Web GTM container |
| Customer Android/iOS app | Firebase Analytics + Meta App Events + Microsoft Clarity |
| Employee React SPA | None |

No server-side GTM container, Conversions API gateway, additional service, or
new deployment instance is required. The existing Express app exposes the
public GTM container ID from `GET /api/public-config`.

## Production identifiers

| System | Identifier |
| --- | --- |
| Web GTM container | `GTM-WN6DZGBS` |
| Landing GA4 web stream | `G-Z4SQ6235CJ` |
| Landing Microsoft Clarity project | `xsjp56x4va` |
| Landing Meta Pixel / dataset | `1581863720182872` |
| Customer Firebase project | `ebtl-37ddb` |
| Customer Microsoft Clarity project | `xr1vveuqim` |
| Customer Meta Developer App | `1611789933929380` |

These identifiers are public client configuration, not server credentials.
Never add a Meta App Secret, Firebase service-account key, Supabase key, or
other private credential to this file.

## GTM container configuration

The repository loads `GTM-WN6DZGBS` only on the production landing page. A
ready-to-import container export is available at:

`admin-dashboard/gtm/ebtl-landing-gtm-container.json`

In GTM, open **Admin > Import Container**, choose the JSON file, create a new
workspace, and select **Merge > Overwrite conflicting tags, triggers, and
variables**. Review the detailed changes and use Preview before publishing.

The import creates the following tags in that **Web** container:

1. **Google tag — EBTL landing**
   - Tag ID: `G-Z4SQ6235CJ`
   - Trigger: Initialization — All Pages
   - Keep automatic page-view measurement enabled.
2. **Microsoft Clarity — EBTL landing**
   - Uses Microsoft's standard Clarity loader in a portable Custom HTML tag.
   - Project ID: `xsjp56x4va`
   - Trigger: All Pages.
3. **Meta Pixel — EBTL landing**
   - Pixel/dataset ID: `1581863720182872`
   - Fire the base `PageView` tag on All Pages.
4. **GA4 event tags**
   - Forward the custom data-layer events in the table below to the Google tag.
5. **Meta event tags**
   - Forward `app_download_click` as Meta custom event `AppDownloadClick`.
   - Forward `cta_click` as Meta custom event `CTAClick`.

Later, add Snapchat to this same container and reuse the existing data-layer
events. Do not add another vendor loader to `landing.html` or `tracking.js`.

### Landing data layer

| Event | Parameters |
| --- | --- |
| `landing_page_ready` | `page_type` |
| `app_download_click` | `link_destination`, `placement` |
| `cta_click` | `cta_label`, `placement` |
| `scroll_depth` | `percent_scrolled` |

The download links still use `APP_LINK_PLACEHOLDER`. Replace both occurrences
with the final App Store, Google Play, or smart-link URL before measuring
download conversions.

## Customer app events

Firebase Analytics, Meta App Events, and Clarity share the provider-neutral
`customer-app/lib/services/analytics_service.dart` boundary.

| Event | When it fires |
| --- | --- |
| `screen_view` | Customer bottom tabs and funnel screens |
| `tutorial_complete` | Onboarding completion |
| `select_location` | A beach-cart location is selected; `method` distinguishes `manual` from `auto_nearest` |
| `view_item` | Cocktail or shop-product detail is viewed |
| `search_submitted` | Cocktail Finder search is submitted; query text is not sent |
| `add_to_wishlist` / `remove_from_wishlist` | Favorite status changes |
| `add_to_cart` | A successful cart addition |
| `select_promotion` | A merchandising banner is tapped |
| `finder_bottle_selected` / `finder_bottle_deselected` | A bottle is added to or removed from the Cocktail Finder's filter |
| `begin_checkout` | Checkout data first loads |
| `purchase` | Backend-confirmed paid order only |

Commerce values use EGP as delivered by the API. Purchase events use the order
ID as the GA4 transaction ID and are deduplicated within the running app.

### Product name and category

`view_item` and `add_to_cart` carry the product in the GA4 `items` array, so
both break down by **Item name** and **Item category** in the standard
ecommerce reports with no custom dimension to register. Category is the
product's catalog category, falling back to its product type (and to
`cocktail` for a cocktail with no category set).

### Where the view or the add came from

Both events also carry a `source` — the surface the customer was on — and a
`source_detail` naming the instance of it. `source` is repeated as the item's
`item_list_name`, so it reads in the ecommerce reports as well as in the event
parameters.

| `source` | `source_detail` |
| --- | --- |
| `home` | — |
| `home_hero_banner` | Banner headline |
| `spotlight_banner` | Banner title |
| `golden_hour` | Card title |
| `order_again` | — |
| `recently_viewed` | — |
| `explore`, `shop`, `favorites` | — |
| `shop_category` | Category name |
| `catalog_search` | — |
| `cocktail_finder` | The selected bottle, when exactly one is selected |
| `related_cocktail` | The slug of the cocktail hopped from |

Register `source` and `source_detail` as **event-scoped custom dimensions** in
GA4 (Admin → Custom definitions) before they appear in exploration reports;
they are collected either way and are in BigQuery from the first event.

### Banner clicks

`select_promotion` carries `promotion_name` (what marketing called the banner),
`promotion_id`, `creative_slot`, and `banner_destination` (the deep link or
sheet it opened). The slot separates the three banner surfaces:

| `creative_slot` | Surface | `promotion_id` |
| --- | --- | --- |
| `home_hero_carousel` | Home hero slide with a deep link | Banner id |
| `home_spotlight_rail` | "The Spotlight" rail card | Banner id |
| `golden_hour_modal` | Golden Hour card's cocktail action | Window mode (`sunset`), not the dated occurrence key |

A hero slide may ship artwork with no headline; those report under the banner
id, and untappable slides fire nothing at all. Whatever the banner opens is
attributed with the matching `source`, so a click and the sale behind it join
up without a session-scoped attribution model.

### The Cocktail Finder funnel

The four steps the funnel is built from, in order:

1. `screen_view` with `screen_name = cocktail_finder` — a visit.
2. `finder_bottle_selected` with `bottle_name` and `selected_bottle_count` —
   the bottle choice. The deselect event carries the same parameters, and a
   count of `0` is the customer clearing their selection.
3. `view_item` where `source = cocktail_finder` — which cocktail details were
   opened from the results, by name and category.
4. `add_to_cart` where `source = cocktail_finder` — which of those were added.

Steps 3 and 4 carry the bottle in `source_detail` while exactly one is
selected. With several selected no single bottle sent them there, so the
`finder_bottle_selected` events are what covers that case.

### Clarity

Clarity gets the same funnel, in the form Clarity can use: a custom event per
step and session tags to filter recordings by. Firebase answers *how many*;
Clarity is how you watch the sessions behind a number.

| Tag | Set by |
| --- | --- |
| `product_viewed` | `view_item` |
| `product_added` | `add_to_cart` |
| `product_category` | Both |
| `product_source` | Both, when a source is named |
| `banner_clicked` | `select_promotion` |
| `finder_bottle` | `finder_bottle_selected` |

Tags carry catalog and banner names only — never search text or anything else
the customer typed. Clarity is release-only, so these do not appear in a debug
run even with `ANALYTICS_ENABLE_DEBUG=true`, which affects Firebase and Meta.

Firebase Analytics is disabled in debug builds by default. For a deliberate
DebugView validation build, pass:

```bash
flutter run --dart-define=ANALYTICS_ENABLE_DEBUG=true
```

## Consent behavior

Per the product owner's direction on 2026-07-26, the implementation assumes
customer consent has already been obtained outside these tracking surfaces.
There is no consent banner or in-app analytics gate: web tags fire when the
production landing page loads, and Firebase Analytics and Clarity run in
release builds. Revisit this decision before serving customers in a region or
storefront whose policy requires an explicit choice or withdrawal mechanism.

## Meta mobile prerequisite

The Meta Pixel ID is only for the landing page. Native Android/iOS App Events
use Meta Developer App ID `1611789933929380`; its Client Token is embedded in
the required Android and iOS native client configuration. The previously
supplied User Access Token is not used or stored.

Facebook Login (the optional sign-in on the customer app's order confirmation
screen) runs on this same Meta Developer App, through the `fb1611789933929380`
URL scheme. Keep the Android package and iOS bundle ID (`wtf.ebtl.app`)
attached to it. Two things it needs that App Events did not:

- **The App Secret**, set as `FACEBOOK_APP_SECRET` in the backend environment.
  It is used only server-side, to build the app access token that Meta's
  `/debug_token` requires when verifying a classic login. It must never reach a
  client.
- **A data-deletion URL**, which Meta requires before Facebook Login passes App
  Review. `admin-dashboard/public/data-deletion.html` is that page — register
  `https://<backend host>/data-deletion.html` as the Data Deletion Instructions
  URL in the Meta dashboard.

## Validation checklist

- GTM Preview shows `landing_page_ready`, download, CTA, and scroll events.
- GA4 DebugView receives landing and customer-app events with the expected
  names, EGP values, and no PII.
- Meta Events Manager Test Events receives PageView, landing conversions, and
  customer-app activation, content, cart, checkout, and purchase events.
- Clarity shows separate landing (`xsjp56x4va`) and mobile (`xr1vveuqim`)
  recordings.
- Checkout/profile/payment text is masked in real Clarity recordings.
- A successful order produces exactly one purchase event.
- `/login`, `/dashboard`, `/admin`, and `/prep` load no GTM, Meta, GA, or
  Clarity scripts.

## App Tracking Transparency (iOS)

The app asks for Apple's tracking permission once, after the first frame
(`customer-app/lib/services/app_tracking_service.dart`, called from
`AnalyticsService.resolveTrackingAuthorization`). iOS only ever shows the
dialog once per install and answers from the stored decision afterwards.

Until it is allowed, Meta's advertising-ID collection stays off — both
statically (`FacebookAdvertiserIDCollectionEnabled` is `false` in
`Info.plist`) and at runtime — because the IDFA reads back as zeros anyway.
Events still flow from the first launch; they simply carry no identifier.
Allowing the prompt turns collection on for the rest of the session and every
session after it.

Android has no such prompt: the plugin answers `notSupported` there and the
advertising ID stays governed by the device's own ads setting, so nothing
changes for Android attribution.

Verify on a real device — the prompt does not appear on a simulator with
tracking already restricted. Reset with **Settings → Privacy & Security →
Tracking** (or reinstall) to see it again.

## Remaining deployment inputs

- Production landing-page domain.
- Final App Store / Google Play / smart download URL.
