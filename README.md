# EBTL

Monorepo for **EBTL** — a beach-side cocktail-kit service
(_"You bring the bottle. We bring the magic."_).

This repository consolidates two previously separate codebases. Both apps are
kept in their own top-level directory with full git history preserved.

## Repository layout

| Directory | Stack | Description |
| --- | --- | --- |
| [`admin-dashboard/`](admin-dashboard/) | React 19 + Vite + Express (Node ≥22) | Back-office web app **and** the backend API. Serves the admin/warehouse/cart dashboards, the public landing page, and the `/api/customer/...` API that the customer app consumes. Integrates Supabase, Geidea payments, and push notifications. |
| [`customer-app/`](customer-app/) | Flutter (Dart) | Customer-facing mobile app. A thin client over the customer API exposed by `admin-dashboard`. No customer login (anonymous session token). |

## How the two apps relate

The customer app is a thin client over the **customer API** served by the
admin dashboard's Express backend. The Flutter app talks to
`/api/customer/...` endpoints (session, home, cocktails, cocktail-finder,
shop, cart, checkout, orders, favorites, profile). See
[`customer-app/AGENTS.md`](customer-app/AGENTS.md) for the full contract.

```
┌─────────────────┐        HTTPS /api/customer/...        ┌──────────────────────────┐
│  customer-app   │  ───────────────────────────────────▶ │  admin-dashboard (server) │
│    (Flutter)    │                                        │   Express + Supabase      │
└─────────────────┘                                        └──────────────────────────┘
                                                                     ▲
                                                            admin / warehouse / cart
                                                                (React dashboard)
```

## Getting started

Each app is self-contained. Work inside its directory.

### admin-dashboard (web + backend)

```bash
cd admin-dashboard
cp .env.example .env      # fill in Supabase, Geidea, admin users, etc.
npm install
npm run dev               # runs the Express server + Vite client concurrently
```

- `npm run build` — production client build
- `npm start` — production server (`NODE_ENV=production`)

Requires Node `>=22 <23` and npm `>=10 <11` (see `admin-dashboard/.node-version`).

### customer-app (Flutter)

```bash
cd customer-app
flutter pub get
flutter run
```

The API base URL is hardcoded in
`customer-app/lib/core/network/api_config.dart`
(`https://ebtl-admin-dashboard.onrender.com`).

## History

This monorepo was assembled by merging the histories of the former
`ebtl-admin-dashboard` and `ebtl_customer_app` repositories into their
respective subdirectories. Past commits remain reachable via
`git log --follow`.
