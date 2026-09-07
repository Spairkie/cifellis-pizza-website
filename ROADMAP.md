# Roadmap

Where the project stands, and what's left. Last reviewed 2026-09-06.

## Start here if you're a new chat picking this up

This file is the source of truth for where the project stands — read
the whole thing before making changes. A few things worth knowing
about how this project has been built so far:

- It's grown through many incremental sessions, each adding a
  feature and pushing straight to `main` (no staging environment,
  no automated test suite). Every change so far was manually tested
  in a sandboxed browser (Playwright) before pushing, checking for
  console errors and visually confirming the UI — but never against
  the real, live Supabase backend, since that's not reachable from
  the sandbox. **The owner has been testing against the real backend
  themselves and has not yet reported specific bugs as of this
  writing** — so there may be real-world issues (RLS edge cases,
  flows that work in isolation but break combined) that haven't
  surfaced yet.
- The owner asked, at the point this section was added, for a full
  review pass: read through the whole codebase fresh, test every
  user flow end to end, fix whatever's actually broken, and update
  this file to reflect what you find — don't assume the "what's
  fully working" list below is still accurate, verify it.
- Read `supabase/README.md` in full before touching anything
  database-related — the RLS model (staff/admin/customer/driver
  separation) is deliberate and has already had one real security
  fix applied (see git log for "staff-allowlist"); don't loosen it
  without understanding why it's shaped the way it is.
- Check `git log --oneline` for the full history of what's been
  built and why — commit messages here have consistently explained
  the reasoning, not just the change.

## What's fully working today

- **Customer Kiosk** (`/order/`): browse menu, build pizzas, order pickup or
  delivery, tip, live delivery distance/ETA, optional account (order
  history, reorder, saved preferences), printable receipt, rate a
  delivered driver.
- **Staff Hub** (`/staff/`): live POS with editing and a proper cancel-
  confirmation flow, Kitchen Board, Analytics (today's numbers, top
  sellers, regulars), Driver Roster with self-apply + admin approval.
- **Driver App**: real per-driver login, claim/complete deliveries, clock
  in/out, stats (deliveries, miles, tips, rating), delivery history.
- **Database**: Supabase Postgres with row-level security separating
  anonymous customers, signed-in customers, drivers, staff, and admins.
  See `supabase/schema.sql` and `supabase/README.md`.
- **Site analytics**: Cloudflare Web Analytics is live on `index.html`
  and `order/index.html`.

Everything below is either a stub waiting on a decision/account from you, or
a smaller polish item.

---

## 1. Real card payments

**Status:** scaffold only (`order/payments.js`). "Card" today just tells
whoever's ringing it up to bring the reader over — no money moves through
the site.

**What it needs:** a Stripe account (or similar) and a small server-side
piece — Stripe's secret key can never live in the frontend, so this means
one Supabase Edge Function that creates a PaymentIntent, plus a few lines
of Stripe.js in the checkout flow. `order/payments.js` has the exact steps
already written out.

**Decision needed from you:** which processor (Stripe is the standard
choice for a business this size — flat ~2.9% + 30c, no monthly fee), and
whether you want to require payment upfront for delivery orders or keep
today's pay-on-arrival model for cash/in-person card.

**Effort once you have a Stripe account:** a focused session — this is the
best-scoped remaining item.

---

## 2. SMS order notifications

**Status:** scaffold only (`supabase/functions/send-order-sms/`). Customers
can already opt in (checkbox on the order form, `phoneOptIn` column) but
nothing sends a text.

**What it needs:** a Twilio account (buy a phone number, get an Account
SID/Auth Token) and deploying the one Edge Function that's already
written, following the steps at the top of that file.

**Decision needed from you:** Twilio has no free tier for production
sending (trial credit only) — budget roughly $1/month for the number plus
~$0.0079 per text. Worth it once volume justifies it.

**Nice side effect once this exists:** the delivery-rating link
(`order/rate.html`) can go out by text instead of only showing on the
confirmation screen, which is the main way a real driver-rating program
gets used.

---

## 3. Receipt printing

**Status:** partially real. `print-bridge/` is a standalone Node.js
service — the ESC/POS receipt formatting and sending to a **network**
printer actually works today, tested against real formatting logic. What's
missing:
- **USB printer support** — needs your actual printer's vendor/product ID,
  which I can't get without the hardware in hand. Documented in
  `print-bridge/transport.js`.
- **The Staff Hub doesn't call it yet** — no button says "print this."
  The exact function to add is commented at the bottom of
  `print-bridge/index.js`.

**What it needs from you:** a thermal receipt printer (network/Wi-Fi ones
are the easy path — 58mm or 80mm, look for "ESC/POS" in the listing) and a
cheap mini PC or Raspberry Pi to run the bridge near it.

**Effort:** small once you have the printer — mostly wiring the two pieces
that already exist together, plus testing against a real device.

---

## 4. SEO — deferred until the custom domain is live

**Status:** intentionally paused. The owner is planning to move the site
to `https://cifelli.com/` and doesn't want to verify search-engine
ownership or submit a sitemap twice — correct call, since the domain
change below invalidates that work anyway.

**Done already, independent of domain:** title/description tags, Open
Graph + Twitter cards, Restaurant JSON-LD structured data, `robots.txt`,
`sitemap.xml`, `/staff/` excluded from indexing.

**Do this once the domain migration below is complete, not before:**
1. Google Search Console (search.google.com/search-console) — add
   property, verify (HTML tag method works from a GitHub Pages-hosted
   site with no DNS access; a real domain like `cifelli.com` also
   supports the DNS TXT method if the owner prefers it once they
   control DNS), submit `sitemap.xml`.
2. Bing Webmaster Tools (bing.com/webmasters) — use "Import from Google
   Search Console" once step 1 is done, fastest path.
3. Google Business Profile (business.google.com) — claim or create the
   listing, start the (slow, mail-based) verification early since it
   isn't blocked on the domain migration and can run in parallel.

**Effort:** under an hour of clicking through Google/Bing's own setup
flows once the domain is live — not a coding task.

---

## 4b. Custom domain migration (spairkie.github.io → cifelli.com)

**Status:** not started — owner has the domain but hasn't asked for the
migration yet. Flagging the full checklist now so it's not rediscovered
from scratch later.

**GitHub Pages side:**
1. Add a `CNAME` file to the repo root containing just `cifelli.com`
   (this is what tells GitHub Pages which custom domain to serve).
2. In the repo's GitHub Settings > Pages, set the custom domain and
   enable "Enforce HTTPS" (GitHub provisions the certificate
   automatically, but only after DNS below is pointed correctly, and it
   can take a few minutes to a few hours the first time).

**DNS side (owner's domain registrar, not something I can do):**
3. Point `cifelli.com` at GitHub Pages: either an `A` record set to
   GitHub's four Pages IPs (185.199.108.153, .109.153, .110.153,
   .111.153), or a `CNAME` record if using a `www` subdomain — GitHub's
   own docs (docs.github.com → "Managing a custom domain") have the
   exact current values, worth double-checking there since IPs can
   change.

**Code changes, once DNS is confirmed working (all hardcoded URLs to
find-and-replace, currently pointing at
`https://spairkie.github.io/cifellis-pizza-website/`):**
4. `index.html`: `<link rel="canonical">`, `og:url`, `og:image`,
   `twitter:image`, and the two URLs inside the Restaurant JSON-LD
   block (`image` and `url` fields, plus the `menu` field's `#menu`
   anchor).
5. `robots.txt`: the `Sitemap:` line.
6. `sitemap.xml`: both `<loc>` entries (homepage and `/order/`).
7. Spot-check `order/index.html` and `staff/index.html` for any
   absolute URLs referencing the old GitHub Pages path (icons/manifest
   links use relative paths already and shouldn't need changes, but
   verify).
8. Re-check the PWA manifests (`manifest.webmanifest` in the root,
   `order/`, and `staff/`) for any absolute `start_url` values.

**Effort:** small — mostly a careful find-and-replace plus DNS
propagation wait time (can be minutes to 48 hours depending on the
registrar).

---

## 5. Site analytics — what to actually use

**Status: done.** Cloudflare Web Analytics is live on `index.html` and
`order/index.html`. Left the comparison below in place for context on
why Cloudflare was picked over the alternatives, and because it's
useful background if the owner ever wants to add a second tool (e.g.
GA4 for funnels) on top rather than switching.

Compared current options:

| Tool | Cost | Setup | Trade-off |
|---|---|---|---|
| **Cloudflare Web Analytics** (in use) | Free, forever | One script tag, no account migration needed | Just traffic counts, no funnels or revenue tracking, but zero cost and genuinely private (no cookies, doesn't need a consent banner) |
| **Google Analytics 4 (GA4)** | Free, unlimited traffic | One script tag (already stubbed in `index.html`, commented out) | Most powerful free option, but complex dashboard, and Google uses the data for ad products, a real consideration if privacy matters to you or your customers |
| **Umami** (self-hosted) or **Plausible** | Free if self-hosted, ~$9+/mo hosted | More setup (self-hosted needs a server) | Nice middle ground, simple, private, actual dashboard, but not worth the effort at this site's current traffic |

If conversion funnels tied to actual orders (e.g. "what fraction of menu
visitors complete checkout") become worth measuring later, that's when
GA4 or a paid tool like Plausible would earn its keep as an addition —
not a replacement for Cloudflare, which is fine to keep running either
way since it costs nothing.

---

## 6. Smaller polish items

- **Driver preferences** are a free-text notes field today, not structured
  data. Worth breaking out (max delivery radius, preferred shift times,
  etc.) if the notes field starts feeling limiting, not before.
- **Kitchen Board** could use another pass now that driver assignment and
  tips show up elsewhere in the app, e.g. showing which driver is en
  route to a ticket, not just that it's "out for delivery."
- **Menu photos** — the 7 category banners in the order screen are still
  original placeholder illustrations, auto-replaced the moment a same-named
  real photo is dropped into `images/menu/` (see the file for the naming
  convention). No code change needed when you're ready, just the photos.
- **Hero video/art** — `videos/hero-pizza.mp4` is a low-resolution phone
  clip; a proper follow-up shoot would sharpen the homepage noticeably.

---

## How to read this file going forward

Update the "What's fully working" section whenever a scaffold above
actually gets finished, and delete its section here. Everything in
sections 1-4 is blocked on an account or hardware purchase from you, not
on more code — flag when you've got one of those and it becomes the next
build session.
