# Roadmap

Where the project stands, and what's left. Last reviewed 2026-09-07.

## Menu Editor + a serious RLS bug found along the way, 2026-09-07

Built, at the owner's request, a way for an admin to edit menu items,
prices, and daily specials from the Staff Hub instead of needing a code
change + deploy for every price update.

**New: `menu_config` table** (`supabase/menu-config-migration.sql`, not
yet run — see below). A single admin-editable JSON row holding
everything that used to be hardcoded JS constants in `order/index.html`
and `staff/index.html` (`TAX_RATE`, `PIZZA_SIZES`, `TOPPINGS`,
`SPECIALTY_PIZZAS`, `CATEGORIES`, `SPECIALS_BY_DAY`), seeded with the
exact values that were live at migration time (generated programmatically
from the actual JS, not retyped, to rule out transcription mistakes).
Publicly readable (the kiosk needs it), admin-only writable, with a
version/updatedAt/updatedBy trigger so the editor can warn on a
conflicting concurrent save.

**Both order/index.html and staff/index.html now load the menu from
Supabase at boot**, with the old hardcoded values kept in place as a
fallback — if `menu_config` doesn't exist yet, or the fetch fails for
any reason, the site behaves exactly as it did before this change.
Nothing about ordering or pricing changes until the migration is run.

**New Staff Hub screen: Menu Editor** (`staff/index.html`, role card
`menu`). Visible to all staff, same pattern as Driver Roster — anyone
can look, only an admin's edits actually save (client-side gate backed
by the same server-side RLS check). Covers tax rate, pizza sizes/topping
pricing, the topping list, specialty pizzas (fixed Medium/Large/Sicilian
price slots, blank = not offered in that size), every category and its
items (add/edit/remove item, add/remove whole category), and the seven
daily specials. Edits are local until "Save Menu" writes the whole
`menu_config.data` blob back in one update.

**Found in the process: a real, previously-invisible RLS bug.** Testing
the admin gate turned up that every query against `public.staff` --
select, insert, or update, for any signed-in staff member -- has always
failed with "infinite recursion detected in policy for relation staff",
confirmed directly via the REST API. The three policies on `staff`
checked admin/active status by selecting from `staff` inside their own
policy, which re-triggers itself forever. `is_staff()`/`is_admin()`
already existed in schema.sql as `security definer` functions built
specifically to avoid exactly this, but the `staff` table's own three
policies were never wired up to use them (every other table's policies
correctly call them). Practical effect: `App.isAdmin` has silently
evaluated to false for every staff member, always -- the error was
caught and swallowed in `loadMyStaffRow()`'s try/catch, so nothing
visibly crashed, but it means **Driver Roster's Approve button has never
worked for anyone**, ever, since this schema was first deployed. Went
unnoticed because no one had tested the approve flow with a real admin
account before now.

Fixed in two places: `schema.sql` itself (function definitions moved
before the policies that use them, all three staff policies rewired to
call `is_staff()`/`is_admin()` — correct for anyone deploying fresh from
scratch), and a standalone `supabase/staff-rls-recursion-fix.sql` to
patch the already-running production database (idempotent, safe to
re-run).

**⚠️ Two migrations need to be run in the Supabase SQL Editor before
this is fully live** (couldn't be run directly — no DDL access via the
service_role key, and this sandbox's network only permits outbound
HTTPS, so a direct Postgres connection wasn't possible either):
1. `supabase/staff-rls-recursion-fix.sql` — run this first, it's the
   one actually breaking things right now.
2. `supabase/menu-config-migration.sql` — turns on the Menu Editor and
   moves the live menu into the database.

**⚠️ Remove before real production use:** a temporary staff/admin/driver
test account was bootstrapped for AI-assisted testing on 2026-09-07
(email `claude-test@cifellispizza.local`, see git log around this date).
Delete its rows from `staff` and `drivers`, and remove the Supabase Auth
user, before this site is actually taking real customer orders for the
business.

## Review pass, 2026-09-07

Did the full review the previous entry asked for: read every file fresh,
tested live against the real GitHub Pages site and the real Supabase
backend (both were actually reachable this session, unlike earlier ones —
worth re-checking that's still true next time, since it's what made live
testing possible instead of only reading code). Found and fixed two real,
live bugs; checked everything else and it matched what this file already
claimed.

**Fixed — customer account creation and driver self-application were both
silently broken.** Root cause: this Supabase project requires email
confirmation (`mailer_autoconfirm: false`, checked via the project's own
`/auth/v1/settings`), but both `order/index.html`'s "Create Account" flow
and `staff/apply.html`'s driver signup assumed `signUp()` hands back an
active session immediately. It doesn't when confirmation is required — it
creates the login but returns no session, so the very next line (writing
the customer profile / driver application row) failed with a permissions
error, in the customer case with no error shown to the visitor at all
(confirmed live: the signup button did nothing, no toast, modal just sat
there). The apply.html version had a related bug on top: its check for
"does this need confirmation" tested `!user`, but Supabase returns a user
object either way — only `session` tells you whether confirmation is
pending — so that check never actually caught the case it was written for.

Fixed both: they now check for a session, not just a user; when there
isn't one, they save the form fields to `localStorage` and set
`emailRedirectTo` so clicking the confirmation email brings the visitor
back to the same page; and the customer-account and driver-application
writes finish automatically on that return visit once a real session
exists. If you ever turn off email confirmation for this project (Supabase
dashboard > Authentication > Sign In / Providers), the "session already
present" branch in both files still handles that in one step — no code
change needed either way.

Verified with Playwright: reproduced the original bug live (signup button
silently doing nothing), then confirmed both branches of the fix —
immediate-session and confirmation-required-then-return — against mocked
Supabase responses shaped exactly like the real project's, since the real
signup endpoint rate-limits repeat sign-ups from the same IP within a
short window (hit that limit partway through testing; expected Supabase
behavior, not a bug).

**Fixed — a smaller admin-only bug.** In `staff/index.html`, whether the
current user is an admin (`App.isAdmin`) was fetched without being
awaited before auto-resuming a saved role screen. An admin whose last
screen was Driver Roster and who reloads the page would land back on
Driver Roster with `isAdmin` still at its default `false`, so the Approve
buttons wouldn't render — nothing re-checks once the real value comes
back. Now awaited in the right place, so this can't happen.

**Checked and NOT a bug, in case a future session re-discovers this and
wonders:** the hero video (`videos/hero-pizza.mp4`) shows `networkState 3`
/ never loads in this sandbox's headless Chromium. Traced it all the way
down — file is valid, correctly-structured H.264/AAC MP4 with the moov
atom already at the front (faststart, good for streaming), server serves
range requests correctly, markup is correct. The actual cause:
`video.canPlayType('video/mp4; codecs="avc1...aac..."')` returns `''` in
this specific Chromium build, while a generic `video/mp4` returns
`'maybe'` — this sandbox's Playwright-bundled Chromium is an open-source
build without the licensed H.264 decoder, which real Chrome/Safari/Edge/
Firefox builds all ship. Don't "fix" this without re-confirming it's
actually broken somewhere real users' browsers would show it.

Everything else — kitchen board, POS queue and cancel/edit flow,
analytics, the driver app's claim/complete/shift-clock flow, `rate.html`'s
`rate_delivery()` RPC, the geo/distance lookup (Nominatim + OSRM, both
confirmed reachable and CORS-fine from a browser), and the RLS policies
in `supabase/schema.sql` — read through and, where testable without staff
login credentials, exercised live, and matched what this file already
said. `staff/index.html` also still contains a full, harmless-but-dead
second copy of the customer ordering flow (`initCustomerView`,
`submitCustomerOrder`, etc. — leftover from before the customer/staff
split in an earlier commit, never called from anywhere in that file).
Left it alone rather than risk a cosmetic edit to a 1900-line live file
that didn't need one; worth deleting next time someone's already in there
for an unrelated change.

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
