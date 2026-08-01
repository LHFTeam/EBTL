# Home Screen Redesign — Designer Handoff

**App:** EBTL customer app (Flutter, iOS + Android)
**Surface:** Home tab (tab 0 of 4)
**Prepared:** August 2026
**Source of truth for this document:** `customer-app/lib/features/home/`, `customer-app/lib/main.dart`, and `admin-dashboard/server/routes/customerRoutes.js`

---

## 0. How to use this document

- **§1–§3** — product and navigation context. Read once.
- **§4** — an annotated teardown of the Home screen exactly as it ships today, with real numbers you can rebuild in Figma.
- **§5** — the data contract: what Home *can* show without backend work, and what needs a backend ticket first.
- **§6** — the design system as actually built in code (colours, type, components, states).
- **§7** — problems with the current Home, ranked.
- **§8** — researched best practice: what belongs on a home screen of this type.
- **§9** — a recommended module structure for the redesign, prioritised.
- **§10–§13** — states to design, engineering constraints, open business questions, and deliverables.

Everything in §4 and §6 is measured from the code, not from a mock. Where a number is an estimate (text line-heights that depend on font metrics), it is marked *approx*.

---

## 1. Product context in 60 seconds

**EBTL** — "Everything But The Liquor." Tagline: *"You bring the bottle. We bring the magic."*

It is a **beach-side cocktail-kit service** in Egypt. The customer already owns a bottle of liquor. EBTL sells them everything else — mixers, garnishes, syrups, ice, snacks — assembled into a kit for a specific cocktail, picked up at a **beach cart** or delivered to their unit in the compound.

The signature mechanic is the **Cocktail Finder**: pick the bottle you already have, see only the cocktails you can actually make with it.

Facts that shape every design decision:

| Fact | Consequence for Home |
| --- | --- |
| **No login, ever.** An anonymous session token is created on first launch and stored on-device. | You cannot greet the user by name on a cold start. There is no "sign in" affordance and no account wall. Personalisation must be built from local/session history, not identity. |
| **Prices in EGP**, business time zone `Africa/Cairo`. | Price format is `EGP 120` / `EGP 120.50`. |
| **English only.** No i18n layer, no RTL. | Copy can be baked into layouts. But see §7 on the baked-image problem. |
| **Everything loads from the backend.** No offline data, no demo fallback. | Every module needs a loading, error and empty state. A user on a bad beach connection sees a full-screen error today. |
| **Location-gated availability.** Product availability, pricing and add-to-cart all depend on which beach cart is selected. | The location choice is not decoration — it is a hard prerequisite for transacting. |
| The backend cold-starts on Render (session call has a **90 s** timeout). | First launch after an idle period can be genuinely slow. The loading state is a real screen users will see, not a formality. |

---

## 2. Where Home sits

```
Onboarding (4 full-bleed images, first launch only)
   └─▶ RootShell  ── bottom nav, 88pt tall, 4 fixed tabs ──────────────┐
         0  HOME      ← this redesign                                   │
         1  Explore   (catalogue: categories + product grid)            │
         2  Cart      (badge shows total quantity, caps at "99+")       │
         3  Profile   (badge dot when unread notifications)             │
                                                                        │
   Pushed on top of the shell (no tab of their own):                    │
     • Cocktail Finder    ← from Home hero CTA, Home "View all", Explore hero
     • Cocktail Detail    ← from any product card
     • Checkout           ← from Cart
     • Notifications      ← from the bell in the Home/Explore top bar
     • Active Orders      ← from the receipt icon in the top bar (only when count > 0)
```

**Everything Home currently links to:** Cocktail Finder (three ways), Cocktail Detail, Notifications, Active Orders. That's it.

**Everything Home does *not* link to:** search (does not exist anywhere in the shipped nav — see §7.2), cart, checkout, order history, favourites, addresses, referrals, promo codes, the Explore catalogue.

---

## 3. Who is on this screen

Because there is no login, treat these as **states**, not personas — the app can detect all three from data it already holds:

1. **First-run.** Just finished onboarding. No location selected, no cart, no orders, no history. This user's only job is: *choose a beach cart, then understand what this thing is.*
2. **Browsing / pre-purchase.** Location selected, empty or partial cart. Job: *find a cocktail I can make and add the kit.*
3. **Returning with a live order.** Has a paid order in flight, on a beach, probably checking "is it ready?" Job: *where is my order* — and secondarily *order one more round.*

Today's Home screen is designed almost entirely for state 1, and treats states 2 and 3 as a badge on an icon.

---

## 4. Current Home screen — annotated teardown

File: `lib/features/home/home_screen.dart` (404 lines, `StatelessWidget`, receives a fully-loaded `AppData` object from `RootShell`).

Scroll structure: a single `CustomScrollView` with 6 slivers, no app bar, no pull-to-refresh, no sticky elements.

### 4.1 Block inventory (top to bottom)

| # | Block | Height | Data source | Tap targets |
| --- | --- | --- | --- | --- |
| 1 | **Hero header** | **470pt fixed** | `hero` (server, hardcoded) | Bell, receipt icon (conditional), CTA button |
| 2 | **Beach cart picker** | ~183pt | `serviceAreas` | Horizontal cards, 235×100 |
| 3 | **Choose Your Bottle** | ~213pt | `liquorTypes` | Horizontal cards, 80×130 |
| 4 | **Featured Cocktails** | ~264pt | `featuredCocktails` | Cards 128×200 + "View all" |
| 5 | **How It Works** | ~286pt (aspect-ratio image) | bundled asset | **none — not tappable** |
| 6 | Bottom spacer | 24pt | — | — |

**Total scroll length ≈ 1,440pt** of content in a **~709pt viewport** (iPhone 14: 844 − 88pt nav − 47pt safe-area top). So Home is roughly **two screens tall**.

### 4.2 The fold

| Device | Usable viewport | What is visible without scrolling |
| --- | --- | --- |
| iPhone 14 (390×844) | ~709pt | Entire hero + entire beach-cart row + the header of "Choose Your Bottle" |
| iPhone SE (375×667) | ~559pt | **Hero only**, plus the beach-cart section header |

**The hero consumes 66–84% of the first screen.** Featured Cocktails — the only actual product on the page — starts around **870pt down**, i.e. after a full screen of scrolling on every device.

### 4.3 Block 1 — Hero header (`HeroHomeHeader`, `home_screen.dart:125`)

Fixed `Container(height: 470)` on a cream background, with a `Stack`:

- **Background image**: starts at y=120, fills to the bottom, at **45% opacity**. Source is `hero.image_url` from the API — but the backend hardcodes it to `null` (`customerRoutes.js:3405`), so in production it is **always** the bundled `assets/images/home_hero.jpg`. The image is decorative wallpaper behind text; it is never art-directed against the copy.
- **y=14, left 22**: `EbtlLogo` — a beach-umbrella icon + "EBTL" in Playfair Display 38pt, letter-spacing 6, over "EVERYTHING BUT THE LIQUOR" in Manrope **7pt**, letter-spacing 1.7, coral.
- **y=14, right 22**: 56×56 circular buttons on 78%-white:
  - `ActiveOrdersIconButton` (receipt icon) — **only rendered when active-order count > 0**, then a 10pt spacer,
  - `NotificationsIconButton` (bell). Both carry a coral pill badge, ≥20pt, capped at "9+".
- **y=130, left/right 22**, a text column:
  1. `"Hey there, Cocktail Lover! 👋"` — Manrope 18 / w800 / navy. **Hardcoded string** (`home_screen.dart:197`).
  2. 20pt gap
  3. `"You bring the bottle."` — Playfair Display 32 / w800 / navy, line-height 1.25
  4. `"We bring the magic."` — Playfair Display 26 / w600 / *italic* / coral, line-height 1.1
     *(Both taglines are hardcoded in the widget. The API sends the same string as `hero.subheadline` — the app parses it and never renders it.)*
  5. 24pt gap
  6. `hero.headline` — Manrope 17 / w500 / ink, line-height 1.55, **max 3 lines, ellipsised**. Currently: *"Premium mixers, garnishes, syrups & cocktail ingredients."*
  7. 28pt gap
  8. **Primary CTA**: `ElevatedButton.icon`, height **64pt**, coral fill, white text, radius 22, icon `liquor_outlined`, label from `hero.primary_cta_label` (currently *"Find your cocktail"*). Opens the Cocktail Finder. The button hugs its content — it is **not** full-width.

Approximate CTA position: **y ≈ 348–412** within the hero, so it lands roughly mid-screen on all supported devices. It is reachable, but it sits in the "stretch" band rather than the natural thumb rest.

### 4.4 Block 2 — Beach cart picker (`ServiceAreaSection`, `home_screen.dart:270`)

Rendered only if `serviceAreas` is non-empty. Uses the shared `SectionBlock` chrome (22pt top padding, coral 28pt icon, Manrope 18/w900 title, optional Manrope 13/w500 subtitle, 14pt gap, then content).

Copy is state-dependent:

| Nothing selected | Something selected |
| --- | --- |
| **"Choose Your Beach Cart"** / *"Select your location for real-time availability."* | **"Ordering From"** / *"Availability is checked against this beach cart."* |

Content: a horizontal `ListView` of `ServiceAreaCard`s, **235×100**, 12pt gaps, 22pt edge padding.
Each card: 90%-white fill, radius 20, 1pt `border` stroke → **1.5pt coral** when selected; a 52pt circle (seafoam → blush when selected) holding a beach-umbrella icon → **check icon** when selected; then the location name (Manrope 15/w900/navy, 2 lines max) and subtitle (Manrope 12/w700/muted, 2 lines max). 180ms `AnimatedContainer` on selection.

Selecting a cart writes to secure storage and triggers a **full app-data reload** (the whole catalogue refetches).

### 4.5 Block 3 — "Choose Your Bottle" (`home_screen.dart:66`)

`SectionBlock` — icon `local_bar_outlined`, title **"Choose Your Bottle"**, subtitle *"Pick the liquor you already have."*, no action link.

Content: 130pt-tall horizontal list of `BottleCard`s, **80pt wide**, 8pt gaps.
Card: 88%-white, radius 18, 1pt border, soft shadow, containing a bottle photo (`CachedNetworkImage`, contain fit, falls back to a generated placeholder).

> **The bottle name is switched off.** `HomeScreenVisuals.showHomeLiquorBottleCardName = false` (`home_screen_visuals.dart:34`). The cards are **unlabelled images** with no `Semantics` label. Screen-reader users get nothing; sighted users must recognise the brand from a ~72pt-wide photo.

Tapping opens the Cocktail Finder pre-filtered to that liquor.

### 4.6 Block 4 — "Featured Cocktails" (`home_screen.dart:90`)

`SectionBlock` — icon `local_bar_outlined` (**the same icon as the block above it**), title **"Featured Cocktails"**, action link **"View all"** (teal, w800, with a chevron) which opens the *unfiltered* Cocktail Finder.

Content: 200pt-tall horizontal list of `CocktailSmallCard`s, **128pt wide**, 12pt gaps. Empty state: `EmptyStateCard` — *"No featured cocktails are available right now."*

Card anatomy (`CocktailCardShell`), white, radius 16, 1pt border:
- Image, **110pt** tall, with up to **1** `ProductTagBadge` overlaid top-left, and an "Unavailable" sand pill bottom-right when not orderable.
- Text block, padding 12/8/10/8:
  - Name — Manrope **10pt** / w900 / navy, line-height 1.12, 2 lines max
  - Price — **hidden** (`showFeaturedProductCardPrice = false`)
  - Short description — Manrope **8pt** / w500 / ink, line-height 1.1, 2 lines max
  - Bottom row: a favourite heart **icon** (coral when favourited) — **display only, not tappable on this card**

> 8pt and 10pt type is far below any accessible minimum, and the price — the single most decision-relevant attribute on a commerce card — is switched off.

### 4.7 Block 5 — "How It Works" (`how_it_works_block.dart`)

A single flat image: `assets/banners/how_it_works_banner.webp`, aspect ratio 1440:1064, 22pt side margins, radius 24, `BoxFit.contain`. Roughly **256pt tall** on a 390pt-wide device.

It carries a `Semantics` label (*"How it works. Pick your bottle, choose a recipe, mix and enjoy."*) and a text fallback if the asset fails to decode. **It is not tappable and leads nowhere.**

The same file contains `HowItWorksStep` / `HowItWorksCard` — a fully built, styled, three-step card component with numbered coral bubbles and chevrons — which is **dead code, referenced nowhere**. If the redesign wants an interactive How-It-Works, the component already exists.

### 4.8 Block 6 — Bottom nav (`ebtl_bottom_nav.dart`, shared)

88pt tall, 97%-white, 1pt top border. Four equal tabs: Home / Explore / Cart / Profile. Icon 27pt, label Manrope **9.5pt**, active state = coral icon + w900 label + a 28×3 coral underline that animates in over 180ms. Cart badge (17pt pill, "99+" cap) and Profile unread dot (8pt) are positioned by index.

---

## 5. Data contract — what Home can show

Home renders from **one** payload: `GET /api/customer/home?location_id=…` (`customerRoutes.js:3337`), merged with `GET /api/customer/cocktail-finder/options` into a single `AppData` object.

### 5.1 Available today, already parsed

| Field | Used on Home? | Notes |
| --- | --- | --- |
| `hero.headline` | ✅ | Server-hardcoded string |
| `hero.subheadline` | ❌ **parsed, never rendered** | Duplicates the hardcoded tagline |
| `hero.image_url` | ✅ (always `null`) | Server sends `null`; bundled asset always wins |
| `hero.primary_cta_label` / `_target` | ✅ label only | Target is ignored; CTA is hardwired to the Finder |
| `serviceAreas[]` | ✅ | id, name, type, compound, beach, lat/lng, `is_available` — **which the server hardcodes to `true` for every location** |
| `featuredCocktails[]` | ✅ | Full product objects: name, slug, image, tags, **prep time**, **starting price**, variants, **liquor compatibility**, **availability**, **isFavorite** |
| `liquorTypes[]` | ✅ | id, name, image, display order |
| `categories[]` | ❌ **parsed, never rendered** | Active product categories with sort order — free browse-by-category on Home, no backend work |
| `cartSummary` | ⚠️ badge only | `item_count`, `total_quantity`, `subtotal_inc_vat`, currency — enough for a "resume your cart" module today |
| `finderOptions` | ❌ on Home | Tags, categories, sort options |

**Two ready-to-use wins with zero backend work:** `categories` and `cartSummary` are already in memory on Home and rendered nowhere.

**Also unused on the cards:** `prep_time_minutes`, `starting_price_inc_vat`, `compatibility` (which bottles a cocktail works with), and `availability`. The featured card deliberately hides most of what it already knows.

### 5.2 Reachable with an extra call the app already makes

| Data | Endpoint | Currently used for |
| --- | --- | --- |
| Active orders (status, label, ETA, total, location, primary item, image) | `GET /customer/orders?limit=100`, filtered client-side | Just a **count** on a badge (`main.dart:277`). Everything needed for a full live-order card is already fetched and thrown away. |
| Unread notifications | `GET /customer/notifications` — polled every **30 s** | A badge + a toast |
| Order history / reorder source | `GET /customer/orders` | Profile only |
| Favourites | `GET /customer/favorites` | Profile only |
| Profile (name, phone, avatar) | `GET /customer/profile` | Profile only — **a real name exists and Home says "Cocktail Lover"** |
| Referral code / "Refer & Earn" | `GET /customer/referrals` | Profile only |

### 5.3 Needs a backend ticket first

- **Promotions/offers on Home.** Promo codes exist server-side but only apply at checkout; there is no customer-facing "current offers" endpoint.
- **Real hero content management.** The hero is a hardcoded object literal in `customerRoutes.js`. Anything editable (seasonal banner, campaign image, multiple slots) needs a CMS-ish endpoint.
- **Per-location availability.** `is_available` is hardcoded `true`; there is no open/closed, hours, or ETA per beach cart.
- **Geolocation / nearest cart.** Locations carry lat/lng but nothing in the app uses device location.
- **A dedicated active-orders endpoint.** Fetching 100 orders to count the live ones is a workaround.
- **Ratings/reviews, delivery ETAs, loyalty balance.** None of these exist in the data model.

> Rule for this project: the customer app is a thin client. If a module needs data that isn't in §5.1/§5.2, it is a backend change in `admin-dashboard` **before** it can be designed as real.

---

## 6. Design system, as actually built

### 6.1 Colour (`core/theme/ebtl_colors.dart`)

| Token | Hex | Where it earns its keep |
| --- | --- | --- |
| `navy` | `#0E2238` | Headlines, card titles, primary icon |
| `coral` | `#F35F4B` | **The** action colour: CTA, active tab, badges, section icons |
| `cream` | `#FFF8EE` | App background, everywhere |
| `sand` | `#F3E5D0` | Disabled fills, "Unavailable" pill |
| `seafoam` | `#C9E3DD` | Soft accent circles, Explore hero |
| `teal` | `#1F6F68` | Secondary/link colour ("View all") |
| `gold` | `#E7BD68` | Accent, rarely used |
| `blush` | `#F8C9BD` | Selected-state fill |
| `ink` | `#1F2933` | Body copy |
| `muted` | `#6F7882` | Secondary copy |
| `border` | `#E8DDD1` | 1pt hairline on every card |
| `white` | `#FFFFFF` | Card fills — usually at 78–90% alpha over cream |

No dark mode. No ad-hoc hex allowed in screens — new colours must be added as tokens.

### 6.2 Type

Two families, both via `google_fonts`:

- **Manrope** — everything functional. Weights in use: w500 (body), w600, w700, w800 (buttons/links), **w900** (titles, card names, badges — used very heavily).
- **Playfair Display** — display only. Used at 38 (logo), 32/26 (hero taglines, the 26 in italic), 42 (Explore header), 24 (fallbacks), 21 (Explore hero).

Shared styles live in `core/theme/ebtl_text_styles.dart` — currently just two: `sectionTitleStyle()` (Manrope 18/w900/navy) and `detailSectionTitleStyle()` (16/w900/navy). **Everything else is an inline `GoogleFonts.manrope(...)` call at the point of use.** There is no type scale. Building one is a deliverable worth asking for (§13).

Observed sizes on Home: 38, 32, 26, 18, 17, 15, 13, 12, **10, 9.5, 8, 7**. The bottom four are the problem.

### 6.3 Spacing and shape

- Horizontal page margin: **22pt** (everything; carousels pad their first/last item to match).
- Section rhythm: 22pt above a section header, 14pt between header and content.
- Radii: 16 (product card), 18 (bottle card, buttons), 20 (location card), 22 (hero CTA), 24 (banners), 999 (pills/badges).
- Elevation: no Material shadows. One recurring soft shadow — `black @ 3.5–4%`, blur 16–18, offset (0, 8).
- Borders: 1pt `border` hairline on essentially every surface; 1.5pt coral for selected.

### 6.4 Shared components you can reuse (already built)

`SectionBlock` (icon + title + subtitle + optional action link) · `CocktailCardShell` / `CocktailSmallCard` / `CocktailGridCard` · `BottleCard` / `SelectableBottleCard` / `CompatibleLiquorChips` · `ServiceAreaCard` · `ProductTagBadge` · `NotificationsIconButton` / `ActiveOrdersIconButton` / `CircleIconButton` · `EbtlLogo` · `NetworkOrAssetImage` (network → bundled asset → gradient) · `IngredientSvgIcon` · `EmptyStateCard` / `InlineErrorCard` / `AppErrorScreen` / `EbtlLoadingSection` · `ShopProductCardTile` / `ShopProductGridSection` (Explore) · `HowItWorksCard` *(built, unused)* · `AppToast`.

**Designing with these costs far less to ship than designing new ones.** Flag explicitly when a new component is intentional.

---

## 7. What's wrong with Home today — ranked

### 7.1 Home doesn't serve the returning customer at all

There is no cart resumption, no reorder, no order history, no live-order card. A user with a paid order in flight on a beach gets a **56pt icon with a number on it** — and only if the count is above zero. Meanwhile every field needed for a rich live-order card (status label, ETA, total, beach cart name, product image) is already being fetched (§5.2).

For a service where people are sitting on a beach ordering repeatedly, this is the single biggest gap.

### 7.2 There is no search anywhere in the app

`ShopSearchScreen` is fully built and **wired to nothing** — it is unreachable in the shipped nav. `finder_header.dart:64` renders a search button whose handler is literally `onTap: () {}`. The only text search that works is inside the Cocktail Finder, two taps deep behind the hero CTA.

Around **one in three** app users navigate by category and the rest lean on search; a catalogue app with no visible search field is leaving a primary product-finding path unbuilt. ([Baymard — mobile search field](https://baymard.com/mcommerce-usability/benchmark/mobile-page-types/search-field))

### 7.3 The hero is 470pt and mostly says the brand name twice

The hero spends a full 470pt — 66–84% of the first screen — on: a logo (with the full brand name spelled out beneath it in 7pt), a generic greeting, the tagline in two typefaces, a category description, and one button. There is no product, no price, no availability, no personalisation, no urgency. The background image is decorative wallpaper at 45% opacity, not a merchandising surface.

Homepage carousels have fallen from 52% to 32% of e-commerce sites precisely because oversized top-of-page brand real estate underperforms ([Baymard — homepage & category UX](https://baymard.com/blog/current-state-of-ecommerce-category-ux)). A static 470pt hero has the same problem without the carousel's upside.

### 7.4 The critical action is buried mid-page and unenforced

Choosing a beach cart is a **hard prerequisite** — without it, add-to-cart fails with *"Choose a beach cart first."* Yet the picker is the second module down, styled identically to every other carousel, with no persistent indicator of what is selected once you scroll past it. A user can browse the whole app, tap a cocktail, and only discover the requirement at the moment they try to buy.

Nothing on Home ever shows the selected cart above the fold.

### 7.5 Type sizes fail accessibility

Card names at **10pt**, descriptions at **8pt**, tab labels at **9.5pt**, brand sub-line at **7pt**. Nothing on Home responds to the OS text-size setting. Fixed-height containers (470pt hero, 200pt card rails) mean a larger accessibility text size would overflow, not reflow.

### 7.6 Prices and product facts are switched off

`showFeaturedProductCardPrice = false` and `showHomeLiquorBottleCardName = false` (`home_screen_visuals.dart`). So the commerce surface shows products with **no price**, and the bottle picker shows **unlabelled** brand photos with no `Semantics` label. `prep_time`, `compatibility` and `availability` are all present in the data and unused on the card.

### 7.7 Structural / craft issues

- **No pull-to-refresh** on Home. (Explore has one.) Home only refreshes on location change or cart mutation.
- **Duplicate section icon** — "Choose Your Bottle" and "Featured Cocktails" both use `local_bar_outlined`.
- **The favourite heart on a card is decorative** — it displays state but cannot be tapped.
- **Four horizontal carousels stacked vertically** (locations, bottles, cocktails, plus the Explore recents pattern). Everything is a side-scroller, so nothing has visual priority and all content is partially clipped by design.
- **How It Works is a flat image** — unselectable text, no scaling, no tap target, ~256pt of dead space, and its interactive counterpart already exists as dead code.
- **A greeting that can be personalised isn't.** `GET /customer/profile` returns a real name; Home says *"Cocktail Lover."*
- **No time/context awareness** on a product that is inherently time-and-place bound (beach, afternoon, sunset).

---

## 8. What should be on a home screen — the research

Sources are listed at the end of this section. The synthesis below is filtered for *this* product: a location-gated, high-repeat, small-catalogue commerce app with no login.

### 8.1 A home screen has exactly three jobs

1. **Orient** — what is this, and am I in the right place? (For EBTL: *which beach cart am I ordering from?*)
2. **Route** — get me to what I want in as few taps as possible: search, categories, and a small number of high-intent shortcuts.
3. **Resume** — put my in-flight state in front of me: live order, open cart, recent purchases.

Current Home does (1) at length, does (2) narrowly (one CTA into the Finder), and does **not** do (3).

### 8.2 The evidence, applied

| Principle | Evidence | What it means here |
| --- | --- | --- |
| **Reorder is the dominant behaviour in repeat-purchase commerce.** | ~70% of Zepto's orders are reorders; one-tap reorder is a non-negotiable in quick-commerce home screens. ([ProductGrowth](https://productgrowth.in/insights/ecommerce/quick-commerce-ux/)) | A "Order it again" rail from `GET /customer/orders` is probably the highest-ROI module you can add. Nothing like it exists today. |
| **Show live order status on the home screen, not just in a tab.** | Apps like Blinkit surface the countdown on the homepage once an order is placed; the more visible the timer, the more users feel in control. ([ProductGrowth](https://productgrowth.in/insights/ecommerce/quick-commerce-ux/)) | Replace the receipt-icon badge with a real card, pinned directly under the header while an order is active. Data is already fetched. |
| **Search must be visible, not hidden behind an icon or a menu.** | On mobile the field is too often collapsed; the design of the field itself directly changes whether users search at all. ([Baymard](https://baymard.com/mcommerce-usability/benchmark/mobile-page-types/search-field)) | Persistent search field in the Home header. Currently there is none at all. |
| **Category browsing is a first-class path, not a fallback.** | ~1 in 3 app users browse by category, especially when seeking inspiration. ([Baymard homepage & category research](https://baymard.com/research/homepage-and-category-usability)) | `categories` is already in the Home payload and rendered nowhere. Add a category row. |
| **Big brand heroes and carousels underperform.** | Homepage carousel usage fell 52% → 32%; they "seldom perform well" in practice. ([Baymard](https://baymard.com/blog/current-state-of-ecommerce-category-ux)) | Cut the 470pt hero hard. If a promotional slot survives, make it a single static, product-led banner — not a brand statement. |
| **Personalise the home screen.** | Personalised home screens, smart search/filters and one-click reorder are the standard feature set for this app category. ([Food-delivery UX practice](https://medium.com/@prajapatisuketu/food-delivery-app-ui-ux-design-in-2025-trends-principles-best-practices-4eddc91ebaee)) | Use the name from `/customer/profile`, recently-viewed (already stored locally), favourites, and last-ordered. No login required for any of it. |
| **Primary actions belong in the thumb zone.** | Most people operate one-handed; the bottom-centre band is the comfortable reach, top corners are the hardest. ([Parachute Design / Hoober](https://parachutedesign.ca/blog/thumb-zone-ux/)) | The bell and the receipt icon — two *secondary* actions — currently occupy the hardest-to-reach corner. The primary CTA sits mid-screen. Reconsider both. |
| **Touch targets: 44×44pt minimum (Apple/WCAG 2.5.5), 48dp (Material); WCAG 2.2 SC 2.5.8 sets a 24×24 floor. ≥8pt between targets.** | ([Parachute Design](https://parachutedesign.ca/blog/thumb-zone-ux/)) | The 56pt circle buttons pass. Card taps pass. But any new inline control (favourite toggle, quantity stepper, chip) must be spec'd at ≥44pt. |
| **Keep it uncluttered; use size and contrast to create one clear hierarchy.** | ([Weavers Web](https://weaversweb.com/6-essential-ui-ux-design-principles-for-food-delivery-apps-in-2025/)) | Four identical horizontal rails give every module equal weight. Vary the format: one full-width card, one grid, one rail. |
| **Trust and credibility matter more than they look.** | Low trust/poor credibility drives ~17% of checkout abandonment. ([Baymard, via Anatta](https://anatta.io/blog/ecommerce-navigation-ux)) | Prices, availability, prep time and fulfilment terms on the card — not hidden. "Unavailable" states should be honest and early. |
| **The bar is low, and that's an opportunity.** | 71% of leading e-commerce mobile apps rate "mediocre or worse"; none rated "good." ([Baymard 2026 Mobile App UX benchmark](https://baymard.com/blog/mobile-app-ux-trends)) | Fixing search, reorder and live-order status alone would put this app ahead of most of its category. |
| **Test with 5 users.** | Five participants surface ~80% of major usability issues. ([NN/g](https://www.nngroup.com/articles/113-design-guidelines-homepage-usability/)) | Budget one round of 5 beach-side sessions before build. Cheap, and this is a screen with strong opinions baked into it. |

### 8.3 The canonical module stack for this app category

In priority order, as it appears in well-performing apps of this type:

1. Header — location/context + search + notifications
2. Live order status (conditional)
3. Open cart resumption (conditional)
4. Reorder / "buy it again" (conditional on history)
5. Primary discovery mechanic — for EBTL, the bottle picker
6. Categories
7. Merchandised products (featured / trending / seasonal)
8. Promotional slot (single, static)
9. Education / how-it-works / referral — bottom, for new users only

Note how much of that stack is **conditional**. A good home screen for this product is not one fixed layout; it is a rules-driven stack that looks materially different for a first-run user and a returning one.

**Sources:**
[Baymard — Mobile E-Commerce Usability](https://baymard.com/research/mcommerce-usability) ·
[Baymard — Homepage & Category Usability](https://baymard.com/research/homepage-and-category-usability) ·
[Baymard — Current State of E-Commerce Category UX](https://baymard.com/blog/current-state-of-ecommerce-category-ux) ·
[Baymard — Mobile App UX Trends 2026](https://baymard.com/blog/mobile-app-ux-trends) ·
[Baymard — Mobile 'Search Field' examples](https://baymard.com/mcommerce-usability/benchmark/mobile-page-types/search-field) ·
[NN/g — 113 Design Guidelines for Homepage Usability](https://www.nngroup.com/articles/113-design-guidelines-homepage-usability/) ·
[NN/g — Mobile & Tablet Usability Research](https://www.nngroup.com/reports/topic/mobile-and-tablet-design/) ·
[Quick Commerce UX: Designing for 10-Minute Delivery](https://productgrowth.in/insights/ecommerce/quick-commerce-ux/) ·
[Food Delivery App UI/UX — Trends, Principles & Best Practices](https://medium.com/@prajapatisuketu/food-delivery-app-ui-ux-design-in-2025-trends-principles-best-practices-4eddc91ebaee) ·
[6 Essential UI/UX Design Principles for Food Delivery Apps](https://weaversweb.com/6-essential-ui-ux-design-principles-for-food-delivery-apps-in-2025/) ·
[Mastering the Thumb Zone](https://parachutedesign.ca/blog/thumb-zone-ux/) ·
[E-commerce Navigation Best Practices](https://anatta.io/blog/ecommerce-navigation-ux)

---

## 9. Recommended structure for the redesign

This is a **starting proposal**, not a locked spec. Argue with it — but if you drop a module, say what problem from §7 you're solving instead.

### 9.1 Above the fold (target: everything below in the first ~380pt)

**A. Compact header — replaces the 470pt hero. Target ≤ 140pt.**
- Left: **selected beach cart** as a tappable chip — icon + name + chevron. This is the app's context indicator and its most important unmet need. Tap → cart switcher sheet.
  - When nothing is selected: the chip becomes the **primary** call to action — *"Choose your beach cart"* in coral.
- Right: notifications bell (keep the existing component + badge). Move the active-orders icon out — it is replaced by module B.
- Reduce the logo to a mark, or drop it. The app icon already established the brand; the 7pt "EVERYTHING BUT THE LIQUOR" line is unreadable and does no work.
- Second row: **persistent search field** — *"Search cocktails, mixers, snacks"*. Route it to the existing `ShopSearchScreen`, which is already built (§7.2). Consider making the header sticky on scroll.

**B. Live order card — conditional, only when an active order exists. Full width.**
Status label, beach cart name, item image, ETA if available, total, and a clear "Track order" affordance. Data is already fetched (§5.2). This replaces the badge-only treatment.

**C. Cart resumption — conditional, when `cartSummary.total_quantity > 0`.**
Slim single-line bar: *"3 items · EGP 460 · Checkout →"*. `cartSummary` is already in the Home payload.

Design a rule for B + C both being present. Recommendation: B wins the full card, C collapses to a one-line bar beneath it.

### 9.2 Below the fold

**D. "Order it again"** — conditional, horizontal rail of last-ordered kits with a one-tap add. Needs `GET /customer/orders`, which the app already calls. Highest-ROI new module (§8.2).

**E. "Choose Your Bottle"** — keep. This is the brand's differentiator and it works. Two changes: **turn the names back on**, and add `Semantics` labels. Consider a "See all bottles" affordance since the rail truncates.

**F. Featured / merchandised products** — keep, but fix the card: **show the price**, raise the name to ≥13pt and the description to ≥11pt, make the favourite heart a real 44pt tap target, and surface `prep_time` and/or bottle compatibility. Widen the card if it needs the room.

**G. Categories** — new, free. `categories` is already in the Home payload (§5.1). A row of category chips or tiles routing into Explore.

**H. Promotional slot** — one, static, product-led. Needs a backend ticket if it should be editable (§5.3). Do not design a carousel.

**I. How It Works** — keep, but **only for users with no order history**, and rebuild it as real widgets. `HowItWorksCard` already exists as dead code and matches the design system. This also fixes the accessibility and scaling problems of the baked image.

**J. Referral / "Refer & Earn"** — a candidate for the bottom slot. The screen and data already exist and are currently buried in Profile.

### 9.3 The composition rules matter as much as the modules

Please deliver, explicitly:
- **Module order and visibility rules per user state** (first-run / browsing / live order) — a simple table is fine.
- **A rhythm that isn't four identical carousels.** Mix full-width cards, a grid, and at most two rails.
- **What happens to the section header pattern** — `SectionBlock` is used everywhere; if you change it, you change five screens.

---

## 10. States to design (please don't skip these)

The app has **no offline data** — every one of these is a screen a real user will hit.

| State | Trigger | Existing pattern to extend |
| --- | --- | --- |
| **Cold-start loading** | First launch / backend cold start (**up to 90 s**) | `theLoadingScaffold()` — full-screen with the EBTL loader webp |
| **Full failure** | `/home` unreachable, nothing cached | `AppErrorScreen` + retry. Today this replaces the *entire* app shell |
| **Section-level failure** | One module fails | `InlineErrorCard` + retry |
| **Empty featured** | No featured products for this cart | `EmptyStateCard` — *"No featured cocktails are available right now."* |
| **No location selected** | First run, or cleared | Section copy flips to "Choose Your Beach Cart" — **needs a much stronger treatment** (§7.4) |
| **No service areas at all** | Empty `serviceAreas` | **Currently the whole section silently disappears.** Needs a designed state |
| **Product unavailable** | `availability.isOrderable == false` | Sand "Unavailable" pill on the card |
| **First-run vs. returning** | No order history vs. has history | **Does not exist today** — Home is identical for both |
| **Refresh in flight** | Background reload | Old content stays on screen; no indicator. **No pull-to-refresh on Home** |
| **Toasts** | New notification arrives (30 s polling) | `AppToast` — order / info variants, with an action |

Also worth specifying: large-accessibility-text behaviour, and what a 320pt-wide device does to the card rails.

---

## 11. Engineering constraints — read before you finalise

These aren't preferences; they're properties of this codebase.

1. **Flutter, Material 3, mobile only.** No dark mode, no tablet layout, no RTL, no i18n.
2. **Deliberately lean dependencies.** No state-management library, no animation library, no codegen. Complex bespoke animation is expensive here; 180ms `AnimatedContainer` transitions are the established idiom.
3. **Colours come only from `EbtlColors`.** New colours must be added as tokens — flag them explicitly.
4. **Fonts are Manrope + Playfair Display via `google_fonts`.** A third family means a new dependency decision.
5. **Home layout constants live in `core/theme/home_screen_visuals.dart`** — card sizes, font sizes, visibility toggles. If your redesign keeps that pattern, hand over your values in that shape and they can be dropped straight in.
6. **Images:** `NetworkOrAssetImage` resolves network URL → bundled asset → gradient. Every image slot needs a **fallback** designed, because product images are frequently `null`. Bundled assets are `.webp`; new asset **folders** need registering in `pubspec.yaml`.
7. **Any new data field is a backend ticket** in `admin-dashboard/server/routes/customerRoutes.js` (§5.3). Design against §5.1/§5.2 unless you're deliberately requesting backend work — in which case call it out on the frame.
8. **Home currently receives its data pre-loaded** and is a `StatelessWidget`. Modules that fetch their own data (reorder, live order) will each need their own loading/error state — see the `FutureBuilder` pattern on Explore.
9. **Reusing an existing component is dramatically cheaper than a new one.** See the list in §6.4.

---

## 12. Open questions for the business (answer before final design)

1. **Is the beach cart chosen once, or often?** Does a user switch carts within a session? This decides whether the picker is a header chip or a persistent module.
2. **Should the app ask for device location** to pre-select the nearest cart? Lat/lng exists in the data; nothing uses it. Big first-run simplification if yes.
3. **Do carts have opening hours / capacity?** `is_available` is hardcoded `true`. If carts really do close, Home has to say so before someone builds a cart.
4. **What is the real repeat rate?** It determines whether reorder (§9.2 D) is the top module or a nice-to-have.
5. **Is there a delivery ETA** we could show? Nothing in the data model supports one today.
6. **Are promotions coming to the app?** If yes, the hero slot needs backend support and should be designed as a real merchandising surface.
7. **Should the greeting use the customer's name** where we have one? Trivial to do, and currently ignored.
8. **Should Home be personalised at all** for an anonymous user, or should it stay identical for everyone? This is the biggest single fork in the design.

---

## 13. Deliverables checklist

**Design:**
- [ ] Home — first-run state (no location, no history)
- [ ] Home — browsing state (location set, empty cart)
- [ ] Home — returning state (live order + populated cart + reorder history)
- [ ] All states from §10
- [ ] Module visibility/ordering rules table (§9.3)
- [ ] Redlines: spacing, sizes, radii, at 390pt width, plus 375pt and 430pt behaviour
- [ ] Any new components, spec'd against the §6.4 inventory (say what's new and why)
- [ ] Asset exports as `.webp`, @1x/@2x/@3x, with fallbacks designed for every image slot

**Design-system asks (out of scope for Home, but this is the moment):**
- [ ] A real **type scale** — Home alone uses 12 different sizes with no system, four of them below 10pt
- [ ] A **spacing scale** — 22/14/12/8 are conventions, not tokens
- [ ] Confirmation of accessible minimums: body ≥13pt, tap targets ≥44pt

**Measurement — instrument the redesign so we can tell if it worked.**
Analytics already run through `AnalyticsService` (Firebase + Meta + Clarity session replay), with `screen_view`, `select_location`, `search_submitted`, `view_item`, `add_to_cart`, `begin_checkout` and `purchase` already wired.

Suggested success metrics:
- Home → product-detail tap-through rate
- Time / scroll depth to first product tap
- % of sessions where a beach cart gets selected (first-run funnel)
- Search usage, once search exists at all
- Reorder-module conversion
- Home → cart → purchase rate

---

## Appendix — file map

| What | Where |
| --- | --- |
| Home screen | `customer-app/lib/features/home/home_screen.dart` |
| How It Works block (+ unused card component) | `customer-app/lib/features/home/widgets/how_it_works_block.dart` |
| Home layout tuning constants | `customer-app/lib/core/theme/home_screen_visuals.dart` |
| Colour tokens | `customer-app/lib/core/theme/ebtl_colors.dart` |
| Shared text styles | `customer-app/lib/core/theme/ebtl_text_styles.dart` |
| App shell, tabs, polling, active-orders count | `customer-app/lib/main.dart` |
| Bottom nav | `customer-app/lib/shared/widgets/ebtl_bottom_nav.dart` |
| Section header pattern | `customer-app/lib/shared/widgets/section_block.dart` |
| Product cards | `customer-app/lib/shared/widgets/cocktail_card_widgets.dart` |
| Bottle cards | `customer-app/lib/shared/widgets/bottle_widgets.dart` |
| Logo, icon buttons, badges | `customer-app/lib/shared/widgets/brand_widgets.dart` |
| Loading / error / empty states | `customer-app/lib/shared/widgets/app_state_widgets.dart` |
| Home data model | `customer-app/lib/models/app_data.dart` |
| API client | `customer-app/lib/services/api_service.dart` |
| Analytics events | `customer-app/lib/services/analytics_service.dart` |
| Backend `/customer/home` endpoint | `admin-dashboard/server/routes/customerRoutes.js:3337` |
| Assets | `customer-app/assets/` |
