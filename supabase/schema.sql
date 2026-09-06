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
-- The Customer Kiosk (order/) is public and talks to Supabase with the
-- anon key, but it only ever needs to CREATE an order, it never reads
-- the orders table back (the confirmation screen shows the ticket number
-- it already generated client-side). The Staff Hub (staff/) requires a
-- Supabase Auth sign-in before it renders anything, and it is the only
-- place that reads or updates orders (POS queue, Kitchen Board, Driver
-- App). So the anon role only needs INSERT, and SELECT/UPDATE are
-- restricted to authenticated (signed-in staff) sessions. Without this,
-- anyone who opened the page source and copied the anon key could read
-- every customer's name, phone number and delivery address, or change
-- order statuses, without ever signing in.
--
-- Create staff accounts in the Supabase dashboard under Authentication >
-- Users, then sign in at /staff/ with that email and password. See
-- supabase/README.md.
alter table public.orders enable row level security;

-- Explicit grants. RLS policies only ever narrow what a grant already
-- allows, they never grant access on their own (Postgres checks table
-- grants first, then RLS). Some Supabase projects don't hand the anon
-- and authenticated roles table privileges by default, which surfaces
-- as the exact same "violates row-level security policy" error as a
-- missing policy even though the policies below are correct. These
-- grants make sure that is never the cause. Safe to re-run.
grant insert on public.orders to anon, authenticated;
grant select, update on public.orders to authenticated;

drop policy if exists "orders_insert_anyone" on public.orders;
drop policy if exists "orders_insert_public" on public.orders;
create policy "orders_insert_public" on public.orders
  for insert to anon, authenticated
  with check (true);

drop policy if exists "orders_select_anyone" on public.orders;
drop policy if exists "orders_select_staff" on public.orders;
create policy "orders_select_staff" on public.orders
  for select to authenticated
  using (true);

drop policy if exists "orders_update_anyone" on public.orders;
drop policy if exists "orders_update_staff" on public.orders;
create policy "orders_update_staff" on public.orders
  for update to authenticated
  using (true)
  with check (true);

-- No delete policy: orders are never deleted from the app, only marked
-- 'cancelled' or 'completed'. That keeps a full history and avoids
-- accidental data loss. Delete manually in the dashboard if you ever need
-- to clear test data.
