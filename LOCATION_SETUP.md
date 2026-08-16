# EBTL beach-cart location setup

Operational guide for switching on the GPS beach-cart selection shipped in
customer-app. Read this end to end before touching a console — the first item
is the only one that actually blocks the feature, and several of the steps you
might expect to need are ones you can skip.

## What the feature does

On every launch, once Home's payload has landed, the app takes a device
location fix in the background and switches to the nearest beach cart, showing
a toast that names it. Beyond 30 km from every cart it selects nothing. The
picker sheet labels each cart with its distance, sorts nearest-first, and
offers a "Use my location" button.

The fix is used **entirely on-device**. No coordinate is ever sent to the
backend, stored on disk, or attached to an analytics event. This one fact
decides most of the App Store and Play Console answers below, so keep it in
mind as you go.

## Status at a glance

| # | Task | System | Blocking? | Who |
| --- | --- | --- | --- | --- |
| 1 | Enter latitude/longitude for each beach cart | Admin dashboard | **Yes — nothing works without it** | Ops |
| 2 | App privacy questionnaire | App Store Connect | No (blocks next submission) | Whoever submits |
| 3 | Data safety form | Google Play Console | No (blocks next release) | Whoever submits |
| 4 | Register `method` as a custom dimension | Firebase / GA4 | No (blocks reporting only) | Analytics |
| 5 | End-to-end verification | Device / simulator | No | Eng |

Nothing in the app, Xcode project, Gradle config, provisioning profiles, or
Firebase project needs a code or configuration change. The permission strings,
manifest entries and the `geolocator` dependency are already committed.

---

## 1. Beach-cart coordinates — do this first

**Until this is done the feature is completely inert.** Every beach cart in the
database currently has `latitude` and `longitude` set to `NULL`. The app treats
a cart with no coordinates as one it cannot measure, so with the data as it
stands today: no distances appear in the picker, no cart is ever auto-selected,
and the app behaves exactly as it did before. There is no error and no warning
— it simply does nothing.

### Where to enter them

Admin dashboard → **Locations** → edit a cart → the **Latitude** and
**Longitude** fields. Save. The change is live immediately: the customer API
already returns coordinates on every `/api/customer/home` response, so no
deploy, migration or cache flush is involved.

Carts needing coordinates:

| Cart | Compound | Beach |
| --- | --- | --- |
| Hacienda Cart | Hacienda | North Coast |
| Marassi Cart | Marassi | North Coast |

Only rows of type `beach_cart` matter. The Central Warehouse is never offered
to customers and can be left alone.

### Getting an accurate pair

Open Google Maps, find **where the cart physically stands** — not the compound
gate, not the centre of the resort — right-click the spot and click the
coordinates at the top of the menu to copy them. They land on your clipboard as
`30.123456, 28.654321`: **latitude first, longitude second**, which is the same
order as the two form fields.

Precision: the column stores 7 decimal places. Five is already about a metre,
which is far finer than the feature needs, so anything Maps gives you is fine.

### Sanity-check before you save

The form does not validate, and a swapped or mistyped pair fails silently — the
cart just never gets picked. Check the numbers against these ranges for the
North Coast before saving:

| Field | Expected for the North Coast |
| --- | --- |
| Latitude | roughly `30.8` to `31.1` (positive — north of the equator) |
| Longitude | roughly `28.5` to `29.5` (positive — east of Greenwich) |

Two mistakes account for almost all failures here: **swapping the fields** (a
latitude of 28.9 puts the cart in southern Egypt) and **dropping the sign or a
digit**. If a cart never gets auto-selected while standing next to it, this is
the first thing to re-check.

### Confirm it took

```bash
curl -s "https://ebtl-admin-dashboard.onrender.com/api/customer/home" \
  | python3 -m json.tool | grep -A2 '"name"'
```

Each entry under `serviceAreas` should now show real numbers for `latitude` and
`longitude` instead of `null`. If the request is slow the first time, that is
the Render instance cold-starting — retry.

---

## 2. Apple

### Nothing to do in Xcode or the Developer portal

Worth stating plainly, because this is where the time usually goes:

- **No capability to enable.** When-in-use location needs no entry under
  Signing & Capabilities.
- **No entitlement.** `Runner.entitlements` and `RunnerRelease.entitlements`
  carry only `aps-environment` for push, and stay that way.
- **No provisioning profile change.** Existing profiles keep working; no
  regeneration, no new App ID configuration.
- **No background mode.** The app only reads location in the foreground, so
  `UIBackgroundModes` is untouched.
- **No Podfile edits.** `geolocator` needs no permission macros (the
  `permission_handler` pattern you may have seen does not apply here).

The purpose string is already committed in `customer-app/ios/Runner/Info.plist`:

```
NSLocationWhenInUseUsageDescription
EBTL uses your location to set the beach cart nearest to you, so prices and
availability match where you are.
```

The deployment target (iOS 15.0) is comfortably above geolocator's floor.

### App Store Connect → App Privacy

This is the one Apple-side task, and the answer is less obvious than it looks.

Apple defines **"collect"** as transmitting data off the device in a way that
you or a partner can access later. EBTL reads the location, compares it to the
cart coordinates in memory, and discards it. Nothing is transmitted, persisted,
or logged. On that basis **"Location" is not a collected data type** and the
existing privacy declaration does not need a new entry.

Two things to confirm rather than assume, since they are yours to verify and
the answer is a compliance statement:

1. **The analytics events carry no coordinates.** `select_location` sends the
   chosen cart's `location_id` (a UUID) and `method`. Neither is location data
   in Apple's sense. Nothing else new is emitted.
2. **Your existing declaration already covers the SDKs.** Firebase Analytics
   and the Meta SDK may infer coarse region from IP independently of this
   feature. If your current questionnaire already accounts for that, this
   change adds nothing; if it does not, that is a pre-existing gap worth
   closing separately.

If your reviewer prefers to declare it anyway, the honest shape is *Precise
Location → used for App Functionality → not linked to identity → not used for
tracking*. Over-declaring is safe; under-declaring is not.

### Review notes

Apple rejects vague purpose strings, not location use itself. Ours names the
benefit to the customer in concrete terms, which is what the guideline asks
for. No reviewer note is required. If a reviewer does ask, the answer is: the
app serves physical beach carts with different stock and prices, and the
location picks the right one instead of making the customer identify it by
name.

### Verify on TestFlight

Location behaves identically in TestFlight and App Store builds, so a TestFlight
build is a valid final check. Do it on a real device at or near a cart — the
simulator is fine for logic, but only a device exercises the real permission
flow and a real fix.

---

## 3. Google Play and Android

### Already in the repo

`customer-app/android/app/src/main/AndroidManifest.xml` declares:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

`minSdk` is 23, above geolocator's floor. Nothing in Gradle changes, and no API
key is needed — this uses the platform location provider, not the Google Maps
SDK, so there is no key to provision or bill.

### What you can skip

**You do not need the background location declaration.** That is the Play review
process with the video walkthrough and the multi-week turnaround, and it is
triggered by `ACCESS_BACKGROUND_LOCATION` — which this app does not declare and
must not start declaring. Foreground-only location needs no special review.

### Play Console → Data safety

Same reasoning as Apple. Play asks whether your app **collects or shares**
location, meaning transmitted off the device. EBTL does neither, so the answer
stays **No** for the Location category and the existing form needs no change.

Play separately surfaces the *permissions* an app requests, which is automatic
from the manifest and needs no action from you. Users will see the app request
location; that is expected and is not a declaration.

### A note on devices without Google Play Services

`geolocator` prefers the fused location provider and falls back to the platform
`LocationManager` when Play Services is absent (Huawei, some China-market
devices). Accuracy is a little worse; the feature still works. Nothing to
configure.

---

## 4. Firebase and GA4

### Nothing here is required for the feature to work

The location feature does not touch Firebase. It needs no new project, no
config file change, no SDK. The `google-services.json` handling in
`android/app/build.gradle.kts` is unchanged.

### The one real task: register the `method` parameter

`select_location` now carries a `method` parameter that is either `manual`
(the customer tapped a cart in the picker) or `auto_nearest` (GPS chose it).
GA4 **collects** custom parameters automatically but will not **report** on them
until they are registered as custom dimensions — until you do this, the data is
being recorded but is invisible in every report and exploration, and GA4 does
not backfill parameters recorded before registration. Do it before you start
caring about the numbers.

In the Firebase console (project `ebtl-37ddb`) → **Analytics** → **Custom
definitions** → **Custom dimensions** → **Create custom dimensions**:

| Field | Value |
| --- | --- |
| Dimension name | `Location select method` |
| Scope | **Event** |
| Description | How the beach cart was chosen: manual tap or GPS auto-select |
| Event parameter | `method` |

While you are there, check whether `location_id` is registered as well. It has
been on this event since long before this change, and if it was never
registered it has the same problem.

Standard GA4 properties allow 50 event-scoped custom dimensions; this uses one.

### Verifying the event

Analytics is **off in debug builds** unless you explicitly enable it, so a
plain `flutter run` sends nothing. To see events live:

```bash
flutter run --dart-define=ANALYTICS_ENABLE_DEBUG=true
```

Then enable DebugView for the device:

```bash
# Android
adb shell setprop debug.firebase.analytics.app wtf.ebtl.app
```

For iOS, add `-FIRDebugEnabled` to the scheme's launch arguments in Xcode.

Firebase console → **Analytics** → **DebugView** shows events within seconds.
Trigger both paths and confirm the parameter:

- Launch near a cart with location granted → `select_location` with
  `method: auto_nearest`
- Tap a different cart in the picker → `select_location` with `method: manual`

Standard (non-debug) reports lag 24–48 hours. DebugView is the only way to
confirm quickly.

---

## 5. End-to-end verification

Once coordinates are in, walk these. The simulator covers everything except the
real permission dialog and a real fix.

Set a simulated position with **Android Emulator → ⋯ Extended controls →
Location**, or **iOS Simulator → Features → Location → Custom Location**.

| Scenario | Simulated position | Expected |
| --- | --- | --- |
| First launch, permission granted | At Marassi | Prompt appears after Home paints, toast names Marassi, chip updates, catalog reloads |
| Relaunch, unmoved | At Marassi | Marassi stays selected, **no** toast |
| Moved to the other cart | At Hacienda | Toast announces the switch to Hacienda |
| Far from everything | Central Cairo | Nothing auto-selected, previous cart untouched; picker lists both carts sorted by distance with `~250 km away` labels |
| Permission denied | Any | App behaves exactly as before; picker shows no distances and offers "Use my location" |
| Denied, then granted in Settings | At a cart | "Use my location" produces distances and re-sorts the list |
| Manual pick during the GPS window | At Marassi, tap Hacienda immediately | Hacienda stays selected — a deliberate pick outranks GPS for the rest of that launch |

The last row is the subtle one and the least likely to be exercised by accident;
it is worth doing deliberately.

### On a real device

Do a final pass standing at an actual cart. Watch for the toast naming the cart
you are standing at, not the other one — that is the single check that catches a
swapped latitude/longitude, which every simulator test would have passed.

---

## 6. Tuning and known limits

**The 30 km radius** lives in `LocationService.maxAutoSelectMeters`
(`customer-app/lib/services/location_service.dart`). It was chosen for the
current geography: the two carts sit about 20 km apart while Cairo is roughly
250 km away, so it cleanly separates "at the beach" from "at home". Changing it
is a one-line code change and a release, not a console setting.

**Adding a third cart near an existing one** needs no configuration — it is
picked up from the API automatically — but do sanity-check that the two are far
enough apart that a customer at one is not closer to the other. Carts within a
few hundred metres of each other will flip between launches as the fix jitters.

**Auto-select runs on every launch**, so a customer who deliberately picked a
different cart last session will be moved back to the nearest one when they next
open the app. That is intended, and the toast is what makes it visible; a manual
pick only holds for the launch it was made in.

**Location accuracy is currently the platform default** (`best`), not the
coarser setting the carts would tolerate. It works; it just costs a slightly
slower first fix and more battery than necessary. Worth revisiting if the launch
delay is noticeable in the field.

**Pre-existing, unrelated to this feature:** nothing validates the stored
beach-cart id against the carts the API returns. If a cart is deactivated while
a customer has it selected, their app keeps showing it and every add-to-cart
fails server-side with "Selected beach cart is not available." Auto-selection
makes this less likely to be hit but does not fix it. Deactivating a cart is
therefore still something to do deliberately.

---

## Identifiers

| System | Identifier |
| --- | --- |
| Firebase project | `ebtl-37ddb` |
| iOS bundle ID / Android applicationId | `wtf.ebtl.app` |
| Customer API base URL | `https://ebtl-admin-dashboard.onrender.com` |

See [`TRACKING_SETUP.md`](TRACKING_SETUP.md) for the full analytics event
catalogue and the rest of the Firebase, Meta and Clarity configuration.
