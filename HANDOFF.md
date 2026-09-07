# Handoff to Claude Code

Written 2026-09-07 by Claude in claude.ai, handing this project off to
Claude Code for continued development. Read this first, then
`ROADMAP.md` for full history and the feature backlog — this file is
just the "get oriented and don't repeat known mistakes" briefing.

## What this is

Cifelli's Pizza (Lindenwold, NJ) — a real, live website with online
ordering, a Staff Hub (POS / Kitchen Board / Driver App / Analytics /
Driver Roster / Menu Editor), and a Supabase backend. Plain HTML/CSS/JS,
no build step, no framework. Deployed via GitHub Pages, redeploys
automatically on push to `main` (usually live within ~30-90 seconds).

Repo: https://github.com/Spairkie/cifellis-pizza-website
Live site: https://spairkie.github.io/cifellis-pizza-website/
Supabase project ref: `yzehosyrsygvbddskpqs`

**This is a real business's live ordering system, not a sandbox.**
Real customers can place real orders against it right now. Treat every
change accordingly — see "Testing conventions" below before writing
anything that touches the live database.

## Structure, in brief

- `index.html` — public marketing homepage.
- `order/index.html` — the customer-facing ordering kiosk (no login).
- `staff/index.html` — the Staff Hub (login required). Single file,
  ~2500 lines, all six role screens live here.
- `staff/apply.html` — public driver self-application form.
- `order/db-supabase.js` — a small Firestore-shaped adapter over
  Supabase. Everything in the app talks to the database through this,
  not the Supabase client directly.
- `order/supabase-config.js` — the project URL + anon key (public by
  design, safe to be in the repo — RLS is what actually protects data).
- `supabase/schema.sql` — the **entire** database: every table, every
  RLS policy, every function, and the menu seed data, in one file. See
  "Database" below.
- `supabase/README.md` — setup instructions, written for whoever's
  running this project (not just for an AI session).

**Important:** `order/index.html` and `staff/index.html` duplicate a
fair amount of logic (menu rendering, item cards, the pizza builder,
cart line editing). This is a known, deliberate tradeoff from before
the customer/staff split, not an oversight — but it means **a menu- or
ordering-related change usually needs to be made in both files**, and
it's easy to fix a bug in one and forget the other exists. Always grep
for the function/pattern name in both files before considering an
ordering-flow change done.

## Database

`supabase/schema.sql` is the single source of truth — every statement
in it is written to be safely re-runnable (`if not exists`,
drop-then-recreate policies, `on conflict do nothing` for the seed), so
catching the live project up on a schema change is always: copy the
whole file, paste into the Supabase SQL Editor, Run. There should never
be a second migration file sitting next to it — if you're about to
create one, fold the change into `schema.sql` instead and note in
`ROADMAP.md` that it needs to be re-run.

This matters because **I (the claude.ai session) never had a working
direct Postgres connection** — that sandbox only allowed outbound
HTTPS, so every schema change this session had to be done by asking
the site owner to paste SQL into the dashboard by hand. **You very
likely don't have this limitation** running locally — if you have (or
can get) a Postgres connection string (Supabase dashboard → Project
Settings → Database → Connection string), use `psql` directly and this
whole dance goes away. Confirm this actually works before relying on
it, rather than assuming.

## Credentials

None of mine carry over — they were scoped to that session and should
be treated as already gone:
- The GitHub PAT I was using is expected to be revoked/rotated by now.
- The Supabase `service_role` key I was using should also be rotated
  before you start (Supabase dashboard → Project Settings → API).

**Get from the site owner before starting:**
1. A way to push to the repo — SSH key or `gh auth login` is a much
   better fit for a persistent CLI tool than the one-off PAT-pasted-
   into-chat pattern this session was stuck with.
2. A **fresh** Supabase `service_role` key if you need to bypass RLS
   for test-data setup/cleanup (store as an env var, never commit it —
   `.env` is already gitignored).
3. A Postgres connection string, if you want real DDL access (see
   above).

**Existing test accounts** (all `@cifellispizza.local`, password
`claudeTestPw2026` — consider rotating these passwords once you have
service_role access, they were set in a chat transcript):
- `claude-test@cifellispizza.local` — admin + driver, sees everything
- `claude-test-staff@cifellispizza.local` — general staff (POS/
  Kitchen/Analytics)
- `claude-test-driver@cifellispizza.local` — driver-only (Driver App
  only)

All three are flagged in `ROADMAP.md` to be deleted before real
production use. They're genuinely useful for continued testing in the
meantime — just don't forget they're there.

## Testing conventions this session learned the hard way

- **Test the actual user-facing behavior, not just that a write
  succeeded.** The biggest miss this session made: a Menu Editor save
  correctly persisted to the database, and the Menu Editor's own
  display correctly showed it — so it looked verified — but the
  customer kiosk's *load* path had a bug that meant it silently never
  picked up live changes at all. Wasn't caught until something checked
  what the kiosk actually rendered, not just what the database
  contained. Always close the loop end-to-end.
- **Writing test orders/signups against the live database pollutes
  real staff-facing screens.** A test order shows up on the real
  Kitchen Board. Prefer mocked network responses (Playwright's
  `page.route()`) for anything that doesn't strictly need the real
  backend; when the real backend is genuinely necessary, clean up
  immediately after (delete the test order/row) and say so.
- **GitHub Pages has deploy lag** (usually well under a minute, but
  don't assume instant) — poll for the actual pushed content to appear
  before concluding a live check failed.
- **A quiet failure is still a failure.** `db-supabase.js`'s adapter
  swallows some errors by design (documented inline where it does) —
  don't assume "no error thrown" means "worked as intended."

## Current state / what's next

Read `ROADMAP.md` top to bottom — it's the real project history, kept
current on purpose, most recent entries first. In short: a full code
review pass, several real bugs found and fixed (an RLS infinite-
recursion bug that broke every staff-admin check, a menu-config
loading bug that meant live menu edits never reached the kiosk, a
broken customer/driver signup flow, a mobile ordering bug), a Menu
Editor was built, least-privilege role-based screen access was added,
and a large feature backlog was captured but mostly not yet built.

**The feature backlog (prioritized, with reasoning) is the "what's
next" — see the "Feature backlog" section of `ROADMAP.md`.** Tier 1 is
where to start: pause/throttle online orders and a Store Settings
screen are the next-highest-value items after the Sold Out toggle that
already shipped.

## One ask

Keep `ROADMAP.md` current the way this session did — it's what let a
brand-new context pick up this project cold and actually understand
what happened and why, not just what the code currently looks like.
Whatever you build, leave the same kind of trail for whoever (or
whatever) picks this up next.
