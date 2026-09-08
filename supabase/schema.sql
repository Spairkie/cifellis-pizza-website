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
alter table public.orders add column if not exists "promoCode" text;
alter table public.orders add column if not exists "discountAmount" numeric(10,2) not null default 0;

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

-- Anti-abuse: block a burst of orders from the same phone number in a
-- short window. Deliberately server-side (a trigger, not a client-side
-- check) since a client-side-only guard is trivially bypassed by anyone
-- calling the REST API directly -- the same reasoning as every other
-- real trust boundary in this file. Only applies to source='customer'
-- (the public kiosk); staff ringing up real phone/walk-in orders at POS
-- are never throttled, including several for the same regular's number
-- in one shift. Paired with a honeypot field and a minimum-time-on-page
-- check in order/index.html's checkout flow -- neither of those is a
-- real security boundary on its own (both are trivial for a script that
-- specifically targets this form to work around), but together they
-- stop the common case: an unsophisticated bot or script hammering the
-- public endpoint, not a targeted attacker. A real CAPTCHA (hCaptcha or
-- Cloudflare Turnstile, both free) would be the next step up if actual
-- abuse shows up -- both need a new account, so deferred for now, same
-- as the payment/SMS scaffolds elsewhere in this project.
create or replace function public.enforce_order_rate_limit()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  recent_count int;
begin
  -- security definer is not optional here, unlike it might look at a
  -- glance: this function is invoked as a BEFORE INSERT trigger on an
  -- anon-role insert (the public kiosk has no SELECT policy on orders at
  -- all -- see orders_select_staff_or_own below, "to authenticated" only).
  -- Without security definer, the SELECT COUNT(*) a few lines down runs
  -- as SECURITY INVOKER -- i.e. as anon -- and RLS silently filters it to
  -- zero rows every time, regardless of how many matching orders actually
  -- exist. That makes `recent_count >= 5` never true, which means this
  -- rate limit was completely inert for every real (unauthenticated)
  -- customer order, not enforcing anything, until this was caught and
  -- fixed. Same is_staff()/rate_delivery()-style reasoning as elsewhere
  -- in this file: security definer runs with the function owner's
  -- privileges, bypassing RLS for this function's own internal lookup,
  -- so it can actually see the rows it needs to count.
  --
  -- Deliberately no `and new.phone <> ''` exemption either: the client-
  -- side form always sends a phone number (submitCustomerOrder requires
  -- one before it will submit), but nothing stops a request sent straight
  -- to the REST endpoint from omitting it -- an empty phone used to skip
  -- this whole check, which was a second, independent unlimited-rate hole
  -- on top of the first. Grouping by the literal phone value (including
  -- '') rate-limits that case the same as any other.
  if new.source = 'customer' then
    select count(*) into recent_count
    from public.orders
    where phone = new.phone
      and source = 'customer'
      and "createdAt" >= (extract(epoch from now()) * 1000)::bigint - 15 * 60 * 1000;
    if recent_count >= 5 then
      raise exception 'Too many orders placed from this phone number recently. Please call the shop directly at (856) 435-8799.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_rate_limit_trigger on public.orders;
create trigger orders_rate_limit_trigger
  before insert on public.orders
  for each row execute function public.enforce_order_rate_limit();

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
-- Promo codes (Staff Hub > Promo Codes, admin-only; redeemed at checkout)
-- =========================================================================
-- Policy decision (owner's call, 2026-09-07): one redemption per phone
-- number per code -- not per order, so a customer can't reuse the same
-- code on a second order, but a different code is fine. Enforced with a
-- real unique constraint in promo_redemptions below, not just a UI
-- check, the same way every other trust boundary in this file is.
create table if not exists public.promo_codes (
  -- code is the real business key (what redeem_promo_code() looks up,
  -- what promo_redemptions references), but the Staff Hub's Firestore-
  -- shaped db adapter always calls .doc(id).update()/.get() against a
  -- column literally named "id" -- this surrogate key exists purely so
  -- Promo Codes management can use that same adapter pattern every
  -- other admin screen in this file already uses, not because the data
  -- model needs two keys.
  code text primary key,
  label text not null default '',
  "discountType" text not null check ("discountType" in ('percent','fixed')),
  amount numeric(10,2) not null check (amount > 0),
  active boolean not null default true,
  "expiresAt" bigint,
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "createdBy" uuid references auth.users(id)
);
-- Migration: the id column above didn't exist when this table was first
-- created in an earlier run of this file -- add it (and its uniqueness)
-- the same way the orders table's migration block above adds columns.
alter table public.promo_codes add column if not exists id uuid not null default gen_random_uuid();
create unique index if not exists promo_codes_id_idx on public.promo_codes (id);

-- Codes are managed only through the admin-only Promo Codes screen and
-- validated only through redeem_promo_code() below (security definer,
-- so it can read promo_codes even though no SELECT policy grants that
-- to anon/authenticated directly) -- deliberately no public read policy,
-- so codes aren't a browsable list to anyone holding the anon key.
alter table public.promo_codes enable row level security;
grant select, insert, update on public.promo_codes to authenticated;
drop policy if exists "promo_codes_admin_all" on public.promo_codes;
create policy "promo_codes_admin_all" on public.promo_codes
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- No orderId column linking a redemption to the specific order it was
-- used on: redeem_promo_code() runs before the order exists (at
-- "Apply Code" time in checkout, so the discount can show before final
-- submit), and there's no second call afterward to attach the resulting
-- order id -- adding an always-null column for that would be exactly
-- the kind of half-finished field this project avoids. The (code,
-- phone) pair below is already enough for what this needs to enforce
-- and audit; wire up that link later if it's ever actually wanted.
create table if not exists public.promo_redemptions (
  id uuid primary key default gen_random_uuid(),
  code text not null references public.promo_codes(code),
  phone text not null,
  "redeemedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  unique (code, phone)
);

-- No policies grant anon/authenticated direct access at all -- every
-- write goes through redeem_promo_code() (security definer, below),
-- and only an admin can browse redemptions directly for auditing.
alter table public.promo_redemptions enable row level security;
grant select on public.promo_redemptions to authenticated;
drop policy if exists "promo_redemptions_admin_select" on public.promo_redemptions;
create policy "promo_redemptions_admin_select" on public.promo_redemptions
  for select to authenticated
  using (public.is_admin());

-- Validates and atomically redeems a code for a phone number, called at
-- checkout before the order is placed (order/index.html). Raises a
-- specific exception per failure reason (surfaced to the customer as
-- e.message by the Supabase JS client) rather than returning a bare
-- boolean like rate_delivery() above -- promo UX benefits from knowing
-- *why* a code didn't work, unlike a delivery rating.
create or replace function public.redeem_promo_code(p_code text, p_phone text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(p_code));
  v_phone text := trim(p_phone);
  v_row public.promo_codes%rowtype;
begin
  if v_code = '' then
    raise exception 'Enter a promo code';
  end if;
  if v_phone = '' then
    raise exception 'A phone number is required to apply a promo code';
  end if;

  select * into v_row from public.promo_codes where code = v_code;
  if not found then
    raise exception 'That promo code doesn''t exist';
  end if;
  if not v_row.active then
    raise exception 'That promo code is no longer active';
  end if;
  if v_row."expiresAt" is not null and v_row."expiresAt" < (extract(epoch from now()) * 1000)::bigint then
    raise exception 'That promo code has expired';
  end if;

  begin
    insert into public.promo_redemptions (code, phone) values (v_code, v_phone);
  exception when unique_violation then
    raise exception 'This phone number has already used that code';
  end;

  return jsonb_build_object('code', v_code, 'discountType', v_row."discountType", 'amount', v_row.amount, 'label', v_row.label);
end;
$$;
grant execute on function public.redeem_promo_code(text, text) to anon, authenticated;

-- =========================================================================
-- Bug reports (Staff Hub > "Report a Bug", admin-only Bug Reports screen)
-- =========================================================================
-- Lets any signed-in staff member flag something broken from inside the
-- app, mid-shift, instead of it only being caught whenever someone
-- happens to review the codebase directly. Any staff member can submit
-- one; only an admin can see the list and mark them resolved -- staff
-- don't need the list, just the ability to add to it.
create table if not exists public.bug_reports (
  id uuid primary key default gen_random_uuid(),
  "reportedBy" uuid not null references auth.users(id),
  "reportedByEmail" text not null default '',
  role text,
  message text not null,
  status text not null default 'open' check (status in ('open','resolved')),
  "resolvedBy" uuid references auth.users(id),
  "resolvedByEmail" text,
  "resolvedAt" bigint,
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists bug_reports_status_idx on public.bug_reports (status);

alter table public.bug_reports enable row level security;
grant select, insert, update on public.bug_reports to authenticated;

drop policy if exists "bug_reports_staff_insert" on public.bug_reports;
create policy "bug_reports_staff_insert" on public.bug_reports
  for insert to authenticated
  with check ("reportedBy" = auth.uid() and public.is_staff());

drop policy if exists "bug_reports_admin_select" on public.bug_reports;
create policy "bug_reports_admin_select" on public.bug_reports
  for select to authenticated
  using (public.is_admin());

drop policy if exists "bug_reports_admin_update" on public.bug_reports;
create policy "bug_reports_admin_update" on public.bug_reports
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());
-- No delete policy -- same reasoning as orders/register_shifts: keep the
-- full history, remove by hand in the dashboard if it's ever needed.

-- Realtime: the admin-only Bug Reports screen live-subscribes (new
-- reports and resolutions from any tab show up immediately), so this
-- table needs to be in the realtime publication the same way orders/
-- drivers/driver_shifts are above -- easy to miss since most of the
-- other newer tables in this file (store_settings, register_shifts,
-- staff_presence) deliberately use one-shot fetches instead and don't
-- need this.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bug_reports'
  ) then
    alter publication supabase_realtime add table public.bug_reports;
  end if;
end $$;

-- =========================================================================
-- Live driver locations (Staff Hub > Driver Map)
-- =========================================================================
-- One row per driver, upserted from the Driver App only while that
-- driver has an active delivery out (not the whole time the app happens
-- to be open) -- the real battery/privacy/data cost this was flagged
-- with in ROADMAP.md is why tracking is scoped that tightly rather than
-- running continuously. Own row only (id = auth.uid(), same ownership
-- pattern as staff_presence above); any staff can read the whole table
-- to render the map. The row is deleted once a driver has no more
-- active deliveries or clocks out, so a stale row only ever means
-- "their last delivery run, now finished" rather than looking live
-- forever -- the client additionally treats anything not updated in the
-- last couple of minutes as "may be offline" rather than trusting it.
create table if not exists public.driver_locations (
  id uuid primary key references auth.users(id) on delete cascade,
  lat numeric(9,6) not null,
  lng numeric(9,6) not null,
  heading numeric(6,2),
  "updatedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);

alter table public.driver_locations enable row level security;
grant select, insert, update, delete on public.driver_locations to authenticated;

drop policy if exists "driver_locations_staff_select" on public.driver_locations;
create policy "driver_locations_staff_select" on public.driver_locations
  for select to authenticated
  using (public.is_staff());

drop policy if exists "driver_locations_own_insert" on public.driver_locations;
create policy "driver_locations_own_insert" on public.driver_locations
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists "driver_locations_own_update" on public.driver_locations;
create policy "driver_locations_own_update" on public.driver_locations
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "driver_locations_own_delete" on public.driver_locations;
create policy "driver_locations_own_delete" on public.driver_locations
  for delete to authenticated
  using (id = auth.uid());

-- Realtime: the Driver Map screen live-subscribes so a driver's dot
-- moves without a manual refresh.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'driver_locations'
  ) then
    alter publication supabase_realtime add table public.driver_locations;
  end if;
end $$;

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

-- =========================================================================
-- Server-authoritative checkout, 2026-09-08 (review-finding fixes)
-- =========================================================================
-- Everything below closes the gap where a customer order's dollar
-- amounts (and, before this, its ownership boundary, its ticket number,
-- and its promo-code redemption) were entirely client-trusted. See the
-- dated ROADMAP.md entry for the full writeup; this comment covers only
-- what each piece does and why.

-- Canonical phone form used everywhere a phone number is compared:
-- digits only, and the US country-code "1" stripped off an 11-digit
-- number so "(856) 555-0100", "18565550100" and "856-555-0100" are all
-- the same key for rate limiting, promo one-per-phone enforcement, and
-- CRM/regulars matching. Immutable (pure function of its input) so it's
-- safe to use directly in comparisons without an expression index.
create or replace function public.normalize_phone(p text)
returns text language sql immutable as $$
  select case
    when length(regexp_replace(coalesce(p, ''), '\D', '', 'g')) = 11
      and left(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 1) = '1'
    then right(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 10)
    else regexp_replace(coalesce(p, ''), '\D', '', 'g')
  end;
$$;

-- Backfill existing stored phone numbers to their normalized form. Safe
-- to re-run (idempotent -- normalizing an already-normalized number is a
-- no-op). Wrapped per-table so one table's constraint conflict (e.g. two
-- differently-formatted numbers for the same person colliding once
-- normalized) can't abort the others.
do $$ begin
  update public.orders set phone = public.normalize_phone(phone) where phone <> public.normalize_phone(phone);
exception when others then null;
end $$;
do $$ begin
  update public.customers set phone = public.normalize_phone(phone) where phone <> public.normalize_phone(phone);
exception when others then null;
end $$;
do $$ begin
  update public.promo_redemptions set phone = public.normalize_phone(phone) where phone <> public.normalize_phone(phone);
exception when others then null;
end $$;

-- Rate limiting now normalizes both sides of the comparison, so
-- "8565550100" and "(856) 555-0100" placed back to back count against
-- the same limit instead of looking like two different phone numbers.
create or replace function public.enforce_order_rate_limit()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  recent_count int;
begin
  if new.source = 'customer' then
    select count(*) into recent_count
    from public.orders
    where public.normalize_phone(phone) = public.normalize_phone(new.phone)
      and source = 'customer'
      and "createdAt" >= (extract(epoch from now()) * 1000)::bigint - 15 * 60 * 1000;
    if recent_count >= 5 then
      raise exception 'Too many orders placed from this phone number recently. Please call the shop directly at (856) 435-8799.';
    end if;
  end if;
  return new;
end;
$$;

-- Real account ownership for signed-in customers, instead of an
-- unverified phone number. A customer's `customers.phone` field is
-- self-entered at signup -- anyone can type any phone number there, so
-- using "phone matches" as the boundary for "which orders can this
-- account read" let one customer read another's full order history
-- (address, items, notes) just by knowing or guessing their phone
-- number. New orders placed while signed in now record customerId
-- directly (set server-side from auth.uid() in create_order() below,
-- never client-supplied); a signed-in customer can only ever read
-- orders that carry their own id here. Pre-existing anonymous orders
-- (customerId null, phone only) are no longer claimable by anyone
-- through this policy -- correct, since phone-matching was never a real
-- ownership proof to begin with.
alter table public.orders add column if not exists "customerId" uuid references auth.users(id);
create index if not exists orders_customerid_idx on public.orders ("customerId");

-- Every dollar amount on a customer order (subtotal/tax/tip/total/
-- discount, and every line's unitPrice) is now computed here, from
-- menu_config, never trusted from the client. A cart line only ever
-- carries a *reference* to what it claims to be (ref.kind + enough to
-- look it up: category+name for a catalog item, pizza+size for a
-- specialty, size+toppings for a build-your-own, nothing extra for
-- today's special since that's resolved fresh server-side regardless of
-- what day the client thinks it is) -- this function resolves that
-- reference against the live menu and prices the line itself. Anything
-- that doesn't resolve (removed item, sold-out item, changed toppings
-- list, malformed/missing ref) fails the whole order with a clear
-- message rather than silently accepting a guessed price. Promo
-- redemption is consumed atomically in here too (see
-- _consume_promo_code below) -- if anything else in this function
-- raises, the whole transaction (including that insert) rolls back, so
-- a promo code is never burned by an order that didn't actually go
-- through.
create or replace function public.create_order(p_order jsonb)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_menu jsonb;
  v_paused boolean;
  v_pause_message text;
  v_categories jsonb;
  v_specialty jsonb;
  v_sizes jsonb;
  v_toppings jsonb;
  v_specials jsonb;
  v_tax_rate numeric;
  v_name text;
  v_phone text;
  v_address text;
  v_notes text;
  v_order_type text;
  v_pay_method text;
  v_phone_opt_in boolean;
  v_tip numeric;
  v_promo_code text;
  v_delivery_miles numeric;
  v_delivery_eta_mins integer;
  v_item jsonb;
  v_ref jsonb;
  v_kind text;
  v_unit_price numeric;
  v_qty int;
  v_line_name text;
  v_line_size text;
  v_line_notes text;
  v_items jsonb := '[]'::jsonb;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_discount_label text := '';
  v_promo_row public.promo_codes%rowtype;
  v_tax numeric;
  v_total numeric;
  v_ticket text;
  v_today_dow int;
  v_today_special jsonb;
  v_order_id uuid;
  v_customer_id uuid := auth.uid();
  v_idempotency_key text;
  v_existing record;
  v_scheduled_for bigint;
  v_scheduled_date date;
  v_scheduled_time time;
  v_hours record;
  v_now_ms bigint := (extract(epoch from now()) * 1000)::bigint;
begin
  -- Idempotency: if this exact request already went through (same key),
  -- return that result instead of creating a second order. Checked
  -- first, before anything else -- a retried request for an order that
  -- already succeeded should succeed again with the same result, even
  -- if the store got paused or the menu changed in between.
  v_idempotency_key := nullif(trim(p_order->>'idempotencyKey'), '');
  if v_idempotency_key is not null then
    select id, ticket, subtotal, tax, tip, total, "discountAmount", "promoCode", items, "createdAt"
      into v_existing
      from public.orders where "idempotencyKey" = v_idempotency_key;
    if found then
      return jsonb_build_object(
        'ticket', v_existing.ticket, 'orderId', v_existing.id, 'subtotal', v_existing.subtotal,
        'tax', v_existing.tax, 'tip', v_existing.tip, 'total', v_existing.total,
        'discountAmount', v_existing."discountAmount", 'discountLabel', coalesce(v_existing."promoCode", ''),
        'promoCode', v_existing."promoCode", 'items', v_existing.items, 'createdAt', v_existing."createdAt",
        'idempotentReplay', true
      );
    end if;
  end if;

  select "ordersPaused", "pauseMessage" into v_paused, v_pause_message from public.store_settings where id = 1;
  if coalesce(v_paused, false) then
    raise exception '%', coalesce(v_pause_message, 'Online ordering is currently paused. Please call the shop to place your order.');
  end if;

  -- Scheduled orders: null scheduledFor is today's ASAP behavior,
  -- completely unchanged. A future time must clear a minimum lead time,
  -- fall within a real advance-booking window, and land inside actual
  -- business hours for that date (hours_for_date() -- regular weekly
  -- hours unless a dated override applies).
  v_scheduled_for := nullif(p_order->>'scheduledFor', '')::bigint;
  if v_scheduled_for is not null then
    if v_scheduled_for < v_now_ms + 30*60*1000 then
      raise exception 'Scheduled orders need at least 30 minutes'' notice.';
    end if;
    if v_scheduled_for > v_now_ms + 14*86400000 then
      raise exception 'Scheduled orders can only be placed up to 14 days in advance.';
    end if;
    v_scheduled_date := (to_timestamp(v_scheduled_for / 1000.0) at time zone 'America/New_York')::date;
    v_scheduled_time := (to_timestamp(v_scheduled_for / 1000.0) at time zone 'America/New_York')::time;
    select * into v_hours from public.hours_for_date(v_scheduled_date);
    if coalesce(v_hours.closed, false) then
      raise exception 'The shop is closed on that date -- please pick a different time.';
    end if;
    if v_hours."openTime" is not null and v_hours."closeTime" is not null
       and (v_scheduled_time < v_hours."openTime" or v_scheduled_time > v_hours."closeTime") then
      raise exception 'That time is outside business hours for that date (% - %).',
        to_char(v_hours."openTime", 'HH12:MI AM'), to_char(v_hours."closeTime", 'HH12:MI AM');
    end if;
  end if;

  select data into v_menu from public.menu_config where id = 1;
  if v_menu is null then
    raise exception 'The menu is not available right now. Please call the shop to place your order.';
  end if;
  v_categories := v_menu->'CATEGORIES';
  v_specialty := v_menu->'SPECIALTY_PIZZAS';
  v_sizes := v_menu->'PIZZA_SIZES';
  v_toppings := v_menu->'TOPPINGS';
  v_specials := v_menu->'SPECIALS_BY_DAY';
  v_tax_rate := coalesce((v_menu->>'TAX_RATE')::numeric, 0.06625);

  v_name := left(trim(coalesce(p_order->>'customerName', '')), 200);
  v_phone := public.normalize_phone(coalesce(p_order->>'phone', ''));
  v_address := left(trim(coalesce(p_order->>'address', '')), 500);
  v_notes := left(trim(coalesce(p_order->>'notes', '')), 500);
  v_order_type := coalesce(p_order->>'orderType', 'pickup');
  v_pay_method := coalesce(p_order->>'payMethod', 'cash');
  v_phone_opt_in := coalesce((p_order->>'phoneOptIn')::boolean, false);
  v_tip := greatest(coalesce((p_order->>'tip')::numeric, 0), 0);
  v_promo_code := nullif(upper(trim(coalesce(p_order->>'promoCode', ''))), '');
  v_delivery_miles := nullif(p_order->>'deliveryMiles','')::numeric;
  v_delivery_eta_mins := nullif(p_order->>'deliveryEtaMins','')::integer;

  if v_name = '' or v_phone = '' then
    raise exception 'Name and phone number are required.';
  end if;
  if v_order_type not in ('pickup','delivery') then
    raise exception 'Invalid order type.';
  end if;
  if v_order_type = 'delivery' and v_address = '' then
    raise exception 'A delivery address is required.';
  end if;
  if v_pay_method not in ('cash','card') then
    raise exception 'Invalid payment method.';
  end if;
  if jsonb_typeof(p_order->'items') <> 'array' or jsonb_array_length(p_order->'items') = 0 then
    raise exception 'Your order is empty.';
  end if;
  if jsonb_array_length(p_order->'items') > 100 then
    raise exception 'That''s too many items for one order -- please call the shop directly.';
  end if;

  for v_item in select * from jsonb_array_elements(p_order->'items') loop
    v_ref := v_item->'ref';
    v_kind := v_ref->>'kind';
    v_qty := greatest(1, least(50, coalesce((v_item->>'qty')::int, 1)));
    v_unit_price := null;
    v_line_notes := '';

    if v_kind = 'catalog' then
      declare
        v_cat jsonb;
        v_it jsonb;
      begin
        select c into v_cat from jsonb_array_elements(v_categories) c where c->>'key' = v_ref->>'categoryKey' limit 1;
        if v_cat is null then raise exception 'One of the items in your order is no longer on the menu -- please refresh and try again.'; end if;
        select it into v_it from jsonb_array_elements(v_cat->'items') it where it->>'name' = v_ref->>'itemName' limit 1;
        if v_it is null then raise exception 'One of the items in your order is no longer on the menu -- please refresh and try again.'; end if;
        if coalesce((v_it->>'soldOut')::boolean, false) then
          raise exception '% is sold out right now -- please remove it from your cart.', v_it->>'name';
        end if;
        v_unit_price := (v_it->>'price')::numeric;
        v_line_name := v_it->>'name';
        v_line_size := coalesce(v_it->>'size', '');
      end;
    elsif v_kind = 'specialty' then
      declare
        v_p jsonb;
        v_s jsonb;
      begin
        select p into v_p from jsonb_array_elements(v_specialty) p where p->>'name' = v_ref->>'pizzaName' limit 1;
        if v_p is null then raise exception 'One of the specialty pizzas in your order is no longer available -- please refresh and try again.'; end if;
        select s into v_s from jsonb_array_elements(v_p->'sizes') s where s->>'label' = v_ref->>'sizeLabel' limit 1;
        if v_s is null then raise exception 'One of the specialty pizzas in your order is no longer available in that size -- please refresh and try again.'; end if;
        v_unit_price := (v_s->>'price')::numeric;
        v_line_name := v_p->>'name';
        v_line_size := v_s->>'label';
      end;
    elsif v_kind = 'custom' then
      declare
        v_size jsonb;
        v_topping text;
        v_count int := 0;
        v_valid_toppings text[];
      begin
        select sz into v_size from jsonb_array_elements(v_sizes) sz where sz->>'key' = v_ref->>'sizeKey' limit 1;
        if v_size is null then raise exception 'That pizza size is no longer available -- please refresh and try again.'; end if;
        select array_agg(t) into v_valid_toppings from jsonb_array_elements_text(v_toppings) t;
        for v_topping in select jsonb_array_elements_text(coalesce(v_ref->'toppings','[]'::jsonb)) loop
          if v_valid_toppings is null or not (v_topping = any(v_valid_toppings)) then
            raise exception 'One of the toppings on your pizza is no longer available -- please rebuild it and try again.';
          end if;
          v_count := v_count + 1;
        end loop;
        if v_count > 20 then raise exception 'Too many toppings on one pizza.'; end if;
        v_unit_price := (v_size->>'base')::numeric + (v_size->>'perTopping')::numeric * v_count;
        v_line_name := regexp_replace(v_size->>'label', '\s*\(.+\)$', '') || ' Pizza';
        v_line_size := v_size->>'label';
        select string_agg(t, ', ') into v_line_notes from jsonb_array_elements_text(coalesce(v_ref->'toppings','[]'::jsonb)) t;
        v_line_notes := coalesce(v_line_notes, '');
      end;
    elsif v_kind = 'special' then
      v_today_dow := extract(dow from (now() at time zone 'America/New_York'))::int;
      v_today_special := v_specials->(v_today_dow::text);
      if v_today_special is null then raise exception 'Today''s special is not available right now -- please remove it from your cart.'; end if;
      v_unit_price := (v_today_special->>'price')::numeric;
      v_line_name := v_today_special->>'name';
      v_line_size := '';
      v_line_notes := 'Daily special';
    else
      raise exception 'One of the items in your order could not be verified -- please refresh the page and try again.';
    end if;

    v_subtotal := v_subtotal + v_unit_price * v_qty;
    v_items := v_items || jsonb_build_object(
      'name', v_line_name, 'size', v_line_size, 'unitPrice', v_unit_price,
      'qty', v_qty, 'notes', coalesce(nullif(v_line_notes,''), v_item->>'notes'),
      -- Stored (not just validated against) so a later "Reorder these
      -- items" can re-resolve current pricing/availability the same way
      -- this order itself was priced, instead of trusting a stale
      -- unitPrice from whenever this order was placed -- see the
      -- reorder handler in order/index.html.
      'ref', v_ref
    );
  end loop;

  if v_promo_code is not null then
    select * into v_promo_row from public.promo_codes where code = v_promo_code;
    if v_promo_row is null then
      raise exception 'That promo code doesn''t exist.';
    end if;
    if not v_promo_row.active then
      raise exception 'That promo code is no longer active.';
    end if;
    if v_promo_row."expiresAt" is not null and v_promo_row."expiresAt" < (extract(epoch from now())*1000)::bigint then
      raise exception 'That promo code has expired.';
    end if;
    perform public._consume_promo_code(v_promo_code, v_phone);
    if v_promo_row."discountType" = 'percent' then
      v_discount := v_subtotal * (v_promo_row.amount / 100);
    else
      v_discount := v_promo_row.amount;
    end if;
    v_discount := least(v_discount, v_subtotal);
    v_discount_label := coalesce(nullif(v_promo_row.label, ''), v_promo_code);
  end if;

  v_tax := round((v_subtotal - v_discount) * v_tax_rate, 2);
  v_total := round((v_subtotal - v_discount) + v_tax + v_tip, 2);
  v_ticket := 'T' || lpad(nextval('public.orders_ticket_seq')::text, 6, '0');

  begin
    insert into public.orders (
      ticket, source, "customerName", phone, address, notes, "orderType", "payMethod",
      items, subtotal, tax, tip, total, "phoneOptIn", "deliveryMiles", "deliveryEtaMins",
      "promoCode", "discountAmount", "customerId", "idempotencyKey", "scheduledFor"
    ) values (
      v_ticket, 'customer', v_name, v_phone,
      case when v_order_type = 'delivery' then v_address else '' end,
      v_notes, v_order_type, v_pay_method, v_items, v_subtotal, v_tax, v_tip, v_total,
      v_phone_opt_in, v_delivery_miles, v_delivery_eta_mins, v_promo_code, v_discount, v_customer_id,
      v_idempotency_key, v_scheduled_for
    ) returning id into v_order_id;
  exception when unique_violation then
    -- Lost a race against another request with the same idempotency
    -- key (two near-simultaneous submits of the same click). Whichever
    -- one actually landed is the real order -- return its result rather
    -- than erroring, which is the whole point of idempotency: the
    -- caller gets a successful, consistent result either way.
    if v_idempotency_key is not null then
      select id, ticket, subtotal, tax, tip, total, "discountAmount", "promoCode", items, "createdAt"
        into v_existing from public.orders where "idempotencyKey" = v_idempotency_key;
      if found then
        return jsonb_build_object(
          'ticket', v_existing.ticket, 'orderId', v_existing.id, 'subtotal', v_existing.subtotal,
          'tax', v_existing.tax, 'tip', v_existing.tip, 'total', v_existing.total,
          'discountAmount', v_existing."discountAmount", 'discountLabel', coalesce(v_existing."promoCode", ''),
          'promoCode', v_existing."promoCode", 'items', v_existing.items, 'createdAt', v_existing."createdAt",
          'idempotentReplay', true
        );
      end if;
    end if;
    raise; -- a ticket collision, not an idempotency-key collision -- a real error, surface it
  end;

  return jsonb_build_object(
    'ticket', v_ticket, 'orderId', v_order_id, 'subtotal', v_subtotal, 'tax', v_tax,
    'tip', v_tip, 'total', v_total, 'discountAmount', v_discount, 'discountLabel', v_discount_label,
    'promoCode', v_promo_code, 'items', v_items, 'scheduledFor', v_scheduled_for,
    'createdAt', (extract(epoch from now())*1000)::bigint
  );
end;
$$;
grant execute on function public.create_order(jsonb) to anon, authenticated;

-- Real, database-enforced ticket uniqueness (there was none before --
-- the client picked the last 6 digits of Date.now(), which repeats
-- every ~16.7 minutes and had no constraint stopping a collision from
-- silently producing two orders with the same ticket). create_order()
-- above generates every customer-facing ticket from this sequence; POS
-- (staff, already trusted for direct order inserts -- see
-- orders_insert_staff_only below) still suggests one client-side the
-- same way it always has, but this constraint means a collision now
-- fails the insert loudly instead of silently duplicating a ticket.
create sequence if not exists public.orders_ticket_seq;
do $$ begin
  alter table public.orders add constraint orders_ticket_unique unique (ticket);
exception when duplicate_object or duplicate_table then null;
end $$;

-- Promo codes: applying/validating one must not consume it -- only
-- creating the order that actually uses it should. validate_promo_code
-- replaces the old redeem_promo_code as the function checkout's "Apply"
-- button calls: same checks (exists / active / not expired / not
-- already used by this phone), but read-only. The actual consuming
-- insert now only ever happens inside create_order() above, via
-- _consume_promo_code below, which has no execute grant to anon/
-- authenticated -- so a code can only be burned by an order that
-- actually goes through, atomically, in the same transaction (if
-- anything else in create_order() fails, this insert rolls back with
-- it). The previous behavior (redeem_promo_code inserting immediately
-- at "Apply" time, before the order existed) meant a code could be
-- permanently burned by someone who applied it and then abandoned
-- checkout, or by anyone just calling the RPC directly, without ever
-- placing an order.
create or replace function public._consume_promo_code(p_code text, p_phone text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.promo_redemptions (code, phone) values (p_code, public.normalize_phone(p_phone));
exception when unique_violation then
  raise exception 'This phone number has already used that code.';
end;
$$;

create or replace function public.validate_promo_code(p_code text, p_phone text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(p_code));
  v_phone text := public.normalize_phone(p_phone);
  v_row public.promo_codes%rowtype;
begin
  if v_code = '' then
    raise exception 'Enter a promo code';
  end if;
  if v_phone = '' then
    raise exception 'A phone number is required to apply a promo code';
  end if;
  select * into v_row from public.promo_codes where code = v_code;
  if not found then
    raise exception 'That promo code doesn''t exist';
  end if;
  if not v_row.active then
    raise exception 'That promo code is no longer active';
  end if;
  if v_row."expiresAt" is not null and v_row."expiresAt" < (extract(epoch from now()) * 1000)::bigint then
    raise exception 'That promo code has expired';
  end if;
  if exists (select 1 from public.promo_redemptions where code = v_code and phone = v_phone) then
    raise exception 'This phone number has already used that code';
  end if;
  return jsonb_build_object('code', v_code, 'discountType', v_row."discountType", 'amount', v_row.amount, 'label', v_row.label);
end;
$$;
grant execute on function public.validate_promo_code(text, text) to anon, authenticated;

-- The old consuming RPC is fully replaced by validate_promo_code above
-- (apply-time check) + _consume_promo_code (order-creation-time, internal
-- only) -- drop it so nothing can call the old immediate-consume path.
drop function if exists public.redeem_promo_code(text, text);

-- Direct INSERT on orders is now staff-only. Every customer-sourced
-- order (signed in or not) must go through create_order() above, which
-- is the only place dollar amounts get computed -- there is no longer
-- any path for a request built by hand against the REST endpoint (using
-- the same public anon key already embedded in the page) to insert an
-- order with a manipulated price, since anon/authenticated no longer
-- have INSERT on this table at all, only EXECUTE on create_order().
-- Staff (POS) keep inserting directly, same as before -- they're
-- already trusted with full order UPDATE access, and POS legitimately
-- needs to ring up off-menu items, manual comps, etc. that a strict
-- menu-config validator would reject.
drop policy if exists "orders_insert_public" on public.orders;
drop policy if exists "orders_insert_staff_only" on public.orders;
create policy "orders_insert_staff_only" on public.orders
  for insert to authenticated
  with check (public.is_staff());
revoke insert on public.orders from anon;

-- Driver-only accounts (isDriver, not isAdmin) no longer get the same
-- broad order/CRM/till/roster visibility plain staff and admins get,
-- just because the Staff Hub UI happens to hide those screens for them
-- -- RLS is the actual boundary, not which buttons the UI shows. A
-- driver-only account can now only ever see delivery orders that are
-- either unclaimed and ready to grab, or already assigned to them
-- (matched through drivers.authUserId, not anything client-supplied).
create or replace function public.is_driver_only()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.staff where id = auth.uid() and active and "isDriver" and not "isAdmin");
$$;

drop policy if exists "orders_select_staff_or_own" on public.orders;
create policy "orders_select_staff_or_own" on public.orders
  for select to authenticated
  using (
    (public.is_staff() and not public.is_driver_only())
    or (
      public.is_driver_only() and "orderType" = 'delivery' and (
        (status = 'ready' and "driverId" is null)
        or "driverId" = (select id from public.drivers where "authUserId" = auth.uid())
      )
    )
    or ("customerId" is not null and "customerId" = auth.uid())
  );

drop policy if exists "orders_update_staff" on public.orders;
create policy "orders_update_staff" on public.orders
  for update to authenticated
  using (
    (public.is_staff() and not public.is_driver_only())
    or (
      public.is_driver_only() and "orderType" = 'delivery' and (
        (status = 'ready' and "driverId" is null)
        or "driverId" = (select id from public.drivers where "authUserId" = auth.uid())
      )
    )
  )
  with check (
    (public.is_staff() and not public.is_driver_only())
    or (
      public.is_driver_only() and "orderType" = 'delivery' and (
        (status = 'ready' and "driverId" is null)
        or "driverId" = (select id from public.drivers where "authUserId" = auth.uid())
      )
    )
  );

-- Same driver-scoping for customer profiles (a driver has no legitimate
-- reason to browse every customer's saved address/email/preferences)
-- and the till (nothing about register shifts concerns a driver role).
-- Own-row access is untouched either way.
drop policy if exists "customers_self" on public.customers;
create policy "customers_self" on public.customers
  for all to authenticated
  using (id = auth.uid() or (public.is_staff() and not public.is_driver_only()))
  with check (id = auth.uid());

drop policy if exists "register_shifts_staff_all" on public.register_shifts;
create policy "register_shifts_staff_all" on public.register_shifts
  for all to authenticated
  using (public.is_staff() and not public.is_driver_only())
  with check (public.is_staff() and not public.is_driver_only());

-- Staff roster: a driver-only account can still read its own row
-- (needed for the app's own role bootstrap -- see App.isDriverStaff in
-- staff/index.html) but can no longer browse the full staff list
-- (everyone else's admin/driver flags) the way any authenticated staff
-- row could before.
drop policy if exists "staff_select_staff" on public.staff;
create policy "staff_select_staff" on public.staff
  for select to authenticated
  using (id = auth.uid() or (public.is_staff() and not public.is_driver_only()));

-- =========================================================================
-- Regulars summary (repeat-customer aggregate), 2026-09-08
-- =========================================================================
-- Both the "Regular" badge (POS Queue, Kitchen Board) and Analytics'
-- "Regulars" list used to be computed client-side from whatever the
-- current orders subscription happened to have fetched -- for the
-- Kitchen Board/POS Queue that's the whole orders table with no limit
-- at all (risking PostgREST's default row cap silently truncating
-- older orders once lifetime history grew past it, systematically
-- undercounting anyone whose repeat visits span that boundary), and
-- Analytics' own version now only sees an 8-day window (see
-- initAnalyticsView), which would make its "$X lifetime" label actively
-- wrong for a genuine regular whose visits are spread out further than
-- that. This aggregates server-side instead -- one row per distinct
-- phone number, not per order, so the result stays small regardless of
-- how large the orders table grows -- and is the one source both
-- screens now read from. Not security definer: relies on the same RLS
-- a raw select already would (full history for staff, only their own
-- scoped deliveries for a driver-only account, only their own orders
-- for a signed-in customer), so it never exposes more than that caller
-- could already see directly.
create or replace function public.regulars_summary()
returns table(phone text, order_count bigint, total_spent numeric, last_order_at bigint, customer_name text)
language sql stable
as $$
  select
    o.phone,
    count(*) as order_count,
    sum(o.total) as total_spent,
    max(o."createdAt") as last_order_at,
    (array_agg(o."customerName" order by o."createdAt" desc))[1] as customer_name
  from public.orders o
  where o.phone <> '' and o.status <> 'cancelled'
  group by o.phone;
$$;
grant execute on function public.regulars_summary() to authenticated;

-- =========================================================================
-- Phase 4: Operational Monitoring (Staff Hub > System Health), 2026-09-08
-- =========================================================================
-- A read-only health snapshot for admins, and the plumbing that feeds
-- it. Three new tables, each intentionally small and narrow:
--
--   app_errors        -- structured client-side error telemetry, deduped
--                         by (source, message) rather than one row per
--                         occurrence, so a repeating error doesn't flood
--                         the table or the System Health screen. NEVER
--                         given customer data (name/phone/address/items)
--                         -- only a source tag and a short, generic
--                         message. Written via report_app_error() below,
--                         never a direct table insert, so that boundary
--                         is enforced in one place, not at every call
--                         site.
--   service_heartbeats -- for a local, off-site service (right now: the
--                         print-bridge, once it's actually deployed) to
--                         report "I'm alive" periodically. One row per
--                         service, upserted, so staleness alone (no
--                         write in the health check's own freshness
--                         window) means "assume it's down" without
--                         needing an explicit down signal.
--   external_health_checks -- results from a scheduled GitHub Actions
--                         workflow (.github/workflows/health-check.yml)
--                         that fetches the live homepage, kiosk, a
--                         couple of critical JS files, the hero GLB
--                         asset, and this same database, on a timer,
--                         from *outside* this app entirely -- catches
--                         "the site is actually down for a real visitor
--                         right now" in a way nothing inside the app
--                         itself ever could.
--
-- system_health() stitches all of this together (plus store_settings,
-- menu_config, recent orders, driver_locations staleness, and a
-- config-presence check for payments/SMS -- see its own comments below)
-- into one jsonb snapshot for the System Health screen to render.
-- Nothing in this section can ever block ordering: every reporting call
-- (report_app_error, report_service_heartbeat, report_external_check)
-- is a narrow, fire-and-forget write with no dependency running the
-- other direction, and system_health() is a pure read.

create table if not exists public.app_errors (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  message text not null,
  "occurrenceCount" int not null default 1,
  "firstSeenAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "lastSeenAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  unique (source, message)
);
alter table public.app_errors enable row level security;
-- No direct grants to anon/authenticated at all -- every write goes
-- through report_app_error() (security definer, below); only an admin
-- can browse the raw table directly for deeper debugging.
grant select on public.app_errors to authenticated;
drop policy if exists "app_errors_admin_select" on public.app_errors;
create policy "app_errors_admin_select" on public.app_errors
  for select to authenticated
  using (public.is_admin());

create or replace function public.report_app_error(p_source text, p_message text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_source text := left(trim(coalesce(p_source, 'unknown')), 60);
  v_message text := left(trim(coalesce(p_message, '')), 300);
begin
  if v_message = '' then return; end if;
  insert into public.app_errors (source, message)
  values (v_source, v_message)
  on conflict (source, message) do update
    set "occurrenceCount" = public.app_errors."occurrenceCount" + 1,
        "lastSeenAt" = (extract(epoch from now()) * 1000)::bigint;
exception when others then
  -- Telemetry must never be the thing that breaks the page that's
  -- trying to report a problem. Swallow anything unexpected here.
  return;
end;
$$;
grant execute on function public.report_app_error(text, text) to anon, authenticated;

create table if not exists public.service_heartbeats (
  service text primary key,
  status text not null default 'unknown',
  detail text,
  "lastSeenAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table public.service_heartbeats enable row level security;
grant select on public.service_heartbeats to authenticated;
drop policy if exists "service_heartbeats_admin_select" on public.service_heartbeats;
create policy "service_heartbeats_admin_select" on public.service_heartbeats
  for select to authenticated
  using (public.is_admin());

create or replace function public.report_service_heartbeat(p_service text, p_status text, p_detail text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_service text := left(trim(coalesce(p_service, '')), 60);
begin
  if v_service = '' then return; end if;
  insert into public.service_heartbeats (service, status, detail, "lastSeenAt")
  values (v_service, coalesce(nullif(trim(p_status), ''), 'unknown'), left(p_detail, 300), (extract(epoch from now()) * 1000)::bigint)
  on conflict (service) do update
    set status = excluded.status, detail = excluded.detail, "lastSeenAt" = excluded."lastSeenAt";
exception when others then
  return;
end;
$$;
-- Granted to anon too: the print-bridge is a small local script, not a
-- signed-in Staff Hub session, and has no natural way to hold a
-- Supabase Auth session of its own. Same narrow-RPC-only trust model as
-- everything else public-writable in this file (report_app_error
-- above, create_order, redeem/validate_promo_code) -- it can only ever
-- upsert its own named row with a status/detail string, nothing else.
grant execute on function public.report_service_heartbeat(text, text, text) to anon, authenticated;

create table if not exists public.external_health_checks (
  target text primary key,
  ok boolean not null,
  "statusCode" int,
  detail text,
  "checkedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table public.external_health_checks enable row level security;
grant select on public.external_health_checks to authenticated;
drop policy if exists "external_health_checks_admin_select" on public.external_health_checks;
create policy "external_health_checks_admin_select" on public.external_health_checks
  for select to authenticated
  using (public.is_admin());

create or replace function public.report_external_check(p_target text, p_ok boolean, p_status_code int, p_detail text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_target text := left(trim(coalesce(p_target, '')), 60);
begin
  if v_target = '' then return; end if;
  insert into public.external_health_checks (target, ok, "statusCode", detail, "checkedAt")
  values (v_target, coalesce(p_ok, false), p_status_code, left(p_detail, 300), (extract(epoch from now()) * 1000)::bigint)
  on conflict (target) do update
    set ok = excluded.ok, "statusCode" = excluded."statusCode", detail = excluded.detail, "checkedAt" = excluded."checkedAt";
exception when others then
  return;
end;
$$;
-- Granted to anon for the same reason as report_service_heartbeat: the
-- GitHub Actions workflow that calls this has no Staff Hub session
-- either, and this can only ever upsert one named row's pass/fail
-- result, nothing else.
grant execute on function public.report_external_check(text, boolean, int, text) to anon, authenticated;

-- The one read this whole section exists for. Admin-only (system
-- internals, not something every staff member needs); a plain function
-- (not security definer) is fine here since every table it touches
-- already grants admin full access via the policies above and
-- elsewhere in this file -- it just saves the System Health screen from
-- stitching together six separate queries with six different RLS
-- shapes into one call.
create or replace function public.system_health()
returns jsonb
language plpgsql stable
as $$
declare
  v_settings record;
  v_menu record;
  v_last_customer_order bigint;
  v_errors jsonb;
  v_stale_drivers int;
  v_active_drivers int;
  v_heartbeats jsonb;
  v_external jsonb;
  v_sms_sent int;
  v_sms_failed int;
  v_sms_total_recent int;
  v_payment_orders int;
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
begin
  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  select "ordersPaused", "pauseMessage", version, extract(epoch from "updatedAt")*1000 as updated_ms
    into v_settings from public.store_settings where id = 1;
  select version, extract(epoch from "updatedAt")*1000 as updated_ms
    into v_menu from public.menu_config where id = 1;

  select max("createdAt") into v_last_customer_order
    from public.orders where source = 'customer';

  select jsonb_agg(jsonb_build_object(
      'source', source, 'message', message, 'occurrenceCount', "occurrenceCount",
      'firstSeenAt', "firstSeenAt", 'lastSeenAt', "lastSeenAt"
    ) order by "lastSeenAt" desc)
    into v_errors
    from (select * from public.app_errors order by "lastSeenAt" desc limit 20) e;

  -- A driver row is "stale" if it hasn't updated in the last 5 minutes
  -- -- the client already treats anything that old as "may be offline"
  -- (see driver_locations' own comment in this file), so this reuses
  -- the same threshold rather than inventing a second one.
  select count(*) filter (where "updatedAt" < v_now - 5*60*1000), count(*)
    into v_stale_drivers, v_active_drivers
    from public.driver_locations;

  select jsonb_agg(jsonb_build_object(
      'service', service, 'status', status, 'detail', detail, 'lastSeenAt', "lastSeenAt"
    ))
    into v_heartbeats
    from public.service_heartbeats;

  select jsonb_agg(jsonb_build_object(
      'target', target, 'ok', ok, 'statusCode', "statusCode", 'detail', detail, 'checkedAt', "checkedAt"
    ))
    into v_external
    from public.external_health_checks;

  -- Payment/SMS health is derived entirely from real order data rather
  -- than a live network ping -- there is no live processor/sender to
  -- ping yet (see order/payments.js and supabase/functions/
  -- send-order-sms), and once there is, this same query starts
  -- reflecting reality automatically with no code change needed here:
  -- a provider showing up on real orders means it's configured: sent
  -- vs failed counts say whether it's actually working.
  select count(*) filter (where "smsStatus" = 'sent'),
         count(*) filter (where "smsStatus" = 'failed'),
         count(*) filter (where "phoneOptIn" and "createdAt" >= v_now - 7*86400000)
    into v_sms_sent, v_sms_failed, v_sms_total_recent
    from public.orders;

  select count(*) into v_payment_orders
    from public.orders where "paymentProvider" is not null;

  return jsonb_build_object(
    'checkedAt', v_now,
    'ordersPaused', coalesce(v_settings."ordersPaused", false),
    'pauseMessage', v_settings."pauseMessage",
    'storeSettingsVersion', v_settings.version,
    'storeSettingsUpdatedAt', v_settings.updated_ms,
    'menuConfigVersion', v_menu.version,
    'menuConfigUpdatedAt', v_menu.updated_ms,
    'lastCustomerOrderAt', v_last_customer_order,
    'recentErrors', coalesce(v_errors, '[]'::jsonb),
    'staleDriverCount', coalesce(v_stale_drivers, 0),
    'activeDriverLocationCount', coalesce(v_active_drivers, 0),
    'serviceHeartbeats', coalesce(v_heartbeats, '[]'::jsonb),
    'externalChecks', coalesce(v_external, '[]'::jsonb),
    'smsSentCount', coalesce(v_sms_sent, 0),
    'smsFailedCount', coalesce(v_sms_failed, 0),
    'smsOptInRecentCount', coalesce(v_sms_total_recent, 0),
    'paymentOrderCount', coalesce(v_payment_orders, 0)
  );
end;
$$;
grant execute on function public.system_health() to authenticated;

-- =========================================================================
-- Phase 8: Structured hours + scheduled orders + idempotency, 2026-09-08
-- =========================================================================
-- Regular weekly hours, moved into the database from where they used to
-- live: hardcoded HTML in index.html's static hours table. Needed for
-- real reasons now, not just tidiness -- scheduled orders (below) has
-- to validate a requested time against real business hours, and a SQL
-- function can't read a hardcoded HTML table. index.html keeps its own
-- static table too (unchanged) as the always-available fallback if this
-- fetch ever fails, same "no hard dependency" pattern as menu_config.
create table if not exists public.store_hours (
  -- Named `id` (not `dayOfWeek`) so the Firestore-shaped adapter's
  -- .doc(id).set() pattern (order/db-supabase.js) works directly here
  -- -- same reason promo_codes has a surrogate `id` column alongside
  -- its real business key. 0 = Sunday, matches JS Date.getDay().
  id smallint primary key check (id between 0 and 6),
  closed boolean not null default false,
  "openTime" time,
  "closeTime" time
);
-- Migration: this table briefly shipped with "dayOfWeek" as the primary
-- key column name before the adapter-compatibility need above was
-- caught. Renames in place if that's what's already live; a no-op
-- otherwise (including on a fresh database, where the column is
-- already named `id` from the create table above).
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='store_hours' and column_name='dayOfWeek') then
    alter table public.store_hours rename column "dayOfWeek" to id;
  end if;
end $$;
alter table public.store_hours enable row level security;
grant select on public.store_hours to anon, authenticated;
drop policy if exists "store_hours_public_read" on public.store_hours;
create policy "store_hours_public_read" on public.store_hours
  for select to anon, authenticated using (true);
grant insert, update, delete on public.store_hours to authenticated;
drop policy if exists "store_hours_admin_write" on public.store_hours;
create policy "store_hours_admin_write" on public.store_hours
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into public.store_hours (id, closed, "openTime", "closeTime") values
  (0, false, '11:00', '21:00'), (1, false, '11:00', '21:00'),
  (2, false, '11:00', '21:00'), (3, false, '11:00', '21:00'),
  (4, false, '11:00', '22:00'), (5, false, '11:00', '22:00'),
  (6, false, '11:00', '22:00')
on conflict (id) do nothing;

-- Dated overrides (holidays, one-off early closures, etc.) -- this is
-- the real upgrade from the old hoursOverrideActive/hoursOverrideNote
-- pair on store_settings (kept as-is, still just a banner-trigger for
-- the homepage; this table is the actual structured data behind
-- ordering availability and scheduling). One row per calendar date.
create table if not exists public.store_hours_overrides (
  id date primary key, -- the calendar date this override applies to; named `id` for the same adapter-compatibility reason as store_hours.id above
  "closedAllDay" boolean not null default false,
  "openTime" time,
  "closeTime" time,
  note text not null default '',
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "createdBy" uuid references auth.users(id)
);
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='store_hours_overrides' and column_name='date') then
    alter table public.store_hours_overrides rename column date to id;
  end if;
end $$;
alter table public.store_hours_overrides enable row level security;
grant select on public.store_hours_overrides to anon, authenticated;
drop policy if exists "store_hours_overrides_public_read" on public.store_hours_overrides;
create policy "store_hours_overrides_public_read" on public.store_hours_overrides
  for select to anon, authenticated using (true);
grant insert, update, delete on public.store_hours_overrides to authenticated;
drop policy if exists "store_hours_overrides_admin_write" on public.store_hours_overrides;
create policy "store_hours_overrides_admin_write" on public.store_hours_overrides
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- The one function everything else (create_order's scheduling
-- validation, and eventually the homepage/kiosk) reads hours through --
-- an override for a date always wins over that date's regular weekly
-- hours, field by field.
create or replace function public.hours_for_date(p_date date)
returns table(closed boolean, "openTime" time, "closeTime" time, "isOverride" boolean, note text)
language sql stable
as $$
  select
    coalesce(o."closedAllDay", h.closed, false) as closed,
    coalesce(o."openTime", h."openTime") as "openTime",
    coalesce(o."closeTime", h."closeTime") as "closeTime",
    (o.id is not null) as "isOverride",
    coalesce(o.note, '') as note
  from (select p_date as d) x
  left join public.store_hours h on h.id = extract(dow from p_date)::smallint
  left join public.store_hours_overrides o on o.id = p_date;
$$;
grant execute on function public.hours_for_date(date) to anon, authenticated;

-- Idempotency + scheduling support on orders. idempotencyKey lets a
-- retried/double-submitted checkout (a slow network prompting a second
-- click, a retried request) return the SAME order instead of creating
-- a duplicate -- create_order() checks this first, before anything
-- else, and returns the original result if it finds a match. Needed
-- for correctness today (double-submit protection) and is also the
-- exact mechanism a real payment integration needs later (see
-- OWNER-TODO.md) to avoid double-charging on a retried webhook.
-- scheduledFor is null for an ASAP order (all of today's behavior,
-- unchanged) or a future epoch-ms pickup/delivery time for a scheduled
-- one, validated in create_order() against hours_for_date() above.
alter table public.orders add column if not exists "idempotencyKey" text;
create unique index if not exists orders_idempotency_key_idx on public.orders ("idempotencyKey") where "idempotencyKey" is not null;
alter table public.orders add column if not exists "scheduledFor" bigint;
create index if not exists orders_scheduledfor_idx on public.orders ("scheduledFor") where "scheduledFor" is not null;

-- =========================================================================
-- Phase 8: Favorites, Marketing Opt-In, Loyalty, Catering, 2026-09-08
-- =========================================================================

-- Favorites ("My Usual"). Saves a canonical item reference (the same
-- `ref` shape create_order() already validates and reorder already
-- resolves -- see resolveRefToLine() in order/ordering-core.js), never
-- a price, so "adding a favorite to cart" always re-prices against the
-- current menu the exact same way a reorder does. Own-row access only.
create table if not exists public.customer_favorites (
  id uuid primary key default gen_random_uuid(),
  "customerId" uuid not null references auth.users(id) on delete cascade,
  label text not null,
  ref jsonb not null,
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists customer_favorites_customer_idx on public.customer_favorites ("customerId");
alter table public.customer_favorites enable row level security;
grant select, insert, delete on public.customer_favorites to authenticated;
drop policy if exists "customer_favorites_own" on public.customer_favorites;
create policy "customer_favorites_own" on public.customer_favorites
  for all to authenticated using ("customerId" = auth.uid()) with check ("customerId" = auth.uid());

-- Marketing opt-in, deliberately separate from phoneOptIn on orders
-- (that one's transactional -- "text me when THIS order's ready" --
-- and needs no separate consent model). This is promotional consent:
-- default off, stores channel/timestamp/source the way real opt-in
-- records should, and nothing sends to it until a real provider is
-- wired up (same "not configured yet" state as SMS order notifications
-- -- see OWNER-TODO.md). Lives on customers since it's account-level
-- preference, not tied to any one order.
alter table public.customers add column if not exists "marketingOptIn" boolean not null default false;
alter table public.customers add column if not exists "marketingOptInChannel" text;
alter table public.customers add column if not exists "marketingOptInAt" bigint;
alter table public.customers add column if not exists "marketingOptInSource" text;

-- Loyalty: configurable, server-controlled, disabled by default -- the
-- owner hasn't chosen point/reward rules yet (see OWNER-TODO.md), so
-- this ships inert. enabled=false means award_loyalty_points() below
-- is a no-op on every order, and the client-side balance display
-- (Account panel) only shows up once this reads enabled=true.
create table if not exists public.loyalty_config (
  id int primary key default 1,
  enabled boolean not null default false,
  "pointsPerDollar" numeric(6,2) not null default 1,
  "rewardThresholdPoints" int not null default 100,
  "rewardDescription" text not null default '$5 off your next order',
  "updatedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "updatedBy" uuid references auth.users(id),
  constraint loyalty_config_singleton check (id = 1)
);
alter table public.loyalty_config enable row level security;
grant select on public.loyalty_config to anon, authenticated;
drop policy if exists "loyalty_config_public_read" on public.loyalty_config;
create policy "loyalty_config_public_read" on public.loyalty_config
  for select to anon, authenticated using (true);
grant update on public.loyalty_config to authenticated;
drop policy if exists "loyalty_config_admin_write" on public.loyalty_config;
create policy "loyalty_config_admin_write" on public.loyalty_config
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
insert into public.loyalty_config (id) values (1) on conflict (id) do nothing;

create table if not exists public.loyalty_points (
  "customerId" uuid primary key references auth.users(id) on delete cascade,
  points int not null default 0,
  "updatedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table public.loyalty_points enable row level security;
grant select on public.loyalty_points to authenticated;
drop policy if exists "loyalty_points_own_select" on public.loyalty_points;
create policy "loyalty_points_own_select" on public.loyalty_points
  for select to authenticated using ("customerId" = auth.uid() or (public.is_staff() and not public.is_driver_only()));
-- No direct insert/update grant to anyone -- only award_loyalty_points()
-- (security definer, below) ever writes here, so a balance can only
-- ever come from a real completed order while the program is enabled,
-- never a client-supplied number.

create or replace function public.award_loyalty_points()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_enabled boolean;
  v_rate numeric;
  v_points int;
begin
  if new.status = 'completed' and old.status is distinct from 'completed' and new."customerId" is not null then
    select enabled, "pointsPerDollar" into v_enabled, v_rate from public.loyalty_config where id = 1;
    if coalesce(v_enabled, false) then
      v_points := floor(new.total * coalesce(v_rate, 1));
      if v_points > 0 then
        insert into public.loyalty_points ("customerId", points, "updatedAt")
        values (new."customerId", v_points, (extract(epoch from now()) * 1000)::bigint)
        on conflict ("customerId") do update
          set points = public.loyalty_points.points + v_points, "updatedAt" = excluded."updatedAt";
      end if;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists orders_award_loyalty on public.orders;
create trigger orders_award_loyalty
  after update on public.orders
  for each row execute function public.award_loyalty_points();

-- Catering / large-order inquiries. Deliberately its own table, not the
-- orders table -- an inquiry is a conversation starter, not a
-- confirmed, payable order, and must never show up in the kitchen
-- queue. Public insert (the inquiry form has no login), staff-only
-- read/update (the review/status workflow lives in Staff Hub), same
-- driver-scoping as everything else staff-visible (a driver has no
-- reason to see these).
create table if not exists public.catering_inquiries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  email text not null default '',
  "eventDate" date,
  "guestCount" int,
  details text not null default '',
  status text not null default 'new' check (status in ('new','contacted','quoted','confirmed','declined')),
  "createdAt" bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "updatedAt" bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists catering_inquiries_status_idx on public.catering_inquiries (status);
alter table public.catering_inquiries enable row level security;
grant insert on public.catering_inquiries to anon, authenticated;
drop policy if exists "catering_inquiries_insert_public" on public.catering_inquiries;
create policy "catering_inquiries_insert_public" on public.catering_inquiries
  for insert to anon, authenticated with check (true);
grant select, update on public.catering_inquiries to authenticated;
drop policy if exists "catering_inquiries_staff_select" on public.catering_inquiries;
create policy "catering_inquiries_staff_select" on public.catering_inquiries
  for select to authenticated using (public.is_staff() and not public.is_driver_only());
drop policy if exists "catering_inquiries_staff_update" on public.catering_inquiries;
create policy "catering_inquiries_staff_update" on public.catering_inquiries
  for update to authenticated using (public.is_staff() and not public.is_driver_only()) with check (public.is_staff() and not public.is_driver_only());

drop trigger if exists catering_inquiries_set_updated_at on public.catering_inquiries;
create trigger catering_inquiries_set_updated_at
  before update on public.catering_inquiries
  for each row execute function public.set_orders_updated_at();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'catering_inquiries'
  ) then
    alter publication supabase_realtime add table public.catering_inquiries;
  end if;
end $$;

insert into public.menu_config (id, data)
values (1, $json${"TAX_RATE": 0.06625, "PIZZA_SIZES": [{"key": "personal", "label": "Personal Pan (9\")", "base": 8, "perTopping": 1}, {"key": "medium", "label": "Medium (14\")", "base": 14.5, "perTopping": 3}, {"key": "large", "label": "Large (16\")", "base": 15.99, "perTopping": 3.5}, {"key": "sicilian", "label": "Sicilian (16x16\")", "base": 17.99, "perTopping": 4}], "TOPPINGS": ["Pepperoni", "Sausage", "Bacon", "Meatball", "Ham", "Extra Cheese", "Green Pepper", "Onion", "Black Olive", "Mushroom", "Anchovy", "Pineapple", "Spinach", "Broccoli"], "SPECIALTY_PIZZAS": [{"name": "Bacon BBQ Chicken Ranch", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 26}]}, {"name": "Buffalo Chicken", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 26}]}, {"name": "Hawaiian", "sizes": [{"label": "Medium", "price": 20.5}, {"label": "Large", "price": 22.99}, {"label": "Sicilian", "price": 24.99}]}, {"name": "White Pie", "sizes": [{"label": "Medium", "price": 14.5}, {"label": "Large", "price": 15.99}, {"label": "Sicilian", "price": 17.99}]}, {"name": "The Works", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 25.99}, {"label": "Sicilian", "price": 29.99}]}], "CATEGORIES": [{"key": "panzarotti", "label": "Panzarotti", "note": "Deep fried and golden brown", "items": [{"name": "Panzarotti", "price": 8.25, "desc": "Add $0.75 per extra ingredient"}]}, {"key": "stromboli", "label": "Stromboli", "photo": "../images/menu/stromboli.jpg", "placeholder": "../images/menu/stromboli.svg", "items": [{"name": "Cheese Stromboli", "price": 17.99, "desc": "+$2.50 per topping, +$5.00 steak or chicken"}, {"name": "Steak & Onion Stromboli", "price": 24.99}]}, {"key": "calzones", "label": "Calzones", "photo": "../images/menu/calzone.jpg", "placeholder": "../images/menu/calzone.svg", "items": [{"name": "Calzone", "price": 14.99, "desc": "Ham, ricotta, mozzarella and sauce"}]}, {"key": "turnover", "label": "Pizza Turnover", "items": [{"name": "Pizza Turnover", "price": 13.5, "desc": "Mozzarella and pizza sauce, $1 per extra ingredient"}]}, {"key": "wings", "label": "Wings", "note": "All wings come with bread and blue cheese", "photo": "../images/menu/wings.jpg", "placeholder": "../images/menu/wings.svg", "items": [{"name": "Wings", "size": "8 pc", "price": 9.5}, {"name": "Wings", "size": "12 pc", "price": 14.99}, {"name": "Wings", "size": "16 pc", "price": 18.99}, {"name": "Wings", "size": "24 pc", "price": 27.99}]}, {"key": "steaks", "label": "Steaks", "note": "Chicken made with 100% boneless, skinless breast meat", "items": [{"name": "Plain Steak", "price": 11}, {"name": "Cheese Steak", "price": 12}, {"name": "Chicken Cheese Steak", "price": 12}, {"name": "Bacon Cheese Steak", "price": 13}, {"name": "Cheese Steak Sub", "price": 13}, {"name": "Chicken Cheese Steak Sub", "price": 13}, {"name": "Mushroom Cheese Steak", "price": 13}, {"name": "Pepperoni Cheese Steak", "price": 13}, {"name": "Pizza Steak", "price": 13}, {"name": "Buffalo Chicken Cheese Steak", "price": 13}, {"name": "Broccoli Garlic & Oil Chicken Cheese Steak", "price": 13}, {"name": "Cheese Steak Special", "price": 13.75}, {"name": "Cheese Steak Platter", "price": 14.99}]}, {"key": "hoagies", "label": "Hoagies", "note": "All hoagies made with lettuce, tomato, onion and oil", "photo": "../images/menu/hoagie.jpg", "placeholder": "../images/menu/hoagie.svg", "items": [{"name": "Mixed Cheese", "price": 11}, {"name": "American", "price": 11.5}, {"name": "Ham & Cheese", "price": 12}, {"name": "Italian", "price": 12}, {"name": "Turkey & Cheese", "price": 12}, {"name": "Roast Beef, Provolone or American", "price": 13}, {"name": "Fried Fish Hoagie", "price": 13}]}, {"key": "pasta", "label": "Pasta", "note": "Served with soup, salad and garlic bread, spaghetti or ziti", "photo": "../images/menu/pasta.jpg", "placeholder": "../images/menu/pasta.svg", "items": [{"name": "Tomato Sauce", "price": 12.99}, {"name": "Meatballs", "price": 16.99}, {"name": "Sausage", "price": 16.99}]}, {"key": "parm", "label": "Parmigiana Dinners", "note": "Served with salad and garlic bread or a side of spaghetti/ziti", "items": [{"name": "Eggplant Parmigiana", "price": 15.99}, {"name": "Chicken Cutlet Parmigiana", "price": 16.99}]}, {"key": "hotsand", "label": "Hot Sandwiches", "items": [{"name": "Homemade Meatball Sandwich", "price": 11.5}, {"name": "Eggplant Parmigiana", "price": 11}, {"name": "Homemade Meatball Parmigiana", "price": 12.5}, {"name": "Chicken Parmigiana", "price": 12.5}, {"name": "Sausage Parmigiana", "price": 12.5}, {"name": "Hot Roast Beef", "price": 12}, {"name": "Hot Roast Beef with Cheese", "price": 13}, {"name": "Sausage Supreme", "price": 12.99}]}, {"key": "italian", "label": "Italian Specialties", "note": "Served with soup, salad and garlic bread", "items": [{"name": "Baked Ziti", "price": 16.99}, {"name": "Cheese Ravioli", "price": 16.99}, {"name": "Stuffed Shells Parmigiana", "price": 16.99}]}, {"key": "platters", "label": "Platters", "items": [{"name": "BLT Club", "price": 12.99}, {"name": "Chicken Finger Platter", "price": 13.99}, {"name": "Ham & Cheese Club", "price": 13.99}, {"name": "Chicken Club", "price": 14.99}, {"name": "Roast Beef Club", "price": 14.99}, {"name": "Turkey Club", "price": 14.99}, {"name": "Shrimp Platter", "price": 14.99}]}, {"key": "burgers", "label": "Quarter Pound Burgers", "photo": "../images/menu/burger.jpg", "placeholder": "../images/menu/burger.svg", "items": [{"name": "Hamburger", "price": 7}, {"name": "Cheeseburger", "price": 8}, {"name": "Bacon Cheeseburger", "price": 9}, {"name": "Pizza Burger", "price": 9}, {"name": "Cheese Burger Sub", "price": 13}]}, {"key": "sides", "label": "Side Orders", "items": [{"name": "French Fries", "price": 5.75}, {"name": "Onion Rings", "price": 8}, {"name": "Poppers", "size": "Cheddar", "price": 8}, {"name": "Breaded Mushrooms", "price": 8.5}, {"name": "Broccoli Bites", "price": 8.5}, {"name": "Meatballs", "price": 8.5}, {"name": "Mozzarella Sticks", "price": 8.5}, {"name": "Pizza Fries", "size": "Small", "price": 8.5}, {"name": "Pizza Fries", "size": "Large", "price": 10.5}, {"name": "Sausage", "price": 8.5}, {"name": "Fried Tomato", "price": 9}, {"name": "Cheese Fries", "size": "Small", "price": 6.5}, {"name": "Cheese Fries", "size": "Large", "price": 9}, {"name": "Loaded Fries", "size": "Small", "price": 9.5}, {"name": "Loaded Fries", "size": "Large", "price": 10.5}, {"name": "Homemade Cole Slaw", "size": "Pint", "price": 3.5}, {"name": "Homemade Cole Slaw", "size": "Quart", "price": 7}, {"name": "Something Sweet Zeppoli", "size": "Small", "price": 4}, {"name": "Something Sweet Zeppoli", "size": "Large", "price": 8}]}, {"key": "soups", "label": "Soups", "items": [{"name": "Pasta Faggioli", "size": "Small", "price": 4.99}, {"name": "Pasta Faggioli", "size": "Quart", "price": 8.99}, {"name": "Chili", "size": "Small, winter", "price": 6.5}, {"name": "Chili", "size": "Quart, winter", "price": 11.99}]}, {"key": "salads", "label": "Salads", "photo": "../images/menu/salad.jpg", "placeholder": "../images/menu/salad.svg", "items": [{"name": "Tossed Salad", "price": 7.99}, {"name": "Antipasta", "price": 12.99}, {"name": "Chef Salad", "price": 12.99}, {"name": "Chicken Caesar Salad", "price": 12.99}, {"name": "Grilled Chicken Salad", "price": 12.99}]}, {"key": "breakfast", "label": "Breakfast", "items": [{"name": "Grilled Cheese", "price": 7, "desc": "+$1 to add ham or bacon"}, {"name": "Bacon, Lettuce & Tomato", "price": 8}, {"name": "Pepper and Egg", "price": 10}, {"name": "Bacon, Egg and Cheese", "price": 11}, {"name": "Sausage, Egg and Cheese", "price": 11}, {"name": "Pork Roll, Egg and Cheese", "price": 11}]}, {"key": "knots", "label": "Garlic Knots", "items": [{"name": "Garlic Knots", "size": "6 pc", "price": 4.75}]}, {"key": "drinks", "label": "Drinks", "note": "We carry Pepsi products -- names/prices are a starting point, adjust in Staff Hub > Menu Editor to match what you actually stock", "items": [{"name": "Pepsi", "size": "20 oz", "price": 2.75}, {"name": "Diet Pepsi", "size": "20 oz", "price": 2.75}, {"name": "Pepsi Zero Sugar", "size": "20 oz", "price": 2.75}, {"name": "Mountain Dew", "size": "20 oz", "price": 2.75}, {"name": "Starry", "size": "20 oz", "price": 2.75}, {"name": "Mug Root Beer", "size": "20 oz", "price": 2.75}, {"name": "Brisk Iced Tea", "size": "20 oz", "price": 2.75}, {"name": "Aquafina Water", "size": "20 oz", "price": 2.0}, {"name": "Pepsi", "size": "2 Liter", "price": 4.5}, {"name": "Diet Pepsi", "size": "2 Liter", "price": 4.5}, {"name": "Mountain Dew", "size": "2 Liter", "price": 4.5}, {"name": "Starry", "size": "2 Liter", "price": 4.5}]}], "SPECIALS_BY_DAY": {"0": {"name": "4 Original Panzarotti", "price": 25.99}, "1": {"name": "2 Cheese Steaks", "price": 20.99}, "2": {"name": "Large Pizza", "price": 13.99}, "3": {"name": "Sicilian Pie", "price": 15.99}, "4": {"name": "2 Chicken Finger Platters", "price": 22.99}, "5": {"name": "Stromboli + 2 Liter Soda", "price": 18.5}, "6": {"name": "Cheese Steak Platter", "price": 13.99}}}$json$::jsonb)
on conflict (id) do nothing;
