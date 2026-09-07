# Roadmap

Where the project stands, and what's left. Last reviewed 2026-09-06.

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

## 4. SEO

**Status:** mostly done.
- Done: title/description tags, Open Graph + Twitter cards, Restaurant
  JSON-LD structured data, `robots.txt`, `sitemap.xml`, `/staff/` excluded
  from indexing.
- Remaining: submit the sitemap to
  Google Search Console (search.google.com/search-console) and
  Bing Webmaster Tools (bing.com/webmasters) (five minutes
  each, just needs you to verify domain ownership) — this is what actually
  gets the site crawled and into local search results, the on-page work
  alone doesn't do that. Also worth claiming/checking your
  Google Business Profile (business.google.com) listing, since for
  a local pizza shop that drives far more traffic than organic search
  ranking does.

**Effort:** under an hour of clicking through Google's own setup flows —
not really a coding task.

---

## 5. Site analytics — what to actually use

You asked specifically what's out there. Compared current options:

| Tool | Cost | Setup | Trade-off |
|---|---|---|---|
| **Cloudflare Web Analytics** | Free, forever | One script tag, no account migration needed | Just traffic counts, no funnels or revenue tracking, but zero cost and genuinely private (no cookies, doesn't need a consent banner) |
| **Google Analytics 4 (GA4)** | Free, unlimited traffic | One script tag (already stubbed in `index.html`, commented out) | Most powerful free option, but complex dashboard, and Google uses the data for ad products, a real consideration if privacy matters to you or your customers |
| **Umami** (self-hosted) or **Plausible** | Free if self-hosted, ~$9+/mo hosted | More setup (self-hosted needs a server) | Nice middle ground, simple, private, actual dashboard, but not worth the effort at this site's current traffic |

**My recommendation:** start with **Cloudflare Web Analytics**. It's free
with no catch, doesn't need a Cloudflare account change to your DNS, adds
one script tag, and tells you what you actually want to know at this
stage — how many people visit, what pages they look at, where they came
from — without any privacy trade-off or ongoing cost. Sign up at
cloudflare.com/web-analytics, copy the snippet into `index.html` and
`order/index.html`. If you later want conversion funnels tied to actual
orders (e.g. "what fraction of menu visitors complete checkout"), that's
when GA4 or a paid tool like Plausible starts earning its keep, not before.

The GA4 snippet already sitting commented-out in `index.html` is fine to
use instead if you'd rather have the more powerful (and more complex)
option from the start.

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
