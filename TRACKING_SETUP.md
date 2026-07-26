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
| `select_location` | A beach-cart location is selected |
| `view_item` | Cocktail or shop-product detail is viewed |
| `search_submitted` | Cocktail Finder search is submitted; query text is not sent |
| `add_to_wishlist` / `remove_from_wishlist` | Favorite status changes |
| `add_to_cart` | A successful cart addition |
| `begin_checkout` | Checkout data first loads |
| `purchase` | Backend-confirmed paid order only |

Commerce values use EGP as delivered by the API. Purchase events use the order
ID as the GA4 transaction ID and are deduplicated within the running app.

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
the required Android and iOS native client configuration. The App Secret and
the previously supplied User Access Token are not used or stored.

Use this same Meta Developer App for Facebook Login later. Keep the existing
Android package and iOS bundle ID (`wtf.ebtl.app`) attached to that Meta app;
the `fb1611789933929380` URL scheme is already registered for that future
login flow.

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

The app does not currently request Apple's App Tracking Transparency
permission. Native Meta events still run, but iOS advertising-ID attribution
remains subject to the device's system permission.

## Remaining deployment inputs

- Production landing-page domain.
- Final App Store / Google Play / smart download URL.
