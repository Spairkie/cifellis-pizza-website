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
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table public.staff enable row level security;
grant select on public.staff to authenticated;
drop policy if exists "staff_select_staff" on public.staff;
create policy "staff_select_staff" on public.staff
  for select to authenticated
  using (exists (select 1 from public.staff s where s.id = auth.uid()));
-- No insert/update/delete policy on purpose: add or remove staff from
-- the Supabase dashboard's Table Editor (or SQL Editor), not the app.
-- That keeps "who can see every customer's data" a deliberate action
-- you take once per person, not something any code path can do.

create or replace function public.is_staff()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.staff where id = auth.uid());
$$;

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

-- Drivers. A driver profile is created by staff (Staff Hub > Driver
-- Roster); the driver signs in with their own Supabase Auth account
-- (created the same way staff accounts are, via the dashboard) and is
-- matched to their profile by email. Being in this table does NOT by
-- itself make someone staff — add them to the staff table too (with
-- "isDriver" true) so they can sign in and reach the Driver App.
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
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "updatedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create unique index if not exists drivers_email_idx on public.drivers (lower(email)) where email <> '';
alter table public.drivers enable row level security;
grant select, insert, update on public.drivers to authenticated;
drop policy if exists "drivers_staff_all" on public.drivers;
create policy "drivers_staff_all" on public.drivers
  for all to authenticated
  using (public.is_staff())
  with check (public.is_staff());

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
