# Disaster Recovery

What to do if the database, the website, or Supabase itself goes down —
written for whoever's running this project, not customers. Nothing in
here is customer-facing; if you're looking for the public privacy/
ordering policy, that's `policies.html`.

**No credentials live in this file, on purpose.** Where a step needs a
password, key, or connection string, this says *where to find it*
(the Supabase dashboard, or wherever the site owner keeps them), never
what it is.

## The short version, if you're mid-shift and something's broken

1. **Keep taking orders by phone and in person.** Nothing about a
   Supabase/website outage stops the shop from operating — pen, paper,
   and the phone still work. This is the actual fallback, not a
   theoretical one: this project has run on phone/walk-in orders since
   long before online ordering existed.
2. **Keep a printed, current menu with prices behind the counter.**
   Menu Editor (Staff Hub) is the live source of truth for prices — if
   it's down, you need a paper copy that isn't. See "Printed menu
   backup" below for how to keep one current without extra work.
3. **Orders already in the kitchen queue don't disappear from the
   kitchen** — they're already tickets in hand or on the board. An
   outage stops *new* orders and *status updates* through the app, not
   food that's already being made. Finish what's in progress the normal
   way; write down anything you'd normally track digitally (who's
   getting what, driver assignments) until the system's back.
4. **If online ordering itself is broken but the rest of the site
   works:** Staff Hub &gt; Store Settings has a Pause Online Ordering
   toggle — use it so customers see a clear "call to order" message
   instead of a broken checkout.

## Diagnosing what's actually down

- **Supabase outage or your project paused:** check
  [status.supabase.com](https://status.supabase.com) first. A free-tier
  Supabase project also auto-pauses after a period of no activity — if
  the site suddenly can't reach the database, check the project's own
  dashboard for a "paused" banner before assuming something's actually
  broken; un-pausing is one click there.
- **GitHub Pages outage:** check
  [githubstatus.com](https://www.githubstatus.com). This affects the
  website itself being reachable at all, separate from Supabase.
- **Just one feature acting up:** check the browser console (F12) for
  errors first — this project logs real problems there rather than
  failing silently in most places.

## Backing up the database

Supabase's own dashboard (Database → Backups) keeps automatic daily
backups on paid plans; free-tier projects don't get this, so treat the
steps below as the actual backup plan, not a supplement to one Supabase
already handles for you — check your plan to know which case you're in.

**Manual export (works on any plan), from a machine with `pg_dump`
installed:**
1. Get the project's connection string: Supabase dashboard → Project
   Settings → Database → Connection string (the direct connection, not
   the pooler, for a one-off dump).
2. Run:
   ```
   pg_dump "<connection string>" --no-owner --no-privileges -f backup-YYYY-MM-DD.sql
   ```
3. Store that file somewhere other than this repo — it will contain
   real customer names, phone numbers, and addresses, which have no
   business being committed to git history even in a private repo.
   A password manager's secure file storage, or an encrypted drive, are
   both fine; a plain cloud-drive folder without encryption is not.

**How often:** for a shop this size, weekly is reasonable, with an
extra manual export before any schema change (before pasting an updated
`schema.sql` into the SQL Editor) in case something about the change
needs to be rolled back.

## Restoring from a backup

1. If the whole project is gone (not just paused) — create a fresh
   Supabase project, then run the *current* `supabase/schema.sql`
   against it first (SQL Editor → paste the whole file → Run) so every
   table/policy/function exists before restoring data into them.
2. Restore the data itself from a `pg_dump` file with `psql`:
   ```
   psql "<new project's connection string>" -f backup-YYYY-MM-DD.sql
   ```
   Expect some noise from `schema.sql` already having created
   everything — a `pg_dump` restore mainly matters here for the actual
   *rows* (orders, staff, drivers, menu_config's data), not the schema
   itself, since `schema.sql` is already the authoritative, safely
   re-runnable source for structure.
3. Update `order/supabase-config.js` with the new project's URL and
   anon key (see that file's own header comment), commit, push.
4. Rotate every credential that existed on the old project (it's being
   retired, but don't leave old keys valid indefinitely) — Supabase
   dashboard → Project Settings → API, and every staff/driver password
   if there's any reason to suspect exposure.

## Printed menu backup

The live menu (Staff Hub → Menu Editor) can change independently of
this printed backup, so the backup only stays useful if it's actually
refreshed:
- After any Menu Editor save that changes a price or removes an item,
  print (or re-write) the affected section.
- Keep the printed copy behind the counter, not just in a drawer
  somewhere — it needs to be reachable *during* an outage, not filed
  away.
- A dated copy ("as of [date]") is more useful than an undated one, so
  whoever's using it during an outage knows how stale it might be.

## Handling active orders during an outage

- **Orders already placed before the outage:** already visible on
  Kitchen Board/POS if those loaded before the outage started (they
  cache the last-seen state client-side); if a screen needs a hard
  reload during the outage, that cached view is lost — write down
  what's in progress before reloading anything once you know
  something's wrong.
- **New orders during the outage:** can't come in through the website
  at all if Supabase itself is down (nothing works without the
  database — this isn't a "some features degrade" situation). Take
  phone/walk-in orders on paper as usual until service is back, then
  there's no reconciliation needed — they were never meant to be in the
  system stealth-added after the fact, just business as normal, on
  paper.

## What this document is not

It's not a substitute for actually testing a restore once, before you
need it for real — a backup you've never tried restoring is a backup
you don't actually know works.
