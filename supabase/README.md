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

There is no login for customers, staff, the kitchen board, or drivers in
this version, everyone reaches the database with the same public anon key,
protected only by the row-level security policies in `schema.sql` (which
allow reading and creating/updating orders, but never deleting them). That
is an accepted trade-off for a single-location shop's internal tools
running on devices you control. If this ever needs real staff accounts
(so only logged-in staff can see the kitchen board, for instance), that is
a Supabase Auth addition worth doing before handling anything more
sensitive than order tickets.

## If you would rather not use Supabase

The app talks to the database only through `order/db-supabase.js`, a small
adapter file. Swapping in a different backend (your own Node server, a
different managed database) means rewriting that one file to the same
four methods it currently exposes (`collection().add()`,
`collection().doc().update()`, `collection().onSnapshot()`, `.orderBy()`),
nothing else in the app needs to change.
