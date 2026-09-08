# Roadmap

Where the project stands, and what's left. Last reviewed 2026-09-08.

**This is a real business's live ordering system, not a sandbox.** Real
customers can place real orders against it right now. Treat every change
accordingly — see "Development notes" below before writing anything that
touches the live database.

For the detailed history of *how* each feature was built — what broke,
what was tried, what got fixed — read `git log`. Commit messages in this
repo consistently explain the reasoning, not just the change, so that
history is not repeated here; this file only tracks where things stand
today and what's still open.

## Current status

**Fully working:** the Customer Kiosk (`/order/`) — browse, build pizzas,
pickup/delivery, tip, live delivery distance/ETA, optional accounts with
order history/reorder/favorites, scheduled orders, printable receipts,
driver ratings, and a public order-status page (`order/status.html`,
linked from the confirmation screen — ticket + phone, same access model
as the driver-rating page, polls every 20s while an order is still in
progress). The Staff Hub (`/staff/`) — POS, Kitchen Board (now also
showing which driver is en route on an out-for-delivery ticket), Driver
App, Analytics, Driver Roster, Menu Editor, Store Settings (hours,
pause-ordering, receipt message), Catering Inquiries, and an admin-only
System Health screen. A Supabase Postgres backend with row-level security
separating anonymous customers, signed-in customers, drivers, staff, and
admins, and server-authoritative pricing (`create_order()` recomputes
every dollar from `menu_config` — a client can never dictate what an
order costs). Cloudflare Web Analytics is live on the public pages.

**Scaffolded, not finished** — each blocked on an account or hardware
decision from the owner, not on more code. See `OWNER-TODO.md` for the
short, prioritized version of every open decision below:

1. [Real card payments](#1-real-card-payments)
2. [SMS order notifications](#2-sms-order-notifications)
3. [Receipt printing](#3-receipt-printing)
4. [SEO](#4-seo--deferred-until-the-custom-domain-is-live) / [4b. Custom domain migration](#4b-custom-domain-migration-spairkiegithubio--cifellicom)
6. [POS/kitchen screens (hardware)](#6-poskitchen-screens-hardware)

## Backlog

Not blocked on the owner — just not built yet, roughly in priority order:

- [ ] **Separate staging environment/database** — every test so far has
  run directly against the live Supabase project (with cleanup after
  each pass). Worth doing before any feature work substantial enough to
  want a safer place to build and test it.
- [ ] **Full production QA / regression suite** — testing has been
  manual (Playwright + real accounts) each session rather than a
  standing suite. Worth formalizing once there's a staging environment
  to run it against.
- [ ] **Conversion/funnel analytics** — where kiosk sessions drop off
  before completing checkout. Different instrumentation than Analytics'
  existing post-order reporting; scope deliberately rather than bolting
  on ad hoc.
- [ ] **Micro-interactions / hover states** — polish pass across buttons,
  cards, transitions. Ongoing/incremental rather than a single task.
- [ ] **External numeric keypad shortcuts** — the owner's keypad (a V7/
  SEVEN KP400, confirmed 2026-09-08) is a plain USB HID keyboard, so
  typing on it already works today with zero code, on any POS number
  field. The only remaining question is whether dedicated shortcuts are
  wanted — e.g. auto-focus + Enter-to-submit on POS's cash-tendered
  field, so a closer can type a total and hit Enter without touching the
  mouse. Genuinely useful for a register that uses this keypad daily;
  small to build once wanted.
- [ ] **A System Health "went down" alert tone**, added 2026-09-08 — of
  everywhere a new UI sound was considered (POS submit, driver
  claim/complete, bug report sent), this is the one actually worth
  building: it's the one screen where *missing* the alert has a real
  cost (nobody notices payments/print-bridge/etc. went down until a
  customer complains), the others are just nice-to-have confirmation
  blips a visible toast already covers. Same zero-licensing approach as
  the existing kitchen chime: a synthesized Web Audio tone, not a
  sourced file — no "audio library" needed at all.

---

## 1. Real card payments

**Status:** server-side scaffold built (`supabase/functions/
create-payment-intent/`, `supabase/functions/stripe-webhook/`,
`order/payments.js`'s client glue — `paymentsConfigured()`,
`payForOrderNow()`, already loaded on the kiosk page), completely inert
until a real key is set. No live processor, no "Pay Now" UI yet — the
charge amount always comes from the order already in the database, never
a client-supplied value, and only the signature-verified Stripe webhook
(never the browser) ever marks an order paid. "Card" today just tells
whoever's ringing it up to bring the reader over.

**Decision needed from the owner:** whether delivery orders should
require payment upfront or keep today's pay-on-arrival model, and which
in-person card reader to pair with it (see below) — the processor itself
is effectively already decided, since Stripe is what's built. See
`OWNER-TODO.md` for the full processor/hardware comparison and cost
numbers researched 2026-09-08.

**Processor: stay with Stripe** — it's the one already scaffolded in
this code (`order/payments.js`, both Edge Functions); switching to
Square or Clover would mean discarding that and rebuilding on a
different SDK for no real benefit at this shop's size. Stripe's online
rate is 2.9% + 30c (what `OWNER-TODO.md` used to cite); in-person, via a
Stripe Terminal reader or Tap to Pay, it's cheaper — 2.7% + 5c — and
that's the rate that actually applies to counter/in-person card
payments.

**In-person reader options, if physical hardware is wanted at the
register** (no monthly fee, pay-per-transaction only): Stripe Reader M2
($59, Bluetooth to an existing phone/tablet, no screen), BBPOS WisePad 3
($59, adds a PIN pad), BBPOS WisePOS E ($249, standalone touchscreen
terminal), Stripe Reader S700 ($349, top of the line). Tap to Pay on a
staff iPhone/Android needs no reader purchase at all. None of this is
required for the app to work today — cash/card-in-person already works
without any of it, this is only for accepting a tap/chip payment
*through Stripe* instead of the counter's existing card machine.

**What's needed once the owner decides on upfront-vs-pay-on-arrival:**
the "HOW TO FINISH THIS" steps at the top of `order/payments.js` and
both Edge Function files (in order — they reference each other).
Building the actual "Pay Now" button on the kiosk is the remaining code
work, and needs real Stripe keys to test against.

## 2. SMS order notifications

**Status:** scaffold only (`supabase/functions/send-order-sms/`).
Customers can already opt in (checkbox on the order form, `phoneOptIn`
column) but nothing sends a text.

**What it needs:** a Twilio account (buy a phone number, get an Account
SID/Auth Token) and deploying the Edge Function that's already written,
following the steps at the top of that file. No free tier for production
sending — budget roughly $1/month for the number plus ~$0.0079/text.

**Nice side effect once this exists:** the delivery-rating link
(`order/rate.html`) can go out by text instead of only showing on the
confirmation screen.

## 3. Receipt printing + cash drawer

**Status: built, ready for hardware (2026-09-09).** `print-bridge/` is a
standalone Node.js service — ESC/POS receipt formatting, sending to a
**network** printer, and a cash-drawer kick pulse (`escpos.js`,
`buildDrawerKick()`) all work today. It reports a heartbeat to System
Health (`service_heartbeats`), so the Staff Hub shows it as Healthy/
Down rather than a guess. The Staff Hub side is wired up too: a "Print"
button on every POS order (`renderQueueRow` → `requestPrint()`,
`staff/index.html`), an "Open Drawer (No Sale)" button in Till, and a
"Reprint an Order" ticket-number lookup on the POS Queue screen
(`reprintLookup()`) that works for any order at all, not just what's
still active — a completed order from last week reprints exactly the
same way as one still in the live queue.

**Architecture changed from the original design, and why:** the Staff
Hub used to be meant to push a print job to the bridge directly over a
WebSocket. That can't actually work — the Staff Hub is served over
https (GitHub Pages), and every modern browser blocks a plain `ws://`
connection from an https page as mixed content, full stop, including to
localhost. Rather than solve that with a TLS certificate on a local-
network device (real option, more to maintain than this needs), the
Staff Hub now queues a job as an ordinary row in a new `print_jobs`
table (plain https, no different from placing an order), and
`print-bridge` polls Supabase for pending jobs every few seconds
(`POLL_INTERVAL_MS`, default 4s) and prints them. See the "WHY POLLING"
comment at the top of `print-bridge/index.js` and the "Print Bridge"
section of `supabase/schema.sql` for the full reasoning. **Never revert
this to a direct WebSocket push** without solving the mixed-content
problem first — it's not a bug, it's a hard browser security boundary.

**Security:** `print_jobs` grants staff INSERT/SELECT only — nothing
ever lets a browser session mark a job printed. The bridge authenticates
separately via a shared secret (`bridge_secrets`, stored only as a
bcrypt hash, set once via `select set_print_bridge_token('...')` in the
SQL Editor as an admin) required by both `claim_pending_print_jobs()`
and `complete_print_job()` — the public anon key alone isn't enough to
call either successfully. A job's `payload` (which carries the
customer's name/address/items, needed to actually print the receipt) is
nulled out the moment the job completes, so that data doesn't sit around
longer than it has to.

**Hardware recommendation changed too:** steered away from the Star
Micronics TSP143IIIU (USB-only — the harder, unbuilt transport) toward
the **Epson TM-m30III** (Ethernet, ~$275) — purpose-built for tablet/
cloud-POS setups like this one, and it has a cash-drawer kick port,
which the TSP143IIIU research hadn't even considered since nothing
addressed the drawer question yet. Full purchase links and a compatible
drawer: `OWNER-TODO.md` → "2. Receipt printer + cash drawer."

**What's left:** buy the printer + drawer + a mini PC/Pi to run the
bridge (`OWNER-TODO.md` has links), run the one-time
`set_print_bridge_token()` step, fill in `print-bridge/.env`, `npm
start`. No more code to write for the LAN path. USB support
(`print-bridge/transport.js`) stays a stub, not needed for the
recommended hardware.

## 4. SEO — deferred until the custom domain is live

**Status:** intentionally paused, so ownership verification and sitemap
submission aren't done twice once the domain (below) moves.

**Done already, independent of domain:** title/description tags, Open
Graph + Twitter cards, Restaurant JSON-LD structured data, `robots.txt`,
`sitemap.xml`, `/staff/` excluded from indexing.

**Once the domain migration is complete:**
1. Google Search Console — add property, verify, submit `sitemap.xml`.
2. Bing Webmaster Tools — "Import from Google Search Console."
3. Google Business Profile — claim/create the listing; this one isn't
   blocked on the domain and can start in parallel (verification is slow
   and mail-based).

## 4b. Custom domain migration (spairkie.github.io → cifelli.com)

**Status:** not started — owner has the domain but hasn't asked for the
migration yet.

**GitHub Pages side:**
1. Add a `CNAME` file to the repo root containing just `cifelli.com`.
2. Repo Settings → Pages: set the custom domain, enable "Enforce HTTPS"
   (only provisions correctly once DNS below is pointed right; can take
   minutes to hours the first time).

**DNS side (owner's registrar):**
3. Point `cifelli.com` at GitHub Pages: an `A` record set to GitHub's
   Pages IPs, or a `CNAME` for a `www` subdomain — check
   docs.github.com → "Managing a custom domain" for current values.

**Code changes, once DNS is confirmed working** (all currently hardcoded
to `https://spairkie.github.io/cifellis-pizza-website/`):
4. `index.html`: canonical link, `og:url`, `og:image`, `twitter:image`,
   and the Restaurant JSON-LD block's `image`/`url`/`menu` fields.
5. `robots.txt`'s `Sitemap:` line.
6. `sitemap.xml`'s two `<loc>` entries.
7. Spot-check `order/index.html`/`staff/index.html` for absolute URLs
   (icon/manifest links are already relative and shouldn't need changes).
8. The PWA manifests' `start_url` values, if any are absolute.
9. `404.html`'s four link `href`s are root-relative
   (`/cifellis-pizza-website/...`) — update to just `/...`.

## 5. Site analytics

**Status: done.** Cloudflare Web Analytics is live on `index.html` and
`order/index.html` — free, cookieless, no consent banner needed, just
traffic counts (no funnels/revenue tracking). A commented-out GA4 snippet
sits alongside it if funnel-level detail (e.g. "what fraction of menu
visitors complete checkout") is ever worth the added complexity — an
addition on top of Cloudflare, not a replacement.

## 6. POS/kitchen screens (hardware)

**Status:** research only, written up 2026-09-08. This project's Staff
Hub is already a browser-based PWA — POS, Kitchen Board, and Driver App
all just need *a device with a modern browser*, not proprietary POS
terminal hardware. See `OWNER-TODO.md` for the actual hardware/cost
comparison (a budget Android tablet vs. a bundled commercial POS
system) — the short version is a bundled system would mean paying for,
and partially rebuilding onto, hardware and software this project
doesn't need.

## 7. Smaller polish items

- **Driver preferences** are free-text notes today, not structured data.
  Worth breaking out (max delivery radius, preferred shift times) if the
  notes field starts feeling limiting, not before.
- **Menu photos** — category banners in `images/menu/` are still
  placeholder illustrations for stromboli, calzone, wings, hoagie,
  burger, pasta, and salad; dropping in a same-named real photo replaces
  the placeholder automatically, no code change. See `OWNER-TODO.md`.
- **Hero video/art** — `videos/hero-pizza.mp4` is a low-resolution phone
  clip; a proper follow-up shoot would sharpen the homepage noticeably.

---

## Development notes

Things this project's testing has learned the hard way — read before
making a change that touches the live database:

- **Test the actual user-facing behavior, not just that a write
  succeeded.** A Menu Editor save once persisted correctly and displayed
  correctly in the editor itself, so it looked verified — but the
  customer kiosk's *load* path had a bug that meant it silently never
  picked up live changes. Always close the loop end-to-end, not just at
  the database.
- **Writing test orders/signups against the live database pollutes real
  staff-facing screens** (a test order shows up on the real Kitchen
  Board). Prefer mocked network responses (Playwright's `page.route()`)
  when the real backend isn't strictly needed; when it is, clean up
  immediately after (delete the test row) and say so.
- **GitHub Pages has deploy lag** (usually under a minute, but not
  instant) — poll for the actual pushed content before concluding a live
  check failed.
- **A quiet failure is still a failure.** The Supabase adapter
  (`order/db-supabase.js`) itself throws on error, but call sites can
  still catch-and-discard. Where a catch block is genuinely intentional
  (display-only data, not a write), it's commented inline saying why —
  don't assume "no error thrown" means "worked as intended" without
  checking which kind of catch you're looking at.
- **The hero video (`videos/hero-pizza.mp4`) may not autoplay in a
  headless-Chromium test sandbox** — that Chromium build lacks a licensed
  H.264 decoder that real Chrome/Safari/Edge/Firefox all ship. Confirmed
  this is a sandbox artifact, not a real bug; don't "fix" it without
  re-confirming it's actually broken somewhere a real browser would show.

**Database:** `supabase/schema.sql` is the single source of truth — every
statement is written to be safely re-runnable (`if not exists`,
drop-then-recreate policies, `on conflict do nothing` for the seed).
There should never be a second migration file sitting next to it — fold
any schema change into `schema.sql` directly. Catching the live project
up on a change is always: copy the whole file, paste into the Supabase
SQL Editor, Run. See `supabase/README.md` for full setup.

If you have (or can get) a direct Postgres connection string (Supabase
dashboard → Project Settings → Database → Connection string), `psql` or
the `pg` Node package can apply `schema.sql` directly instead of the
dashboard dance — confirm it actually works in your environment before
relying on it. The **direct** connection (`db.<ref>.supabase.co:5432`) is
IPv6-only and may not route from some environments (`ENETUNREACH` even
when DNS resolves). Supabase's **session pooler** is the IPv4-compatible
fix: same password, host `aws-0-<region>.pooler.supabase.com:5432`,
username `postgres.<project-ref>` instead of plain `postgres` (this
project's region is `us-east-1`). Worth trying the pooler form first if
the direct connection ever mysteriously fails to resolve.

**Architecture:** `order/db-supabase.js` is a small Firestore-shaped
adapter over Supabase — everything in the app talks to the database
through it, not the Supabase client directly. Its `.doc(id)` pattern
assumes a table's primary key column is literally named `id` (same
precedent as `promo_codes`'s surrogate key); a table whose natural key is
something else (e.g. `customerId`) needs `.where()` instead, or it'll hit
a "column does not exist" error — this has bitten more than one new table
already, worth checking before adding another. Cart state, the menu/cart
pane builders, and their wiring live once in `order/ordering-core.js`,
loaded by both `order/index.html` and `staff/index.html` — grep both
pages before considering an ordering-flow change done, since each page's
own submit/receipt/queue logic is genuinely separate.

## Test accounts (development/testing mode)

Three Supabase Auth accounts exist for continued AI-assisted testing —
all `@cifellispizza.local`, password `claudeTestPw2026` (consider
rotating this once you have `service_role` access; it's appeared in chat
transcripts):

- `claude-test@cifellispizza.local` — admin + driver, sees everything
- `claude-test-staff@cifellispizza.local` — general staff (POS/Kitchen/
  Analytics)
- `claude-test-driver@cifellispizza.local` — driver-only (Driver App
  only)

They're genuinely useful for continued testing while the project is
still in development/testing mode. **Delete all three (rows + Auth
users, in Staff/Drivers tables and Authentication → Users) before this
site takes real production traffic without supervision.**

**Getting access, if you're picking this up fresh:**
1. A way to push to the repo — SSH key or `gh auth login`.
2. A fresh Supabase `service_role` key if you need to bypass RLS for
   test-data setup/cleanup (env var only, never commit it — `.env` is
   already gitignored).
3. A Postgres connection string, if you want direct DDL access (see
   "Database" above).
