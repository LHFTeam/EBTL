# AGENTS.md

Guidance for AI coding agents (and new contributors) working in the **EBTL**
monorepo. Read this first, then the per-app `AGENTS.md` for whichever app you
are touching.

## What this repo is

**EBTL** ("Everything But The Liquor" — _"You bring the bottle. We bring the
magic."_) is a beach-side cocktail-kit service. Customers pick a beach cart,
browse cocktails and shop products, filter cocktails by the liquor bottle they
already own (the "Cocktail Finder"), customize a kit, and check out for pickup
or delivery. Prices are in EGP; the business time zone is `Africa/Cairo`.

This is a **monorepo consolidating two previously separate codebases**, each
kept in its own top-level directory with full git history preserved (reachable
via `git log --follow`).

## Layout

| Directory | Stack | What it is | Deep docs |
| --- | --- | --- | --- |
| [`admin-dashboard/`](admin-dashboard/) | React 19 + Vite + Express (Node ≥22, ESM) | The back-office web app **and** the backend API + marketing landing page. Serves the staff dashboard (`/api/...`) **and** the customer API (`/api/customer/...`). Integrates Supabase (Postgres), Geidea payments, push notifications. | [`admin-dashboard/AGENTS.md`](admin-dashboard/AGENTS.md) |
| [`customer-app/`](customer-app/) | Flutter (Dart 3.12, Material 3) | The customer-facing mobile app. A thin client over the customer API. Anonymous session token; sign-in is optional and offered once, after checkout. | [`customer-app/AGENTS.md`](customer-app/AGENTS.md) |

## How the two apps relate

The Flutter `customer-app` is a **thin client** over the customer API served by
`admin-dashboard`'s Express backend. It calls `/api/customer/...` endpoints
(session, home, cocktails, cocktail-finder, shop, cart, checkout, orders,
favorites, spirits, profile, notifications) and holds no business logic or
offline data.

```
┌─────────────────┐        HTTPS /api/customer/...        ┌───────────────────────────┐
│  customer-app   │  ───────────────────────────────────▶ │  admin-dashboard (server)  │
│    (Flutter)    │                                        │   Express + Supabase       │
└─────────────────┘                                        └───────────────────────────┘
                                                                     ▲
                                                            admin / warehouse / cart
                                                              (React dashboard + API)
```

The Flutter app's base URL is **hardcoded** to
`https://ebtl-admin-dashboard.onrender.com`
(`customer-app/lib/core/network/api_config.dart`) — there is no env/flavor
switching on the client.

**Key consequence for agents:** `admin-dashboard` owns the customer API
contract. A `customer-app` task that needs a new field or endpoint requires a
**backend change in `admin-dashboard/server/routes/customerRoutes.js`**, and a
change to those routes is a potentially breaking change for `customer-app`.
Keep the two in sync and call out cross-app impact explicitly.

## Working in this repo

Each app is **self-contained — `cd` into it and work there.** The two apps
share nothing at the code level (no shared package, no common tooling); the
only coupling is the runtime HTTP contract above.

```bash
# Back-office web + backend API
cd admin-dashboard
cp .env.example .env      # fill in Supabase, Geidea, admin users, etc.
npm install
npm run dev               # Express + Vite, concurrently

# Customer mobile app
cd customer-app
flutter pub get
flutter run
```

Full commands, env vars, architecture, and conventions live in each app's own
`AGENTS.md` — **always read the app-level file before making changes**; it is
more specific and takes precedence over this overview.

## Conventions common to both apps

- **EGP everywhere**, `Africa/Cairo` time zone, English-only copy (no i18n).
- **Deliberately minimal dependencies.** Neither app uses a heavy framework
  stack — no ORM/router/state-library on the web side, no state-management or
  codegen on the Flutter side. Do **not** add packages unless the task
  explicitly calls for it.
- **Keep diffs minimal and scoped.** Both codebases favor readable, explicit
  code over abstraction; match the surrounding style rather than introducing
  new patterns.
- **Secrets are server-only.** The Supabase service-role key, `SESSION_SECRET`,
  and all Geidea/push credentials live in `admin-dashboard` env and must never
  reach a client. Never commit a real `.env`.
- **Report honestly.** `admin-dashboard` has no test suite (verify via
  `npm run build` + server boot); `customer-app` uses `flutter analyze` and may
  run in environments without the Flutter SDK installed. If a check couldn't
  run, say so — don't claim it passed.

## Repository etiquette

- Preserve the two-directory split and each app's git history; don't move code
  between apps.
- The Postgres schema is managed in Supabase and is **not** in this repo —
  don't assume you can migrate it from here; check how existing routes query it.
- Landing-page and static assets for the web app live under
  `admin-dashboard/public/`.

When in doubt about which app a task belongs to: **anything the customer
touches on their phone is `customer-app` UI, but the data behind it — and any
API/contract change — is `admin-dashboard`.**


## Codex Cloud Git workflow

When running a code-changing task in Codex Cloud:

- The task must be started with `main` selected as its starting branch.
- Before the first file edit, create and switch to a unique branch named
  `codex/<short-task-slug>` from the currently checked-out `main` commit.
- Never commit directly to `main`.
- After validation, commit all intended changes with a descriptive commit message.
- Push the branch to `origin` and configure upstream tracking.
- Do not create or open a pull request unless the user explicitly asks for one.
- If branch creation, commit, or push fails, preserve the task diff, report the
  failure, and do not open a pull request as a fallback.
