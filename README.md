# Cifelli's Pizza: website and order system

Website, online ordering, staff POS, kitchen board, and delivery driver app
for Cifelli's Pizza (700 Chews Landing Rd, Lindenwold, NJ 08021).

## What's in here

- **`index.html`**: the marketing site (menu, specials, reviews, hours,
  and an "Order Online" link into the app below).
- **`order/`**: the Order Hub, one web app with four role-based screens
  (Customer Kiosk, Staff POS, Kitchen Board, Driver App) that all share one
  live order queue. Installable as its own app (a PWA) on a tablet or
  phone.
- **`supabase/`**: the database schema and setup instructions for the
  free backend that powers live orders. See `supabase/README.md` to finish
  setup, it's the one manual step required.

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

The trade-off: everything currently talks to Supabase with the same public
key (no staff login yet), which is fine for internal tools on devices you
control, and is covered in more detail in `supabase/README.md`.

If this ever needs to grow past what Supabase's free tier or built-in
features cover (SMS notifications, a receipt printer bridge, real payment
processing), the natural next step is a small serverless function (a
Supabase Edge Function, or a free Render web service) added alongside,
not a rebuild.

## Getting it running

1. **Finish the database setup**: follow `supabase/README.md` (create a
   free Supabase project, run the schema, paste two values into
   `order/supabase-config.js`). Takes about five minutes.
2. **Turn on GitHub Pages**: repo Settings > Pages > Source: "Deploy from a
   branch" > Branch: `main`, folder `/ (root)` > Save. The site will be
   live at `https://spairkie.github.io/cifellis-pizza-website/` within a
   minute or two.
3. **Open the Order Hub** at `/order/` on whatever devices will run each
   role (a tablet at the counter for the kiosk, a laptop or tablet at the
   register for POS, a screen in the kitchen, phones for drivers). Each
   device picks its role once; it's remembered after that (switch anytime
   with "Switch screen" in the header).
4. **Install it as an app** (optional but recommended for kiosk/kitchen/
   driver devices): open the Order Hub in Chrome or Edge, tap "Install this
   app on this device" on the role picker screen, or use the browser's
   own install/Add to Home Screen option. On iPhone, use Safari's Share >
   Add to Home Screen (iOS doesn't support the automatic install prompt).

## What's real, and what isn't (yet)

Real: the menu (matches the shop's actual items and prices), the order
flow, the live shared queue across all four screens, ticket numbers, and
the kitchen board's order-aging warnings.

Not built: real payment processing. Card is selectable as a payment method
throughout, but nothing actually charges a card, every order is paid in
person (cash or card at pickup/delivery), matching how the shop operates
today. Adding real card processing later (Stripe, Square, or similar) is a
separate, deliberate step, not something to bolt on quietly.

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
