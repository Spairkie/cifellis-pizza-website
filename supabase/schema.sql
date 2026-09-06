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
  total         numeric(10,2) not null default 0,
  status        text not null default 'new' check (status in ('new','preparing','ready','out_for_delivery','completed','cancelled')),
  driver        text,
  "createdAt"   bigint not null default (extract(epoch from now()) * 1000)::bigint,
  "updatedAt"   bigint not null default (extract(epoch from now()) * 1000)::bigint
);

create index if not exists orders_status_idx on public.orders (status);
create index if not exists orders_created_idx on public.orders ("createdAt");

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
-- MVP policy: this app has no login for the customer kiosk, staff POS,
-- kitchen board, or driver app, so every one of them talks to Supabase with
-- the anon public key. That means anyone with the anon key (visible in the
-- page source) can read and write every order. That is an accepted
-- trade-off for a single-location shop's internal tools running on
-- trusted devices, matching how the previous prototype worked, but it is
-- NOT the same as having no security: it still requires knowing your
-- Supabase URL, and RLS still blocks anything these policies do not
-- explicitly allow (deletes, other tables, etc).
--
-- If you later add staff/driver logins (Supabase Auth), tighten these to
-- check auth.uid() or a custom claim instead of allowing anon.
alter table public.orders enable row level security;

drop policy if exists "orders_insert_anyone" on public.orders;
create policy "orders_insert_anyone" on public.orders
  for insert to anon, authenticated
  with check (true);

drop policy if exists "orders_select_anyone" on public.orders;
create policy "orders_select_anyone" on public.orders
  for select to anon, authenticated
  using (true);

drop policy if exists "orders_update_anyone" on public.orders;
create policy "orders_update_anyone" on public.orders
  for update to anon, authenticated
  using (true)
  with check (true);

-- No delete policy: orders are never deleted from the app, only marked
-- 'cancelled' or 'completed'. That keeps a full history and avoids
-- accidental data loss. Delete manually in the dashboard if you ever need
-- to clear test data.
