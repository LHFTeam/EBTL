# AGENTS.md

Guidance for AI coding agents (and new contributors) working in the
`admin-dashboard` directory of the EBTL monorepo.

## What this app is

`admin-dashboard` is **two things served from one Node process**:

1. **The back-office web app** — a React 19 + Vite single-page app used by
   staff (admins, managers, warehouse, cart operators, prep) to run the
   business: dashboard KPIs, orders, inventory, stock transfers, ingredients,
   the cocktail/product catalog, liquors, the shop, locations and employees.
2. **The backend API** — an Express server that powers _both_ the admin SPA
   (`/api/...`, cookie session) **and** the public customer mobile app
   (`/api/customer/...`, bearer token). It also serves the marketing landing
   page and integrates Supabase (Postgres), Geidea payments, and push
   notifications.

The Flutter [`customer-app`](../customer-app/) is a thin client over the
`/api/customer/*` routes defined here. **This app is the source of truth for
the customer API contract** — if a customer-app task implies a backend change,
it lands here.

Everything is EGP, and the business time zone is `Africa/Cairo`
(see `BUSINESS_TIME_ZONE` in `server/routes/customerRoutes.js`).

## Tech stack and constraints

- **Runtime:** Node `>=22 <23`, npm `>=10 <11` (pinned in `package.json`
  `engines` and `.node-version` = `22.22.0`). ES modules everywhere
  (`"type": "module"`); use `import`, not `require`.
- **Backend:** Express 4, `@supabase/supabase-js`, `zod` for input
  validation, `helmet` + `compression` + `morgan`. Payments use the native
  `fetch` + `crypto` (no SDK). No ORM — all DB access is the Supabase JS
  client against an **externally-managed** Postgres schema — it is owned by the
  Supabase dashboard, and you should not assume you can change it from here.
  The repo now carries a **read-only capture** of it in `db/schema/` (see the
  README there) plus hand-written migrations in `db/migrations/`, so the shape
  of the data model is reviewable in diffs. Neither is the source of truth, and
  neither is applied automatically. `db/tools/dump_schema.sql` refreshes the
  capture.
- **Frontend:** React 19, Vite 6, `lucide-react` for icons. **No router
  library, no state-management library, no data-fetching library, no CSS
  framework, no TypeScript.** Routing is a hand-rolled tab switch, state is
  `useState` + a tiny `useLoad` hook, styling is one global `src/styles.css`
  with CSS variables. Keep it that way unless a task explicitly asks
  otherwise.
- **Dependencies are deliberately minimal.** Do not add packages (Redux,
  React Query, Tailwind, axios, an ORM, a test runner, …) unless the task
  calls for it.
- **There is no test suite and no linter config** in this app. "Passing"
  means the server boots, `npm run build` succeeds, and the flows you touched
  work. Do not claim tests passed — there are none.

## Commands

Run from inside `admin-dashboard/`:

```bash
cp .env.example .env      # then fill in real values (see below)
npm install
npm run dev               # Express (nodemon) + Vite client, concurrently
npm run build             # production client build → dist/
npm start                 # production server (NODE_ENV=production, serves dist/)
```

- `npm run dev:server` / `npm run dev:client` run the halves separately.
- In **dev**, Vite serves the SPA (with HMR) and Express serves the API; the
  client calls same-origin `/api/...` (see `src/api/client.js`, `API = ''`),
  so run both.
- In **prod** (or whenever `dist/index.html` exists), Express serves the built
  client itself and there is no Vite. See the static-serving block in
  `server/app.js`.

## Environment variables

`server/config/appConfig.js` reads and validates env at boot. Key ones
(full list + comments in `.env.example`):

- `PORT` (default `10000`), `NODE_ENV`.
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` — **required**; the server
  throws on boot if missing. This is the service-role key, so the backend has
  full DB access and **must never** be exposed to the client.
- `SESSION_SECRET` — HMAC key for both admin and customer tokens. Required in
  production (boot throws if left at the dev default).
- `ADMIN_USERS` — JSON array of env-defined fallback logins
  (`{username,password,role,name}`), checked before the DB `employee_credentials`
  table. Handy for bootstrapping; plaintext, so treat as break-glass.
- `PAYMENT_MODE` — `live` (configured gateway) or `demo` (orders confirm
  immediately with no real payment). Anything not `demo` normalizes to `live`.
- `PAYMENT_PROVIDER` — `stripe` (default) or `geidea`.
- `GEIDEA_*` — payment gateway config; `geideaIsConfigured()` gates real card
  sessions. `GEIDEA_IS_SANDBOX` defaults true.
- `PUSH_NOTIFICATIONS_ENABLED` + `PUSH_PROVIDER` (`fcm` | `expo` | `none`) and
  the provider creds. When disabled, `sendPushToCustomer` returns a `skipped`
  result instead of erroring.

## Repository layout

```
admin-dashboard/
  index.html              # SPA entry. Inline boot script shows a friendly
                          # error screen + POSTs client errors to /api/client-error.
  vite.config.js          # just @vitejs/plugin-react
  public/
    landing.html          # marketing page served at "/"
    landing-assets/       # its css/js/images (webp heroes)
  server/
    index.js              # createApp().listen(PORT)
    app.js                # THE express wiring: middleware order, route mounting,
                          # static + SPA-fallback serving. Read this first.
    config/appConfig.js   # env parsing/validation + roleAccess (RBAC) + the
                          # canonical status/role/type enum lists + can()/envUsers()
    middleware/auth.js    # auth (decode session → req.user), requireAuth,
                          # requireArea(area), requireEmployeeSession
    lib/
      supabase.js         # single service-role Supabase client (export `supabase`)
      supabaseResponse.js # sb(promise, res) — run a query, 400 on error, else data
      session.js          # HMAC-signed admin cookie (ebtl_admin), 12h expiry
      passwords.js        # pbkdf2 hash/verify for employee_credentials
      geidea.js           # Geidea session create + callback signature verify
      notifications.js    # customer notifications + FCM/Expo push
      objectUtils.js      # clean() / normalizeEmptyStrings()
    routes/
      authRoutes.js       # /login /logout /me /me/password
      dashboardRoutes.js  # /dashboard KPI aggregate
      locationRoutes.js employeeRoutes.js ingredientRoutes.js
      cocktailRoutes.js   # cocktails AND additional-products (shared handlers)
      liquorRoutes.js shopRoutes.js inventoryRoutes.js transferRoutes.js
      orderRoutes.js      # admin/cart-operations order management
      customerRoutes.js   # ~5.6k lines: the ENTIRE /api/customer/* + payments API
  src/
    main.jsx              # React root + startup-error handling
    App.jsx               # auth gate: /api/me → Login | PasswordChange | Shell
    layout/Shell.jsx      # sidebar nav + active-tab page host + cart-location switch
    api/client.js         # api(path, options) fetch wrapper (credentials: include)
    config/
      navigation.jsx      # nav sections/tabs (+ icons, allowedRoles)
      constants.js        # small client-side enum mirrors
    hooks/useLoad.js      # {loading,error,data,reload} data-loading hook
    components/ui.jsx      # Section, Loading, Message, Kpi, SimpleTable primitives
    features/auth/         # Login, PasswordChange
    pages/                 # one file per tab (Dashboard, Orders, Inventory, …)
    utils/format.js        # money/date/slug/bool/tags helpers
    styles.css             # the ONLY stylesheet (CSS variables at :root)
```

## Backend architecture

### Middleware order (in `server/app.js`)

`helmet` → `compression` → `morgan` → `express.json({limit:'8mb'})` →
**normalize empty strings on POST only** → `auth` (populate `req.user`) →
health/error endpoints → all `/api` routers → static + SPA fallback.

Two subtle, deliberate behaviors — preserve them:

- Empty-string normalization runs on **POST bodies only**. `PATCH`/`PUT` keep
  `''` so update routes can convert it to `null` and intentionally clear
  optional columns.
- The SPA is served for `/login`, `/dashboard*`, `/admin*`; unknown paths
  redirect to `/`; `/` serves the **landing page** (`landing.html`), not the
  app.

### Auth, sessions and RBAC

- Two independent auth schemes share `SESSION_SECRET`:
  - **Admin/staff:** HMAC-signed `ebtl_admin` **cookie** (`lib/session.js`),
    12-hour expiry, `HttpOnly; SameSite=Lax`. `auth` decodes it into
    `req.user` on every request.
  - **Customer:** HMAC-signed bearer token (`x-ebtl-customer-token` header,
    `Authorization: Bearer`, or `ebtl_customer` cookie), handled entirely
    inside `customerRoutes.js` (`encodeCustomerToken`/`decodeCustomerToken`).
    Responses echo a refreshed token in the `X-EBTL-Customer-Token` header —
    the Flutter app persists it.
- **Login precedence:** env `ADMIN_USERS` first, then the
  `employee_credentials` table (pbkdf2 via `lib/passwords.js`). Employees can
  be forced to change password (`must_change_password`) — `requireArea`
  blocks them until they do.
- **Authorization** is `roleAccess` in `appConfig.js` (role → allowed area
  keys, `admin` = `['*']`). Guard admin routes with `requireArea('<area>')`;
  the area keys line up with the frontend nav tab keys. `can(role, area)` is
  the single check used on both server and (mirrored) client.

### Data access pattern

- One shared **service-role** client (`lib/supabase.js`). Never create another.
- Prefer the `sb(query, res)` helper (`lib/supabaseResponse.js`): it awaits the
  query, and on error logs + sends `400 {error}` and returns `null` (so callers
  do `const rows = await sb(...); if (!rows) return;`). Many routes also inline
  the `{data,error}` check — match whichever the surrounding file uses.
- Validate input with `zod` at the top of a handler (see `authRoutes.js`,
  `customerRoutes.js`); `safeParse` → `400` on failure.
- Use `clean()` to strip `undefined`/`''` from insert/update payloads.
- The Postgres schema (tables like `orders`, `employees`,
  `employee_credentials`, `products`, `ingredients`, `inventory_balances`,
  `stock_transfers`, `locations`, `customer_notifications`,
  `customer_push_tokens`, and views like `v_daily_sales_by_location`,
  `v_inventory_low_stock`) lives in Supabase, **not** in this repo. Assume it
  exists; don't invent columns without checking how existing routes query them.

### Customer API & payments (`customerRoutes.js`)

This one file is the whole customer surface: session, home, shop, cocktails,
cocktail-finder, cart, checkout (quote + place-order), orders, order
status/payment-status polling, favorites, addresses, profile, notifications,
push-token registration, and the Geidea payment callback. It is large by
design — **follow the local structure**; don't refactor it wholesale.

- **Payments:** `PAYMENT_MODE=demo` confirms orders without a gateway;
  `live` uses Geidea. Session creation, amount formatting, and **callback
  signature verification** all live in `lib/geidea.js` — the callback
  (`POST /api/payments/geidea/callback`) is unauthenticated and trusts the
  HMAC signature, so never weaken `verifyGeideaCallbackSignature`. Orders carry
  an `idempotency_key`; payment status is polled by the app.
- **Cart lifecycle:** placing a gateway order does **not** touch the cart — the
  customer has not paid yet and may dismiss the payment sheet. The cart is
  emptied and marked `converted` only from a payment-success path, via
  `convertCartAfterPayment` (demo placement, Geidea callback, Stripe webhook),
  using the `cart_id`/`cart_item_ids` recorded on `payments.raw_payload`. Do
  not move cart clearing back to placement.
- **Abandoned checkouts:** an order that never gets paid would stay at
  `pending_payment` forever, so `lib/pendingOrderCleanup.js` sweeps them from an
  unref'd timer started in `index.js` and marks them **`expired`**. Never
  delete them — a payment that settles late must still find its order so the
  money can be flagged and reconciled. Before expiring, it cancels the Stripe
  PaymentIntent; if Stripe reports the intent `succeeded`/`processing`, or the
  order has a `paid` payment row, or the cancel call fails, the order is left
  pending for the next sweep. `PENDING_ORDER_MAX_AGE_MINUTES` (30) is the
  customer's payment window, not a webhook grace period.
- **Late payments:** `updateOrderForPaymentResult` returns `confirmed`, which is
  false when the order was not sitting at `pending_payment`. Fulfillment side
  effects (promotion redemption, referral/credit settlement, cart conversion)
  run only when it is true. If the order is `expired`/`cancelled`,
  `flagPaidOrderForReview` marks `payments.raw_payload.needs_reconciliation` and
  logs — a human decides refund vs. reinstate. Replaying place-order against
  such an order returns 409 `error_code: checkout_expired`, which the app uses
  to start a fresh checkout.
- **Notifications:** order status changes fan out through
  `lib/notifications.js` (`createCustomerNotification` → persist + push via FCM
  or Expo, gated by env). `notifyOrderReadyForPickup` dedupes on
  `order:<id>:ready_for_pickup`.

## Frontend architecture

### Boot & auth flow

`index.html` (inline error UI) → `main.jsx` (React root, catches startup
errors) → `App.jsx`. `App` calls `GET /api/me` once and renders one of:
`Login`, `PasswordChange` (when `must_change_password`), or the lazy-loaded
`Shell`. "Routing" is just `window.history.replaceState` between `/login` and
`/dashboard` — there is no router.

### Shell & navigation

`Shell.jsx` renders the sidebar from `config/navigation.jsx` filtered by the
user's `access` array and role (`allowedRoles`), tracks the active tab in
local state, and conditionally renders the matching page component. It also
owns the **cart-operations location switcher** (persisted in `localStorage`
under `ebtl.cart_operations.location_id`) that it passes into `Orders`.
Adding a page = add a tab to `navigation.jsx` + a render branch in `Shell.jsx`
+ (for RBAC) an area key in `roleAccess`.

### Page pattern (follow it)

Every page is a default-exported component that:

1. Loads data with `useLoad(() => api('/api/<area>'))` → `{loading, error,
   data, reload}`.
2. Renders `<Loading error={error} />` while loading/on error.
3. Lays out with the `ui.jsx` primitives — `Section`, `SimpleTable`, `Kpi`,
   `Message` — and forms that `POST`/`PATCH` via `api(...)` then call
   `reload()`.

`Cocktails.jsx` is the big one: it's a **parametrized** CRUD page reused by
`AdditionalProducts.jsx` (same component, different `listApiPath`/labels/flags).
Extend via its props before copy-pasting.

### Client conventions

- All HTTP goes through `api(path, options)` in `src/api/client.js`
  (`credentials: 'include'`, JSON headers, throws `Error(data.error)` on
  non-2xx). Don't call `fetch` directly in pages.
- Formatting (`money`, `dt`, `d`, `slugify`, `toBool`, `splitTags`) lives in
  `utils/format.js` — reuse, don't reimplement. Money is `EGP <n>`.
- Styling is `styles.css` only, driven by the `:root` CSS variables
  (`--bg/--card/--ink/--accent/--danger`, etc.) and shared class names
  (`card`, `grid2`, `miniForm`, `error`, `success`, `muted`, `kpi`,
  `tableWrap`). Add classes there; **no inline styles** in pages beyond the
  boot/error fallbacks, and no CSS-in-JS.
- Icons come from `lucide-react`.

## Domain glossary

- **Areas / tabs** — the RBAC + nav unit: `dashboard`, `orders`, `inventory`,
  `transfers`, `ingredients`, `cocktails`, `additional-products`, `liquors`,
  `shop`, `locations`, `employees`. Defined once in `roleAccess`
  (`appConfig.js`) and mirrored in `navigation.jsx`.
- **Roles** — `prep` < `cart_operator` < `warehouse` < `supervisor` <
  `manager` < `admin` (see `employeeRoles`). `admin` sees everything.
- **Cart operations** — the beach-cart order workflow; a cart operator works a
  single beach-cart location (the switcher). Locations are
  `central_warehouse` or `beach_cart` (`locationTypes`).
- **Products** — one catalog table spans `productTypes` (`cocktail`, `snack`,
  `essential`, `bundle`, `add_on`) with `productStatuses`
  (`draft`/`active`/`archived`). Cocktails and "additional products" are the
  same rows viewed through different UI.
- **Order lifecycle** — `orderStatuses`: draft → pending_payment → confirmed →
  preparing → ready → out_for_delivery → completed (or cancelled/refunded).
  `paymentStatuses`: unpaid/pending/paid/failed/refunded/partially_refunded.
  `transferStatuses`: draft/picked/in_transit/received/cancelled. These enum
  lists are canonical in `appConfig.js` — import them, don't hardcode strings.

## Working agreements for agents

1. **Match the existing style.** Plain Express handlers, `zod` validation, the
   shared Supabase client + `sb()`/`clean()` helpers on the server; `useLoad` +
   `ui.jsx` + `api()` + `styles.css` on the client. Introducing a new
   architectural pattern (router, store, ORM, test runner) needs an explicit
   request.
2. **Never expose secrets to the client.** The service-role key and all
   `GEIDEA_*`/push creds are server-only. The customer/admin tokens are the
   only auth material that crosses the wire.
3. **Preserve security-critical code:** HMAC signing/verification in
   `session.js` and `geidea.js`, pbkdf2 in `passwords.js`, and the
   `timingSafeEqual` comparisons. Don't loosen them.
4. **Respect the POST-vs-PATCH empty-string rule** in `app.js` — updates rely
   on `''` reaching the route to clear columns.
5. **The DB schema is external.** Don't fabricate tables/columns; check how
   current routes query Supabase, and flag schema needs rather than faking them.
6. **Verify before claiming success:** `npm run build` should pass and the
   server should boot (it throws on missing Supabase/session config). There are
   no automated tests — say so honestly instead of claiming they passed. **CI**
   (`.github/workflows/ci.yml`) is the only gate on a PR touching this app: it
   runs `npm ci` + `npm run build` and nothing else (no test runner, no
   linter). Keep the build green.
7. **The customer API here is a contract** with the Flutter app. Changing
   request/response shapes under `/api/customer/*` is a breaking change for
   `customer-app`; keep them in sync and call it out.
8. Keep diffs minimal and scoped; this codebase favors readable, explicit code
   over abstraction.
