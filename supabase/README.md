# Setting up the live order database (Supabase)

This is the one manual step needed to make online ordering, the staff POS,
the kitchen board and the driver app actually share live data. It takes
about five minutes and costs nothing.

## 1. Create a free Supabase account and project

1. Go to [supabase.com](https://supabase.com) and sign up (GitHub login is
   the fastest way).
2. Click **New project**. Pick any name (e.g. `cifellis-pizza`), generate a
   database password (save it somewhere, you likely will not need it again),
   and pick a region close to New Jersey (e.g. `us-east-1`).
3. Wait about two minutes for the project to finish provisioning.

## 2. Run the schema

1. In your new project, open **SQL Editor** (left sidebar) > **New query**.
2. Open `supabase/schema.sql` from this repo, copy its entire contents, and
   paste it into the SQL Editor.
3. Click **Run**. You should see "Success. No rows returned." This creates
   the `orders` table, turns on live updates for it, and sets up the access
   rules (row level security policies).

## 3. Get your project URL and anon key

1. Open **Project Settings** (gear icon) > **API**.
2. Copy the **Project URL** (looks like `https://xxxxxxxxxxxx.supabase.co`).
3. Copy the **anon public** key (a long string starting with `eyJ...`). Do
   **not** copy the `service_role` key, that one must never appear in
   frontend code.

## 4. Paste them into the app

Open `order/supabase-config.js` in this repo and fill in the two values:

```js
window.SUPABASE_URL = 'https://xxxxxxxxxxxx.supabase.co';
window.SUPABASE_ANON_KEY = 'eyJ...';
```

Commit and push (or ask Claude to). Once GitHub Pages redeploys (usually
under a minute), reload the Order Hub and the red "Not connected" banner
should be gone.

## 5. Turn on email sign-in and create staff accounts

The Staff Hub (`/staff/`) requires a Supabase Auth sign-in before it shows
the POS, Kitchen Board or Driver App screens, only the public Customer
Kiosk (`/order/`) works with no login.

1. Open **Authentication** (left sidebar) > **Sign In / Providers**, and
   confirm **Email** is enabled (it is on by default).
2. Open **Authentication** > **Users** > **Add user** > **Create new user**.
   Enter an email and password for each staff member (or one shared login
   for the whole counter, whichever fits how the shop runs). Check
   **Auto Confirm User** so they can sign in immediately without a
   confirmation email.
3. Give that email and password to whoever will use the Staff Hub. They
   sign in at `/staff/` on whatever device runs POS, Kitchen Board, or
   Driver App. Signing in is remembered on that device until they sign out.

## What this gets you, for free

Supabase's free tier includes a real Postgres database, live realtime
subscriptions (how the kitchen board and driver app update instantly), and
500 MB of storage, which is far more than a single pizza shop's order
history will use in years. The one catch: a free project pauses itself
after **one week with no activity at all** (no page opened, no order
placed). A shop taking orders daily will not hit this. If it ever does
pause, open the project dashboard and click **Restore**, it takes under a
minute and no data is lost.

## About security

The Customer Kiosk creates orders using the public anon key, and that is
all it can do: `schema.sql` only grants the anon role INSERT on the
`orders` table. Reading the order list back (the POS queue, the Kitchen
Board, the Driver App) and updating an order's status both require an
authenticated Supabase session, which is what the Staff Hub's sign-in
screen provides. That means the anon key being visible in the page source
(which it always will be, for any frontend app) no longer exposes every
customer's name, phone number and delivery address, only staff who have
signed in can read that.

There is currently one tier of staff account, anyone who can sign in to
`/staff/` can use POS, Kitchen Board and Driver App equally. If this ever
needs finer-grained roles (drivers who can't see the POS cash drawer, for
instance), that is a further Supabase Auth policy worth adding before it
becomes a real problem.

## If you see "new row violates row-level security policy for table orders"

This means Postgres is blocking the Customer Kiosk from creating an order.
It almost always means the INSERT policy from `schema.sql` either never
ran or isn't there anymore (a project reset, a partial run that hit an
error partway through, or a table that got recreated from the Table
Editor UI instead of the SQL script all cause this). Fix it by re-running
just the access-rules section, safe to run as many times as you want:

1. Open **SQL Editor** > **New query** in your Supabase project.
2. Paste this and click **Run**:

```sql
alter table public.orders enable row level security;

grant insert on public.orders to anon, authenticated;
grant select, update on public.orders to authenticated;

drop policy if exists "orders_insert_public" on public.orders;
create policy "orders_insert_public" on public.orders
  for insert to anon, authenticated
  with check (true);
```

3. To confirm it took, run `select * from pg_policies where tablename =
   'orders';` — you should see `orders_insert_public` listed with
   `cmd = INSERT` and `roles = {anon,authenticated}`.
4. Reload the Order Hub and try again.

If it still fails, open the browser console when placing the order and
look for the error's `code` field. `42501` with "row-level security" is
the policy issue above. `PGRST301` or "JWT" usually means the
`SUPABASE_ANON_KEY` in `order/supabase-config.js` doesn't match the
project the policy was created in (e.g. it was copied from a different
or older Supabase project). A plain "Failed to fetch" is a network or
`SUPABASE_URL` typo, not RLS at all.

## If you would rather not use Supabase

The app talks to the database only through `order/db-supabase.js`, a small
adapter file. Swapping in a different backend (your own Node server, a
different managed database) means rewriting that one file to the same
four methods it currently exposes (`collection().add()`,
`collection().doc().update()`, `collection().onSnapshot()`, `.orderBy()`),
nothing else in the app needs to change.
