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

**Update (Claude Code, 2026-09-07/08):** the duplication the paragraph
above used to warn about is fixed — cart state, the menu/cart-pane
builders, and their wiring (`resetOrderCtx`, `addLine`, `buildMenuPaneHTML`,
`buildCartPaneHTML`, `renderCart`, `renderOrderLayout`, and the rest)
now live once in `order/ordering-core.js`, loaded by both pages. Only
each page's own submit/receipt/queue logic (genuinely different between
a customer placing an order and staff ringing one up) stays separate.
Still always grep both files before considering an ordering-flow change
done — mode-specific behavior can still diverge — but there's no longer
a second copy of the shared pieces to forget about.

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
Settings → Database → Connection string), use `psql` (or the `pg`
Node package) directly and this whole dance goes away. Confirm this
actually works before relying on it, rather than assuming.

**Update (Claude Code, 2026-09-08):** the direct connection string
(`db.<ref>.supabase.co:5432`) is IPv6-only, and this environment's
network stack couldn't route to it at all (`ENETUNREACH`, even though
DNS resolved fine via a different path) — looked like a Supabase
problem at first but wasn't. Supabase's session pooler is the IPv4-
compatible fix: same password, but the host is
`aws-0-<region>.pooler.supabase.com:5432` and the username becomes
`postgres.<project-ref>` instead of plain `postgres` (this project's
region is `us-east-1`). Worth trying the pooler form first if the plain
`db.<ref>.supabase.co` connection ever mysteriously fails to resolve —
it's a fast, easy alternative, not a last resort.

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
  itself doesn't swallow errors (it throws) — but plenty of call sites
  used to catch and discard them anyway, including several genuinely
  critical ones (`updateOrder`, driver approval, clock in/out) fixed
  2026-09-08 after a review caught them. Where a catch block truly is
  intentional (display-only data, not a write), it's commented inline
  saying why. Don't assume "no error thrown" means "worked as intended"
  without checking which kind you're looking at.

## Current state / what's next

Read `ROADMAP.md` top to bottom — it's the real project history, kept
current on purpose, most recent entries first. This file (`HANDOFF.md`)
is orientation, not a live status tracker — if the two ever disagree,
`ROADMAP.md` is right.

**As of 2026-09-08:** the original claude.ai handoff's feature backlog
is done (Tier 1/2/3, checked off in `ROADMAP.md`'s "Feature backlog"
section), the 2026-09-07 "Next Development Roadmap" (5 priorities from
the owner) is done, the cart-state/pizza-builder duplication this file
used to warn about is fixed, and a review-findings pass fixed a real
set of production-security issues — most notably, customer orders
could previously be inserted directly with client-supplied (i.e.
attacker-controlled) prices; that's now structurally impossible (see
"Part 1 fixes shipped..." in `ROADMAP.md`, 2026-09-08). Two new phases
from that same review (Phase 4: operational health monitoring, Phase 8:
growth features — loyalty, scheduled orders, catering, real payments)
are written up but **deliberately not started**, awaiting the owner's
go-ahead on scope. Check `ROADMAP.md`'s top section for whether that's
moved since this was written.

## One ask

Keep `ROADMAP.md` current the way this session did — it's what let a
brand-new context pick up this project cold and actually understand
what happened and why, not just what the code currently looks like.
Whatever you build, leave the same kind of trail for whoever (or
whatever) picks this up next.
