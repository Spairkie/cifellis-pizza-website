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

## Before you re-run schema.sql if you already have staff signed in

**This matters if you're updating an existing project, not setting one up
fresh.** This version adds customer accounts, and doing that safely
required a real access-control change: there's now a `staff` table that
says who's staff, and only rows in it can read or manage orders. Before
this, *any* signed-in user was treated as staff (there was no other
kind of signed-in user). If you skip the step below, your existing
staff accounts will still be able to sign in, but every screen will
look empty or broken, because they're no longer recognized as staff.

Run this once, in the SQL Editor, **before** any customer creates an
account (right after running the updated `schema.sql` is the right
time):

```sql
insert into public.staff (id)
select id from auth.users
on conflict (id) do nothing;
```

This makes everyone who has ever signed in count as staff, which is
exactly the group that should be staff today. Do not run it again once
customers start signing up — at that point add new staff (and drivers)
one at a time from the Table Editor instead, on the `staff` table.

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
3. **New step:** open **Table Editor** > `staff`, and add a row with
   that same user's `id` (copy it from the Authentication > Users list).
   Signing in with an email/password Supabase recognizes is no longer
   enough on its own — a row here is what actually grants access to
   orders. Check `isDriver` if this person is a driver (see "Driver
   accounts" below); leave it unchecked for POS/Kitchen/Analytics
   staff.
4. Give that email and password to whoever will use the Staff Hub. They
   sign in at `/staff/` on whatever device runs POS, Kitchen Board, or
   Driver App. Signing in is remembered on that device until they sign out.

## Bootstrap your first admin

Approving driver applications from the app (rather than the SQL
Editor every time) requires at least one **admin** — a staff member
with `isAdmin` checked. Nothing in the app can grant the very first
admin that permission (that would be a hole an attacker could drive a
truck through), so it's a one-time manual step:

1. Find your own user id: **Authentication** > **Users**, copy the id
   next to your account.
2. Run in the SQL Editor:
   ```sql
   update public.staff set "isAdmin" = true where id = '<your-user-id>';
   ```

After that, you (and anyone else you make an admin the same way) can
approve driver applications and add other staff/admins right from the
Staff Hub, no SQL Editor needed for routine approvals.

## Driver accounts

Two ways someone becomes a driver:

**They apply themselves (recommended for most hires).** Send them to
`/staff/apply.html` — no login needed to get there. They pick their
own email/password (that's their Supabase Auth login, created right
in that step) and fill in their name, phone, and car info. It lands in
**Staff Hub > Driver Roster > Pending Applications**, where an admin
clicks **Approve**. That one click does everything: adds them to the
`staff` table (`isDriver` true) and marks their driver profile
approved. Before that click, their login exists but grants access to
nothing — signing in just shows "no driver profile found."

**You add them directly.** Useful if you'd rather not have them
self-serve. Create their Supabase Auth account yourself (step 5
above), add them to `staff` with `isDriver` checked, then **Driver
Roster > Add Driver** using the same email. This path skips the
pending/approval step entirely since you're vouching for them by
creating the account yourself.

Either way, the email on the `drivers` profile is what matches a
signed-in driver to their profile and their history (deliveries,
miles, tips, ratings) the first time they open the Driver App.

## Customer accounts

No setup needed — this works automatically once `schema.sql` has run.
A customer can place orders with no account at all (the default), or
tap **Sign In / Create Account** in the Customer Kiosk to make one.
Creating an account links to whatever phone number they give at
signup, so any past orders placed anonymously with that same phone
number show up in their order history right away — nothing to migrate
by hand.

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

There are two different causes that produce this exact same message.
Fixed as of the code in this repo, but documented here in case it comes
back (e.g. you're comparing against an older copy, or debugging
something similar in a new table):

**Cause 1: the actual root cause we hit** — `order/db-supabase.js`'s
`add()` used to chain `.select('id')` after the insert, so it could
hand back the new row's id. But chaining `.select()` makes PostgREST
read the row back before responding, which requires a SELECT policy —
and the anon role (Customer Kiosk) deliberately only has INSERT on
`orders`, not SELECT (see "About security" below). So the insert itself
was fine, but the read-back after it was rejected, and Postgres reports
that as the exact same "row-level security policy" error as a missing
INSERT policy, even though INSERT was never the problem. The fix
(already applied): `add()` no longer selects the row back, since
nothing in this app needs it — the ticket number is generated
client-side before `add()` is ever called. If you see this error and
you're confident your policies and grants are right (check with the
query in cause 2 below), check `order/db-supabase.js` for a stray
`.select()` chained onto an `insert()` call anywhere anon touches.

**Cause 2: the INSERT policy or grant is actually missing** — a project
reset, a partial `schema.sql` run that hit an error partway through, or
a table recreated from the Table Editor UI instead of the SQL script.
Fix it by re-running just the access-rules section, safe to run as many
times as you want:

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
