-- Cifelli's Order Hub: Supabase schema.
--
-- Run this once in your Supabase project's SQL Editor (Project > SQL Editor
-- > New query, paste this whole file, Run). Safe to re-run: every statement
-- is idempotent (create if not exists / drop-then-create for policies).
--
-- Column names intentionally match the app's JS field names exactly
-- (camelCase, quoted) so the frontend needs no field-name translation.

create extension if not exists pgcrypto;

create table if not exists public.orders (
  id            uuid primary key default gen_random_uuid(),
  ticket        text not null,
  source        text not null default 'customer' check (source in ('customer','pos')),
  "customerName" text not null default '',
  phone         text not null default '',
  address       text not null default '',
  notes         text not null default '',
  "orderType"   text not null default 'pickup' check ("orderType" in ('pickup','delivery','phone','walkin')),
  "payMethod"   text not null default 'cash' check ("payMethod" in ('cash','card')),
  items         jsonb not null default '[]'::jsonb,
  subtotal      numeric(10,2) not null default 0,
  tax           numeric(10,2) not null default 0,
  tip           numeric(10,2) not null default 0,
  total         numeric(10,2) not null default 0,
  status        text not null default 'new' check (status in ('new','preparing','ready','out_for_delivery','completed','cancelled')),
  driver        text,
  -- Payment scaffold: not wired to a real processor yet. See
  -- order/payments.js for where a Stripe (or similar) integration plugs
  -- in. "cash"/"card" orders today are always paymentStatus 'unpaid'
  -- (paid in person); once real card processing is added this becomes
  -- 'paid' the moment the processor confirms the charge.
  "paymentStatus"   text not null default 'unpaid' check ("paymentStatus" in ('unpaid','paid','refunded','failed')),
  "paymentProvider" text,
  "paymentIntentId" text,
  -- SMS notification scaffold: not wired to a real sender yet. See
  -- supabase/functions/send-order-sms/. A customer opting in stores
  -- their consent here; smsStatus tracks whether a text was actually
  -- sent once that function is implemented.
  "phoneOptIn"  boolean not null default false,
  "smsStatus"   text not null default 'not_sent' check ("smsStatus" in ('not_sent','sent','failed')),
  -- Delivery distance/ETA, computed client-side from a free geocoder
  -- when the customer enters a delivery address (see order/geo.js).
  -- Null for pickup orders, or if the lookup failed/was never run.
  "deliveryMiles"   numeric(6,2),
  "deliveryEtaMins" integer,
  "cancelReason"    text,
  -- Driver assignment + customer rating. driverId links to the drivers
  -- table below (added once a driver claims the delivery); the
  -- "driver" text column above is kept as-is for backward
  -- compatibility with existing rows and as a plain display fallback.
  "driverId"           uuid,
  "driverRating"       smallint check ("driverRating" between 1 and 5),
  "driverRatingComment" text,
  "createdAt"   bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "updatedAt"   bigint not null default (extract(epoch from now()) * 1000)::bigint
);

create index if not exists orders_status_idx on public.orders (status);
create index if not exists orders_created_idx on public.orders ("createdAt");

-- Migration: add columns introduced after the table may have already been
-- created on your project. Safe to re-run; each is a no-op once applied.
alter table public.orders add column if not exists tip numeric(10,2) not null default 0;
alter table public.orders add column if not exists "paymentStatus" text not null default 'unpaid';
alter table public.orders add column if not exists "paymentProvider" text;
alter table public.orders add column if not exists "paymentIntentId" text;
alter table public.orders add column if not exists "phoneOptIn" boolean not null default false;
alter table public.orders add column if not exists "smsStatus" text not null default 'not_sent';
alter table public.orders add column if not exists "deliveryMiles" numeric(6,2);
alter table public.orders add column if not exists "deliveryEtaMins" integer;
alter table public.orders add column if not exists "cancelReason" text;
alter table public.orders add column if not exists "driverId" uuid;
alter table public.orders add column if not exists "driverRating" smallint;
alter table public.orders add column if not exists "driverRatingComment" text;

do $$ begin
  alter table public.orders add constraint orders_driverrating_check
    check ("driverRating" between 1 and 5);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.orders add constraint orders_paymentstatus_check
    check ("paymentStatus" in ('unpaid','paid','refunded','failed'));
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.orders add constraint orders_smsstatus_check
    check ("smsStatus" in ('not_sent','sent','failed'));
exception when duplicate_object then null;
end $$;

-- Keep updatedAt current on every row change, even a direct SQL edit in the
-- Supabase dashboard, as a backstop (the app also sets it explicitly).
create or replace function public.set_orders_updated_at()
returns trigger as $$
begin
  new."updatedAt" = (extract(epoch from now()) * 1000)::bigint;
  return new;
end;
$$ language plpgsql;

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function public.set_orders_updated_at();

-- Realtime: let the app subscribe to live changes on this table.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;

-- Row Level Security.
--
-- IMPORTANT CHANGE: this project now has three kinds of Supabase Auth
-- user, not two. Originally "authenticated" meant "signed-in staff" and
-- every policy below trusted that. Now that customers can also create
-- an account (see the customers table below), a customer who signs up
-- becomes "authenticated" too — the exact same Postgres role staff use.
-- If the old policies (grant everything to "authenticated") stayed as
-- they were, any customer who created an account would have been able
-- to read and edit every order in the shop, not just their own. The
-- `staff` allowlist table and `is_staff()` function below exist purely
-- to tell those two kinds of "authenticated" apart. Nothing about
-- customer accounts is safe without this.
--
-- The Customer Kiosk (order/) is public and talks to Supabase with the
-- anon key. Signed-out customers can only ever CREATE an order. Signed-
-- in customers (see customers table) can also read (not edit) their own
-- past orders, matched by phone number. The Staff Hub (staff/) requires
-- a Supabase Auth sign-in AND a row in the staff table before it can
-- read or update orders at all.
--
-- Create staff accounts in the Supabase dashboard under Authentication >
-- Users, same as before, but there is now a second required step: add
-- that user's id to the staff table (see "Add a staff member" below),
-- or they'll be able to sign in but every screen will show empty/denied.
alter table public.orders enable row level security;

-- Staff allowlist. A row here is what makes an authenticated user
-- "staff" rather than "a customer who happens to have an account".
create table if not exists public.staff (
  id uuid primary key references auth.users(id) on delete cascade,
  "isDriver" boolean not null default false,
  "isAdmin"  boolean not null default false,
  active     boolean not null default true,
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table public.staff add column if not exists "isAdmin" boolean not null default false;
alter table public.staff add column if not exists active boolean not null default true;
alter table public.staff enable row level security;
grant select, insert, update on public.staff to authenticated;

-- is_staff()/is_admin() are defined here, before the policies below, and
-- used BY them (rather than each policy re-querying public.staff inline)
-- specifically to avoid infinite recursion: a policy on public.staff
-- whose own USING clause selects from public.staff re-triggers that same
-- policy on every row check, and Postgres errors with "infinite
-- recursion detected in policy for relation staff" the moment anyone
-- queries it. security definer is what breaks the loop -- the function
-- runs with its owner's privileges, bypassing RLS for its own internal
-- lookup, so the outer policy's call to it doesn't recurse.
create or replace function public.is_staff()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.staff where id = auth.uid() and active);
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.staff where id = auth.uid() and active and "isAdmin");
$$;

drop policy if exists "staff_select_staff" on public.staff;
create policy "staff_select_staff" on public.staff
  for select to authenticated
  using (public.is_staff());

-- Only an admin can add or edit staff rows through the app (this is
-- what lets Driver Roster's "Approve" button work without anyone
-- needing the Supabase dashboard for routine approvals). Adding the
-- very first admin still has to happen by hand in the SQL Editor —
-- see "Bootstrap your first admin" below — there's no safe way for
-- the app to grant the very first admin permission to itself.
drop policy if exists "staff_admin_insert" on public.staff;
create policy "staff_admin_insert" on public.staff
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "staff_admin_update" on public.staff;
create policy "staff_admin_update" on public.staff
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());
-- No delete policy: to remove someone's access, an admin sets
-- active = false via update (above) rather than deleting the row —
-- keeps a record of who used to have access instead of erasing it.

-- MIGRATION: if you already had staff signing in before this table
-- existed, run this once so your existing staff don't get locked out
-- (everyone who has ever signed in becomes staff; safe to run more
-- than once, it just re-adds the same rows):
--   insert into public.staff (id)
--   select id from auth.users
--   on conflict (id) do nothing;
-- Do NOT run that after customer accounts exist — it would make every
-- customer staff too. Run it once, now, before customers start signing
-- up, or hand-pick rows in the Table Editor instead.

-- BOOTSTRAP YOUR FIRST ADMIN: the policies above mean only an admin
-- can create staff/approve drivers through the app — which means the
-- very first admin has to be set by hand, once, here in the SQL
-- Editor (nothing after this needs the SQL Editor again for routine
-- staff/driver approvals). Find your user id in Authentication > Users,
-- then:
--   update public.staff set "isAdmin" = true where id = '<your-user-id>';

-- Customers (optional accounts). Anonymous ordering never requires
-- this table — the order still gets created and the phone number still
-- ties it to a customer even with no account. This table only exists
-- for the customer who chooses to create an account, so their past
-- orders (matched by phone) show up automatically the first time they
-- sign in with that phone number on file.
create table if not exists public.customers (
  id uuid primary key references auth.users(id) on delete cascade,
  phone text not null default '',
  name text not null default '',
  email text,
  preferences jsonb not null default '{}'::jsonb,
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "updatedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists customers_phone_idx on public.customers (phone);
alter table public.customers enable row level security;
grant select, insert, update on public.customers to authenticated;
drop policy if exists "customers_self" on public.customers;
create policy "customers_self" on public.customers
  for all to authenticated
  using (id = auth.uid() or public.is_staff())
  with check (id = auth.uid());

drop trigger if exists customers_set_updated_at on public.customers;
create trigger customers_set_updated_at
  before update on public.customers
  for each row execute function public.set_orders_updated_at();

-- Drivers. Two ways a profile row here gets created:
--   1. Staff add one directly (Staff Hub > Driver Roster > Add Driver),
--      then create the driver's Supabase Auth login from the dashboard
--      the same way staff accounts are made, and separately add them
--      to the staff table with "isDriver" true.
--   2. The driver applies themselves at /staff/apply.html: they pick
--      their own email/password (creates their Supabase Auth login in
--      the same step) and fill in their own profile. That row starts
--      "approved" = false and grants no access at all — it's just an
--      application sitting in Driver Roster's "Pending" list until an
--      admin approves it, which is the one action that actually adds
--      them to the staff table and lets them sign in to anything.
-- Either way, being in this table does NOT by itself grant access —
-- only a matching, active row in the staff table does.
create table if not exists public.drivers (
  id uuid primary key default gen_random_uuid(),
  name text not null default '',
  phone text not null default '',
  email text not null default '',
  "carMake" text not null default '',
  "carModel" text not null default '',
  "carColor" text not null default '',
  "carPlate" text not null default '',
  notes text not null default '',
  active boolean not null default true,
  "authUserId" uuid references auth.users(id),
  approved boolean not null default false,
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "updatedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table public.drivers add column if not exists "authUserId" uuid references auth.users(id);
alter table public.drivers add column if not exists approved boolean not null default false;
-- Existing rows (added by staff directly, before self-apply existed)
-- were already trusted, so treat them as pre-approved rather than
-- retroactively hiding drivers who were already working. Only rows
-- with no linked auth account are "manually added by staff" — the
-- self-apply flow always sets authUserId, so this only back-fills the
-- old kind.
update public.drivers set approved = true where "authUserId" is null and approved = false;
create unique index if not exists drivers_email_idx on public.drivers (lower(email)) where email <> '';
alter table public.drivers enable row level security;
grant select, insert, update on public.drivers to authenticated;
drop policy if exists "drivers_staff_all" on public.drivers;
create policy "drivers_staff_all" on public.drivers
  for all to authenticated
  using (public.is_staff())
  with check (public.is_staff());

-- Self-apply: someone who just signed up (not staff yet, maybe never
-- will be) can create exactly one application row for themselves, and
-- can only ever see their own — never the roster, never other
-- applicants. They cannot set approved themselves (with check strips
-- it back to false regardless of what they send), so this never grants
-- access on its own — only an admin approving it (see Driver Roster)
-- does that, via the staff table insert, which has its own admin-only
-- policy above.
drop policy if exists "drivers_self_apply_insert" on public.drivers;
create policy "drivers_self_apply_insert" on public.drivers
  for insert to authenticated
  with check ("authUserId" = auth.uid() and approved = false);

drop policy if exists "drivers_self_select" on public.drivers;
create policy "drivers_self_select" on public.drivers
  for select to authenticated
  using ("authUserId" = auth.uid());

drop trigger if exists drivers_set_updated_at on public.drivers;
create trigger drivers_set_updated_at
  before update on public.drivers
  for each row execute function public.set_orders_updated_at();

do $$ begin
  alter table public.orders add constraint orders_driverid_fkey
    foreign key ("driverId") references public.drivers(id);
exception when duplicate_object then null;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'drivers'
  ) then
    alter publication supabase_realtime add table public.drivers;
  end if;
end $$;

-- Driver shifts: a simple clock-in/clock-out log, the basis for
-- schedule and hours-worked history. One open row (clockOut null) per
-- driver at a time.
create table if not exists public.driver_shifts (
  id uuid primary key default gen_random_uuid(),
  "driverId" uuid not null references public.drivers(id) on delete cascade,
  "clockIn" bigint not null,
  "clockOut" bigint,
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists driver_shifts_driver_idx on public.driver_shifts ("driverId");
alter table public.driver_shifts enable row level security;
grant select, insert, update on public.driver_shifts to authenticated;
drop policy if exists "driver_shifts_staff_all" on public.driver_shifts;
create policy "driver_shifts_staff_all" on public.driver_shifts
  for all to authenticated
  using (public.is_staff())
  with check (public.is_staff());

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'driver_shifts'
  ) then
    alter publication supabase_realtime add table public.driver_shifts;
  end if;
end $$;

-- Explicit grants on orders. RLS policies only ever narrow what a grant
-- already allows, they never grant access on their own (Postgres checks
-- table grants first, then RLS). Some Supabase projects don't hand the
-- anon and authenticated roles table privileges by default, which
-- surfaces as the exact same "violates row-level security policy"
-- error as a missing policy even though the policies below are
-- correct. These grants make sure that is never the cause. Safe to
-- re-run.
grant insert on public.orders to anon, authenticated;
grant select, update on public.orders to authenticated;

drop policy if exists "orders_insert_anyone" on public.orders;
drop policy if exists "orders_insert_public" on public.orders;
create policy "orders_insert_public" on public.orders
  for insert to anon, authenticated
  with check (true);

-- Staff can read every order. A signed-in customer can read only
-- orders that match the phone number on their own account — never
-- other customers' orders, and never by guessing an id.
drop policy if exists "orders_select_anyone" on public.orders;
drop policy if exists "orders_select_staff" on public.orders;
drop policy if exists "orders_select_staff_or_own" on public.orders;
create policy "orders_select_staff_or_own" on public.orders
  for select to authenticated
  using (
    public.is_staff()
    or (phone <> '' and phone = (select phone from public.customers where id = auth.uid()))
  );

-- Only staff update orders (status changes, driver assignment, etc.).
-- Customers never update an order directly — see rate_delivery() below
-- for the one narrow exception (rating a completed delivery), which
-- goes through a function instead of a blanket UPDATE grant.
drop policy if exists "orders_update_anyone" on public.orders;
drop policy if exists "orders_update_staff" on public.orders;
create policy "orders_update_staff" on public.orders
  for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

-- No delete policy: orders are never deleted from the app, only marked
-- 'cancelled' or 'completed'. That keeps a full history and avoids
-- accidental data loss. Delete manually in the dashboard if you ever need
-- to clear test data.

-- Customer delivery ratings. Anon has no UPDATE grant on orders at all
-- (see above), so rating a driver goes through this one narrow
-- function instead of opening UPDATE up generally. It only ever
-- touches driverRating/driverRatingComment, only on a completed
-- delivery, only once (can't be changed after), and only by whoever
-- knows both the ticket number and the phone number on the order —
-- printed on the receipt, not guessable from the order id alone.
create or replace function public.rate_delivery(
  p_ticket text, p_phone text, p_rating smallint, p_comment text
)
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare
  updated_count int;
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5';
  end if;
  update public.orders
    set "driverRating" = p_rating, "driverRatingComment" = p_comment
    where ticket = p_ticket
      and phone = p_phone
      and status = 'completed'
      and "orderType" = 'delivery'
      and "driverRating" is null;
  get diagnostics updated_count = row_count;
  return updated_count > 0;
end;
$$;
grant execute on function public.rate_delivery(text, text, smallint, text) to anon, authenticated;


-- =========================================================================
-- Register shifts (Till / End-of-day management, Staff Hub > Till)
-- =========================================================================
-- One row per till session: opened with a starting cash count, closed with
-- a counted cash amount and a snapshot of the computed cash/card/tip
-- report for that window (snapshotted, not recomputed later, so a shift's
-- history doesn't drift if orders are edited afterward). Generalizes the
-- driver_shifts shape above to the register instead of a driver.
create table if not exists public.register_shifts (
  id uuid primary key default gen_random_uuid(),
  "openedBy" uuid not null references auth.users(id),
  "openedByEmail" text not null default '',
  "startingCash" numeric(10,2) not null default 0,
  "openedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "closedBy" uuid references auth.users(id),
  "closedByEmail" text,
  "countedCash" numeric(10,2),
  "overShort" numeric(10,2),
  "closedAt" bigint,
  report jsonb,
  notes text not null default '',
  status text not null default 'open' check (status in ('open','closed')),
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);

-- Only one open register at a time, for a single-register shop: a partial
-- unique index on a constant expression means at most one row can ever
-- have status = 'open' simultaneously (a second insert while one is
-- already open violates the index instead of silently creating two).
create unique index if not exists register_shifts_one_open_idx
  on public.register_shifts ((1)) where status = 'open';
create index if not exists register_shifts_status_idx on public.register_shifts (status);

alter table public.register_shifts enable row level security;
grant select, insert, update on public.register_shifts to authenticated;
drop policy if exists "register_shifts_staff_all" on public.register_shifts;
create policy "register_shifts_staff_all" on public.register_shifts
  for all to authenticated
  using (public.is_staff())
  with check (public.is_staff());
-- No delete policy -- same reasoning as orders above: keep full shift
-- history, fix mistakes by hand in the dashboard rather than an undo UI.

-- =========================================================================
-- Staff presence ("who's online" indicator in the Staff Hub header)
-- =========================================================================
-- One row per staff member, upserted every ~20s while any Staff Hub
-- screen is open (and on every role switch) with their email and current
-- screen; someone's "online" if lastSeenAt is recent. A real table
-- rather than Supabase Realtime Presence deliberately -- Realtime
-- presence/broadcast channels aren't gated by RLS the way table data is,
-- and this project's customer kiosk shares the same public anon key as
-- the Staff Hub, so a channel by a guessable name could leak staff
-- emails to anyone holding that key without ever signing in. A plain
-- table with the same is_staff()-gated RLS as everything else avoids
-- that entirely: only an authenticated staff member can read it, and
-- only ever their own row to write it.
create table if not exists public.staff_presence (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  role text,
  "lastSeenAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table public.staff_presence enable row level security;
grant select, insert, update, delete on public.staff_presence to authenticated;

drop policy if exists "staff_presence_select_staff" on public.staff_presence;
create policy "staff_presence_select_staff" on public.staff_presence
  for select to authenticated
  using (public.is_staff());

drop policy if exists "staff_presence_own_insert" on public.staff_presence;
create policy "staff_presence_own_insert" on public.staff_presence
  for insert to authenticated
  with check (id = auth.uid() and public.is_staff());

drop policy if exists "staff_presence_own_update" on public.staff_presence;
create policy "staff_presence_own_update" on public.staff_presence
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "staff_presence_own_delete" on public.staff_presence;
create policy "staff_presence_own_delete" on public.staff_presence
  for delete to authenticated
  using (id = auth.uid());

-- =========================================================================
-- Menu configuration (admin-editable pricing/menu, Staff Hub > Menu Editor)
-- =========================================================================
-- A single JSON row holding everything that would otherwise be hardcoded
-- menu/pricing constants in order/index.html and staff/index.html
-- (TAX_RATE, PIZZA_SIZES, TOPPINGS, SPECIALTY_PIZZAS, CATEGORIES,
-- SPECIALS_BY_DAY). Both files keep their own hardcoded copies of these
-- same values as a fallback -- if this table is missing or a fetch fails,
-- the site behaves exactly as if this table didn't exist, so there's no
-- hard dependency on it.
--
create table if not exists public.menu_config (
  id int primary key default 1,
  data jsonb not null,
  version int not null default 1,
  "updatedAt" timestamptz not null default now(),
  "updatedBy" uuid references auth.users(id),
  constraint menu_config_singleton check (id = 1)
);

alter table public.menu_config enable row level security;

drop policy if exists menu_config_public_read on public.menu_config;
create policy menu_config_public_read on public.menu_config
  for select
  to anon, authenticated
  using (true);

drop policy if exists menu_config_admin_update on public.menu_config;
create policy menu_config_admin_update on public.menu_config
  for update
  to authenticated
  using (exists (
    select 1 from public.staff s where s.id = auth.uid() and s.active and s."isAdmin"
  ))
  with check (exists (
    select 1 from public.staff s where s.id = auth.uid() and s.active and s."isAdmin"
  ));

-- No insert/delete policy for anyone: this is a singleton row seeded
-- once below and only ever updated after that, never replaced or removed.

create or replace function public.bump_menu_config_version()
returns trigger language plpgsql as $fn$
begin
  new.version := old.version + 1;
  new."updatedAt" := now();
  new."updatedBy" := auth.uid();
  return new;
end;
$fn$;

drop trigger if exists menu_config_bump_version on public.menu_config;
create trigger menu_config_bump_version
  before update on public.menu_config
  for each row execute function public.bump_menu_config_version();

--
-- store_settings: a single admin-editable row for store-wide operational
-- controls that used to have no home -- whether the kiosk is currently
-- taking online orders, the message shown when it isn't, a holiday/special
-- hours override banner for the homepage, and a customizable receipt
-- footer message. Public read (the kiosk, and the homepage, both need to
-- read this while signed out), admin-only write, same singleton-row +
-- version-bump-trigger shape as menu_config above.
--
create table if not exists public.store_settings (
  id int primary key default 1,
  "ordersPaused" boolean not null default false,
  "pauseMessage" text not null default 'We''re not accepting online orders right now — please call the shop to place your order.',
  "hoursOverrideActive" boolean not null default false,
  "hoursOverrideNote" text,
  "receiptMessage" text not null default 'Thank you for your order!
Pay in person at pickup or delivery.',
  version int not null default 1,
  "updatedAt" timestamptz not null default now(),
  "updatedBy" uuid references auth.users(id),
  constraint store_settings_singleton check (id = 1)
);

alter table public.store_settings enable row level security;

drop policy if exists store_settings_public_read on public.store_settings;
create policy store_settings_public_read on public.store_settings
  for select
  to anon, authenticated
  using (true);

drop policy if exists store_settings_admin_update on public.store_settings;
create policy store_settings_admin_update on public.store_settings
  for update
  to authenticated
  using (exists (
    select 1 from public.staff s where s.id = auth.uid() and s.active and s."isAdmin"
  ))
  with check (exists (
    select 1 from public.staff s where s.id = auth.uid() and s.active and s."isAdmin"
  ));

-- No insert/delete policy for anyone: singleton row seeded once below.

create or replace function public.bump_store_settings_version()
returns trigger language plpgsql as $fn$
begin
  new.version := old.version + 1;
  new."updatedAt" := now();
  new."updatedBy" := auth.uid();
  return new;
end;
$fn$;

drop trigger if exists store_settings_bump_version on public.store_settings;
create trigger store_settings_bump_version
  before update on public.store_settings
  for each row execute function public.bump_store_settings_version();

insert into public.store_settings (id)
values (1)
on conflict (id) do nothing;

insert into public.menu_config (id, data)
values (1, $json${"TAX_RATE": 0.06625, "PIZZA_SIZES": [{"key": "personal", "label": "Personal Pan (9\")", "base": 8, "perTopping": 1}, {"key": "medium", "label": "Medium (14\")", "base": 14.5, "perTopping": 3}, {"key": "large", "label": "Large (16\")", "base": 15.99, "perTopping": 3.5}, {"key": "sicilian", "label": "Sicilian (16x16\")", "base": 17.99, "perTopping": 4}], "TOPPINGS": ["Pepperoni", "Sausage", "Bacon", "Meatball", "Ham", "Extra Cheese", "Green Pepper", "Onion", "Black Olive", "Mushroom", "Anchovy", "Pineapple", "Spinach", "Broccoli"], "SPECIALTY_PIZZAS": [{"name": "Bacon BBQ Chicken Ranch", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 26}]}, {"name": "Buffalo Chicken", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 26}]}, {"name": "Hawaiian", "sizes": [{"label": "Medium", "price": 20.5}, {"label": "Large", "price": 22.99}, {"label": "Sicilian", "price": 24.99}]}, {"name": "White Pie", "sizes": [{"label": "Medium", "price": 14.5}, {"label": "Large", "price": 15.99}, {"label": "Sicilian", "price": 17.99}]}, {"name": "The Works", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 25.99}, {"label": "Sicilian", "price": 29.99}]}], "CATEGORIES": [{"key": "panzarotti", "label": "Panzarotti", "note": "Deep fried and golden brown", "items": [{"name": "Panzarotti", "price": 8.25, "desc": "Add $0.75 per extra ingredient"}]}, {"key": "stromboli", "label": "Stromboli", "photo": "../images/menu/stromboli.jpg", "placeholder": "../images/menu/stromboli.svg", "items": [{"name": "Cheese Stromboli", "price": 17.99, "desc": "+$2.50 per topping, +$5.00 steak or chicken"}, {"name": "Steak & Onion Stromboli", "price": 24.99}]}, {"key": "calzones", "label": "Calzones", "photo": "../images/menu/calzone.jpg", "placeholder": "../images/menu/calzone.svg", "items": [{"name": "Calzone", "price": 14.99, "desc": "Ham, ricotta, mozzarella and sauce"}]}, {"key": "turnover", "label": "Pizza Turnover", "items": [{"name": "Pizza Turnover", "price": 13.5, "desc": "Mozzarella and pizza sauce, $1 per extra ingredient"}]}, {"key": "wings", "label": "Wings", "note": "All wings come with bread and blue cheese", "photo": "../images/menu/wings.jpg", "placeholder": "../images/menu/wings.svg", "items": [{"name": "Wings", "size": "8 pc", "price": 9.5}, {"name": "Wings", "size": "12 pc", "price": 14.99}, {"name": "Wings", "size": "16 pc", "price": 18.99}, {"name": "Wings", "size": "24 pc", "price": 27.99}]}, {"key": "steaks", "label": "Steaks", "note": "Chicken made with 100% boneless, skinless breast meat", "items": [{"name": "Plain Steak", "price": 11}, {"name": "Cheese Steak", "price": 12}, {"name": "Chicken Cheese Steak", "price": 12}, {"name": "Bacon Cheese Steak", "price": 13}, {"name": "Cheese Steak Sub", "price": 13}, {"name": "Chicken Cheese Steak Sub", "price": 13}, {"name": "Mushroom Cheese Steak", "price": 13}, {"name": "Pepperoni Cheese Steak", "price": 13}, {"name": "Pizza Steak", "price": 13}, {"name": "Buffalo Chicken Cheese Steak", "price": 13}, {"name": "Broccoli Garlic & Oil Chicken Cheese Steak", "price": 13}, {"name": "Cheese Steak Special", "price": 13.75}, {"name": "Cheese Steak Platter", "price": 14.99}]}, {"key": "hoagies", "label": "Hoagies", "note": "All hoagies made with lettuce, tomato, onion and oil", "photo": "../images/menu/hoagie.jpg", "placeholder": "../images/menu/hoagie.svg", "items": [{"name": "Mixed Cheese", "price": 11}, {"name": "American", "price": 11.5}, {"name": "Ham & Cheese", "price": 12}, {"name": "Italian", "price": 12}, {"name": "Turkey & Cheese", "price": 12}, {"name": "Roast Beef, Provolone or American", "price": 13}, {"name": "Fried Fish Hoagie", "price": 13}]}, {"key": "pasta", "label": "Pasta", "note": "Served with soup, salad and garlic bread, spaghetti or ziti", "photo": "../images/menu/pasta.jpg", "placeholder": "../images/menu/pasta.svg", "items": [{"name": "Tomato Sauce", "price": 12.99}, {"name": "Meatballs", "price": 16.99}, {"name": "Sausage", "price": 16.99}]}, {"key": "parm", "label": "Parmigiana Dinners", "note": "Served with salad and garlic bread or a side of spaghetti/ziti", "items": [{"name": "Eggplant Parmigiana", "price": 15.99}, {"name": "Chicken Cutlet Parmigiana", "price": 16.99}]}, {"key": "hotsand", "label": "Hot Sandwiches", "items": [{"name": "Homemade Meatball Sandwich", "price": 11.5}, {"name": "Eggplant Parmigiana", "price": 11}, {"name": "Homemade Meatball Parmigiana", "price": 12.5}, {"name": "Chicken Parmigiana", "price": 12.5}, {"name": "Sausage Parmigiana", "price": 12.5}, {"name": "Hot Roast Beef", "price": 12}, {"name": "Hot Roast Beef with Cheese", "price": 13}, {"name": "Sausage Supreme", "price": 12.99}]}, {"key": "italian", "label": "Italian Specialties", "note": "Served with soup, salad and garlic bread", "items": [{"name": "Baked Ziti", "price": 16.99}, {"name": "Cheese Ravioli", "price": 16.99}, {"name": "Stuffed Shells Parmigiana", "price": 16.99}]}, {"key": "platters", "label": "Platters", "items": [{"name": "BLT Club", "price": 12.99}, {"name": "Chicken Finger Platter", "price": 13.99}, {"name": "Ham & Cheese Club", "price": 13.99}, {"name": "Chicken Club", "price": 14.99}, {"name": "Roast Beef Club", "price": 14.99}, {"name": "Turkey Club", "price": 14.99}, {"name": "Shrimp Platter", "price": 14.99}]}, {"key": "burgers", "label": "Quarter Pound Burgers", "photo": "../images/menu/burger.jpg", "placeholder": "../images/menu/burger.svg", "items": [{"name": "Hamburger", "price": 7}, {"name": "Cheeseburger", "price": 8}, {"name": "Bacon Cheeseburger", "price": 9}, {"name": "Pizza Burger", "price": 9}, {"name": "Cheese Burger Sub", "price": 13}]}, {"key": "sides", "label": "Side Orders", "items": [{"name": "French Fries", "price": 5.75}, {"name": "Onion Rings", "price": 8}, {"name": "Poppers", "size": "Cheddar", "price": 8}, {"name": "Breaded Mushrooms", "price": 8.5}, {"name": "Broccoli Bites", "price": 8.5}, {"name": "Meatballs", "price": 8.5}, {"name": "Mozzarella Sticks", "price": 8.5}, {"name": "Pizza Fries", "size": "Small", "price": 8.5}, {"name": "Pizza Fries", "size": "Large", "price": 10.5}, {"name": "Sausage", "price": 8.5}, {"name": "Fried Tomato", "price": 9}, {"name": "Cheese Fries", "size": "Small", "price": 6.5}, {"name": "Cheese Fries", "size": "Large", "price": 9}, {"name": "Loaded Fries", "size": "Small", "price": 9.5}, {"name": "Loaded Fries", "size": "Large", "price": 10.5}, {"name": "Homemade Cole Slaw", "size": "Pint", "price": 3.5}, {"name": "Homemade Cole Slaw", "size": "Quart", "price": 7}, {"name": "Something Sweet Zeppoli", "size": "Small", "price": 4}, {"name": "Something Sweet Zeppoli", "size": "Large", "price": 8}]}, {"key": "soups", "label": "Soups", "items": [{"name": "Pasta Faggioli", "size": "Small", "price": 4.99}, {"name": "Pasta Faggioli", "size": "Quart", "price": 8.99}, {"name": "Chili", "size": "Small, winter", "price": 6.5}, {"name": "Chili", "size": "Quart, winter", "price": 11.99}]}, {"key": "salads", "label": "Salads", "photo": "../images/menu/salad.jpg", "placeholder": "../images/menu/salad.svg", "items": [{"name": "Tossed Salad", "price": 7.99}, {"name": "Antipasta", "price": 12.99}, {"name": "Chef Salad", "price": 12.99}, {"name": "Chicken Caesar Salad", "price": 12.99}, {"name": "Grilled Chicken Salad", "price": 12.99}]}, {"key": "breakfast", "label": "Breakfast", "items": [{"name": "Grilled Cheese", "price": 7, "desc": "+$1 to add ham or bacon"}, {"name": "Bacon, Lettuce & Tomato", "price": 8}, {"name": "Pepper and Egg", "price": 10}, {"name": "Bacon, Egg and Cheese", "price": 11}, {"name": "Sausage, Egg and Cheese", "price": 11}, {"name": "Pork Roll, Egg and Cheese", "price": 11}]}, {"key": "knots", "label": "Garlic Knots", "items": [{"name": "Garlic Knots", "size": "6 pc", "price": 4.75}]}, {"key": "drinks", "label": "Drinks", "note": "We carry Pepsi products -- names/prices are a starting point, adjust in Staff Hub > Menu Editor to match what you actually stock", "items": [{"name": "Pepsi", "size": "20 oz", "price": 2.75}, {"name": "Diet Pepsi", "size": "20 oz", "price": 2.75}, {"name": "Pepsi Zero Sugar", "size": "20 oz", "price": 2.75}, {"name": "Mountain Dew", "size": "20 oz", "price": 2.75}, {"name": "Starry", "size": "20 oz", "price": 2.75}, {"name": "Mug Root Beer", "size": "20 oz", "price": 2.75}, {"name": "Brisk Iced Tea", "size": "20 oz", "price": 2.75}, {"name": "Aquafina Water", "size": "20 oz", "price": 2.0}, {"name": "Pepsi", "size": "2 Liter", "price": 4.5}, {"name": "Diet Pepsi", "size": "2 Liter", "price": 4.5}, {"name": "Mountain Dew", "size": "2 Liter", "price": 4.5}, {"name": "Starry", "size": "2 Liter", "price": 4.5}]}], "SPECIALS_BY_DAY": {"0": {"name": "4 Original Panzarotti", "price": 25.99}, "1": {"name": "2 Cheese Steaks", "price": 20.99}, "2": {"name": "Large Pizza", "price": 13.99}, "3": {"name": "Sicilian Pie", "price": 15.99}, "4": {"name": "2 Chicken Finger Platters", "price": 22.99}, "5": {"name": "Stromboli + 2 Liter Soda", "price": 18.5}, "6": {"name": "Cheese Steak Platter", "price": 13.99}}}$json$::jsonb)
on conflict (id) do nothing;
