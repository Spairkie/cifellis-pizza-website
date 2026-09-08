# Cifelli's Pizza: website and order system

Website, online ordering, staff POS, kitchen board, and delivery driver app
for Cifelli's Pizza (700 Chews Landing Rd, Lindenwold, NJ 08021).

**Live site:** https://spairkie.github.io/cifellis-pizza-website/

## What's in here

- **`index.html`**: the marketing site (menu, specials, reviews, hours,
  a cinematic video intro, and an "Order Online" link into the app below).
  Public, no login.
- **`order/`**: the Customer Kiosk, a single-purpose ordering app for
  customers (the counter kiosk or a customer's own phone). Public, no
  login, installable as its own PWA.
- **`staff/`**: the Staff Hub — POS, Kitchen Board, Driver App, Analytics,
  Driver Roster, Menu Editor, Store Settings, Catering Inquiries, and an
  admin-only System Health screen, all role-gated and sharing the same
  live order queue as the Customer Kiosk. Requires a Supabase Auth
  sign-in, not linked from the public site, and not indexed by search
  engines. Installable as its own PWA, separate from the Customer Kiosk.
- **`supabase/`**: the database schema and setup instructions for the
  free backend that powers live orders, including the row-level security
  rules that keep the two apps' access separate. See `supabase/README.md`
  to finish setup, it's the one manual step required.

## How this is architected, and why

Real restaurant systems (Toast, Square, and similar) run the kiosk, POS,
kitchen display, and driver tools as separate screens that all read and
write one shared backend in real time, usually over WebSockets, with
Postgres as the database of record. That's the same shape used here: one
`orders` table, one realtime subscription mechanism, four screens.

Where this differs from a big commercial system on purpose: there's no
custom server to run and pay for. [Supabase](https://supabase.com) provides
a free hosted Postgres database with built-in realtime subscriptions, which
covers everything a Node.js + WebSocket server would otherwise be needed
for at this scale. That means:

- **No server to keep running.** GitHub Pages hosts the static site and
  app for free, forever, with no sleep/cold-start behavior to worry about.
  Supabase hosts the database and pushes live updates to every open screen.
- **One free tier that's actually usable long-term**, not a 30-day trial.
  The known catch is a Supabase project pauses after a full week of zero
  activity; a shop taking orders daily won't hit that (see
  `supabase/README.md`).
- **Less to maintain.** No servers to patch, no separate realtime message
  broker (Redis/Socket.io) to run, no deploy pipeline beyond pushing to
  `main`.

The Customer Kiosk (public) and the Staff Hub (signed-in staff only) are
two separate apps for exactly this reason: a customer placing an order
should never be one click away from the kitchen board or a driver's
delivery list. The Customer Kiosk can only create orders (enforced by the
database's row-level security policies, not just by hiding a button);
reading the order queue or changing a status requires a signed-in Supabase
Auth session, which only the Staff Hub asks for. Details in
`supabase/README.md`.

If this ever needs to grow past what Supabase's free tier or built-in
features cover (SMS notifications, a receipt printer bridge, real payment
processing), the natural next step is a small serverless function (a
Supabase Edge Function, or a free Render web service) added alongside,
not a rebuild. See `ROADMAP.md` for the research behind SMS, online
payment, receipt printing, and a future custom domain — each is scaffolded
in the code already but blocked on an account or hardware decision from
the owner, tracked in `OWNER-TODO.md`.

## Getting it running

1. **Finish the database setup**: follow `supabase/README.md` (create a
   free Supabase project, run the schema, paste two values into
   `order/supabase-config.js`, turn on email sign-in and create at least
   one staff account). Takes about ten minutes.
2. **Turn on GitHub Pages**: repo Settings > Pages > Source: "Deploy from a
   branch" > Branch: `main`, folder `/ (root)` > Save. The site will be
   live at `https://spairkie.github.io/cifellis-pizza-website/` within a
   minute or two.
3. **Customers order at `/order/`**, no setup needed on their end, it's
   linked from the main site.
4. **Staff sign in at `/staff/`** on whatever device runs each role (a
   laptop or tablet at the register for POS, a screen in the kitchen,
   phones for drivers). Each device picks its role once after signing in;
   switch anytime with "Switch screen" in the header, and "Sign Out" ends
   that device's session.
5. **Install either as an app** (optional but recommended for kiosk/
   kitchen/driver devices): open the page in Chrome or Edge, tap "Install
   this app on this device", or use the browser's own install/Add to Home
   Screen option. On iPhone, use Safari's Share > Add to Home Screen (iOS
   doesn't support the automatic install prompt).

## What's real, and what isn't (yet)

Real: the menu (matches the shop's actual items and prices), the order
flow (server-authoritative pricing — a customer's device can never dictate
what an order costs), the live shared queue across all four screens,
ticket numbers, and the kitchen board's order-aging warnings. Also real:
customer accounts with order history and reorder, favorites ("My Usual"),
scheduled orders (with real lead-time/business-hours validation), a
catering/large-order inquiry form, a public order-status page (check
"preparing / ready / out for delivery" without calling), an optional
loyalty program (off by default, admin-configurable), and an admin-only
System Health screen in the Staff Hub.

Not built: real payment processing. Card is selectable as a payment method
throughout, but nothing actually charges a card, every order is paid in
person (cash or card at pickup/delivery), matching how the shop operates
today. Adding real card processing later (Stripe, Square, or similar) is a
separate, deliberate step, not something to bolt on quietly.

## What's scaffolded but not finished yet

These exist in the repo as a starting point, not as working features.
Each has a comment at the top of its main file explaining exactly what's
left to do:

- **Tipping** — actually works today. The Customer Kiosk shows a tip
  picker (15%/18%/20%/custom) for delivery orders, added to the total
  and stored on the order.
- **Online card payments** — the server-side scaffold exists
  (`supabase/functions/create-payment-intent/`, `supabase/functions/
  stripe-webhook/`, and `order/payments.js`'s client glue), but there's
  no live Stripe key and no "Pay Now" button yet. Today "Card" just
  tells the counter to bring the card reader over, no money moves
  through the site. See `OWNER-TODO.md`.
- **SMS order notifications** — not wired up.
  `supabase/functions/send-order-sms/` is a Supabase Edge Function stub
  with the Twilio integration steps documented; the Customer Kiosk
  already has a "text me when it's ready" opt-in checkbox that stores
  consent (`phoneOptIn` on the order), nothing sends a text yet.
- **Receipt printing** — partially works. `print-bridge/` is a separate
  Node.js service (run on a mini PC near the printer) that turns an
  order into a real ESC/POS receipt and can send it to a network
  printer today. USB printer support and the Staff Hub's "send this to
  the bridge" call are both stubbed with exact next steps. See
  `print-bridge/README.md`.
- **Analytics & SEO** — `index.html` has Open Graph/Twitter meta tags and
  Restaurant structured data (JSON-LD) for search engines, plus
  `robots.txt` and `sitemap.xml` at the repo root. Cloudflare Web
  Analytics (free, cookieless) is already live on the homepage and
  kiosk; a commented-out Google Analytics 4 snippet sits alongside it
  in `index.html`'s `<head>` if a funnel-capable tool is ever wanted on
  top. Search Console/Bing/Google Business Profile submission is
  intentionally deferred until the custom domain migration — see
  `ROADMAP.md`. `/staff/` is excluded from search indexing and the
  sitemap since it's a private tool, not a public page.

## Research notes (for whoever picks this up later)

A quick summary of what shaped the choices above, useful if this needs to
be revisited:

- Restaurant POS/KDS systems generally push order updates over WebSockets
  so every screen updates instantly rather than polling
  ([Kanopy: building a restaurant POS system](https://kanopylabs.com/blog/how-to-build-a-restaurant-pos-system)).
  Supabase's realtime subscriptions serve the same purpose here without a
  custom WebSocket server.
- Free hosting for a persistent Node.js server + Postgres is limited:
  Render's free web services spin down after 15 minutes idle and its free
  Postgres expires after 30 days; Railway's free credit isn't enough for
  continuous uptime
  ([Render: platforms with a real free tier in 2026](https://render.com/articles/platforms-with-a-real-free-tier-for-developers-in-2026)).
  Supabase and Neon were the two free Postgres options without a hard
  expiration
  ([free Postgres hosting compared](https://perkstack.co/blog/free-postgres-hosting)).
  Supabase was chosen over Neon because it bundles realtime subscriptions
  and row-level security, which this app needs anyway.
- GitHub Pages is free, static-only hosting with no sleep behavior, a good
  fit for a site plus a client-side app that talks directly to a hosted
  database
  ([GitHub Pages hosting guide](https://everhour.com/blog/how-to-host-website-on-github/)).
- PWA installability (the "Install this app" prompt) follows the standard
  `beforeinstallprompt` pattern
  ([web.dev: patterns for promoting PWA installation](https://web.dev/promote-install/);
  [MDN: making PWAs installable](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)).
