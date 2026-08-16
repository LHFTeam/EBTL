-- EBTL: Scan to Collect — the handoff log behind QR-gated order pickup
--
-- The Postgres schema is managed in Supabase and is NOT otherwise tracked in
-- this repo (see AGENTS.md). This file is the record of a migration already
-- applied to the live project (`apply_migration`, ledger version
-- 20260816004356). It is idempotent and safe to re-run.
--
-- Why: until now the last hop of a cart order — `ready` → `completed` — was a
-- button on the cart-operations screen. Anyone with the orders area could tap
-- it, nothing tied the tap to the customer standing at the cart, and the only
-- trace left behind was orders.completed_at. A bag handed to the wrong group
-- and a bag handed over correctly are the same row.
--
-- Pickup is now gated on the customer showing a short-lived signed code from
-- the app (server/lib/pickupToken.js) which the attendant scans. This table is
-- the record of that moment: who handed over, at which cart, and by which of
-- the three routes. There is deliberately no column on `orders` — an order has
-- one handoff in the happy path, but a log that can hold a second row is what
-- makes a double-handoff investigable rather than invisible.
--
-- The three methods are a health metric, not just an audit field:
--   qr          the normal path — camera scanned the customer's code
--   short_code  the same token typed as six digits (dim screen, no camera)
--   override    no code at all (dead battery, reinstalled app). Requires a
--               reason, and its rate is the number that says whether this
--               process is working. The app has no customer login — just an
--               anonymous device token — so a reinstall means a customer who
--               genuinely cannot produce a code. Watch this climb.
--
-- employee_id is nullable on purpose: ADMIN_USERS logins (the env-defined
-- break-glass accounts in server/config/appConfig.js) have no employees row.
-- staff_label carries the name either way, and outlives a deleted employee,
-- which is exactly when an audit row is most worth having.

create table if not exists public.order_handoffs (
    id uuid default gen_random_uuid() not null,
    order_id uuid not null,
    location_id uuid not null,
    employee_id uuid,
    staff_label text not null,
    method text not null,
    reason_code text,
    token_nonce text,
    created_at timestamp with time zone default now() not null
);

alter table public.order_handoffs enable row level security;

alter table public.order_handoffs
    drop constraint if exists order_handoffs_pkey;
alter table public.order_handoffs
    add constraint order_handoffs_pkey primary key (id);

alter table public.order_handoffs
    drop constraint if exists order_handoffs_order_id_fkey;
alter table public.order_handoffs
    add constraint order_handoffs_order_id_fkey
    foreign key (order_id) references public.orders(id) on delete cascade;

alter table public.order_handoffs
    drop constraint if exists order_handoffs_location_id_fkey;
alter table public.order_handoffs
    add constraint order_handoffs_location_id_fkey
    foreign key (location_id) references public.locations(id);

-- The employee may be removed later; the row stays, and staff_label still says
-- who it was.
alter table public.order_handoffs
    drop constraint if exists order_handoffs_employee_id_fkey;
alter table public.order_handoffs
    add constraint order_handoffs_employee_id_fkey
    foreign key (employee_id) references public.employees(id) on delete set null;

alter table public.order_handoffs
    drop constraint if exists order_handoffs_staff_label_not_blank;
alter table public.order_handoffs
    add constraint order_handoffs_staff_label_not_blank check ((length(btrim(staff_label)) > 0));

alter table public.order_handoffs
    drop constraint if exists order_handoffs_method_valid;
alter table public.order_handoffs
    add constraint order_handoffs_method_valid
    check ((method = any (array['qr'::text, 'short_code'::text, 'override'::text])));

alter table public.order_handoffs
    drop constraint if exists order_handoffs_reason_code_valid;
alter table public.order_handoffs
    add constraint order_handoffs_reason_code_valid
    check ((reason_code is null or reason_code = any (array[
        'dead_phone'::text,
        'no_app'::text,
        'app_error'::text,
        'staff_error'::text,
        'other'::text
    ])));

-- A reason is what makes an override reviewable, so it is required there and
-- meaningless anywhere else. Codes carry a nonce for the same reason — it is
-- what the replay guard below keys on.
alter table public.order_handoffs
    drop constraint if exists order_handoffs_reason_matches_method;
alter table public.order_handoffs
    add constraint order_handoffs_reason_matches_method
    check ((method = 'override'::text) = (reason_code is not null));

alter table public.order_handoffs
    drop constraint if exists order_handoffs_nonce_matches_method;
alter table public.order_handoffs
    add constraint order_handoffs_nonce_matches_method
    check ((method = 'override'::text) or (token_nonce is not null));

-- Replay guard. A code that has already closed an order cannot close another,
-- even inside its ninety-second window. The compare-and-swap in
-- transition_cart_order_status already stops the same order completing twice;
-- this stops one captured code being replayed at all.
create unique index if not exists idx_order_handoffs_token_nonce
    on public.order_handoffs using btree (token_nonce)
    where (token_nonce is not null);

create index if not exists idx_order_handoffs_order
    on public.order_handoffs using btree (order_id, created_at desc);

-- Backs the operational read: "how were handoffs made at this cart today".
create index if not exists idx_order_handoffs_location_created
    on public.order_handoffs using btree (location_id, created_at desc);

create index if not exists idx_order_handoffs_method_created
    on public.order_handoffs using btree (method, created_at desc);

-- Mirrors the other operational tables: the server holds the service-role key
-- and bypasses RLS, so this matters only for any other client.
drop policy if exists "Staff can read order_handoffs" on public.order_handoffs;
create policy "Staff can read order_handoffs" on public.order_handoffs for select to authenticated
    using (is_staff());

drop policy if exists "Staff can create order_handoffs" on public.order_handoffs;
create policy "Staff can create order_handoffs" on public.order_handoffs for insert to authenticated
    with check (is_staff());

comment on table public.order_handoffs is
    'One row per completed pickup handoff: who released the order, at which cart, and whether the customer proved it with a scanned QR, a typed six-digit code, or a staff override. Append-only; the override rate is the health metric for the pickup process.';

comment on column public.order_handoffs.staff_label is
    'Name of the attendant at handoff time. Snapshot, so it survives employee_id being nulled, and covers ADMIN_USERS logins that have no employees row.';

comment on column public.order_handoffs.method is
    'How the customer was proven: qr (scanned), short_code (six digits typed from the same token), override (no code — requires reason_code).';

comment on column public.order_handoffs.token_nonce is
    'Nonce of the pickup token spent on this handoff. Uniquely indexed, so a captured code cannot be replayed. Null only for overrides, which have no token.';
