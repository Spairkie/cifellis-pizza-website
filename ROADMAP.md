# Roadmap

Where the project stands, and what's left. Last reviewed 2026-09-07.

**Picking this project up fresh (especially in Claude Code)?** Read
`HANDOFF.md` first — it's a short orientation doc written specifically
for that handoff, with credentials status, known gotchas, and where to
start. This file is the detailed history.

## Next Development Roadmap, added 2026-09-07 by the owner

The active backlog as of this writing — supersedes the older "Feature
backlog" further down this file (that one's fully resolved except the
day-mode/high-contrast item, folded into item 10 below). Each item's
own dated entry (search this file for its name) has the implementation
detail; this list is just the tracker. **Do not redo or interfere with
already-shipped items unless something here specifically asks for it.**

**Priority 1 — reliability / production hardening**
- [x] Branded 404 page (Home / Order Online / Call / Menu)
- [x] Fix service-worker fallbacks (HTML fallback for navigations only)
- [x] Anti-abuse architecture prep (Turnstile-ready extension point +
  documented Edge Function long-term path)
- [x] Delivery address validation rework (explicit Check Address
  button, cached lookups, no more per-keystroke geocoding)

**Priority 2 — performance / customer UX**
- [x] Optimize intro + 3D loading (smarter timing than plain eager,
  without reintroducing the lazy-load deadlock)
- [x] Improve repeat-visitor intro (shortened/skipped on return visits,
  an Order Now action on the intro itself)
- [x] Persistent mobile conversion bar (Order / Call / Directions)

**Priority 3 — privacy / accessibility / recovery**
- [x] Customer-facing policies (privacy, ordering/cancellation/refund,
  SMS consent, delivery/location-data disclosure)
- [x] Disaster-recovery documentation (backup/restore, outage
  procedure, phone-order fallback, printed menu backup)
- [x] High-contrast accessibility mode (dark stays default; light/day
  mode explicitly deferred again until wanted) — now covers both
  `index.html` and `order/index.html` (the kiosk), sharing one
  `localStorage` preference between them

**Priority 4 — code quality**
- [x] Reduce duplicated ordering logic between `order/index.html` and
  `staff/index.html` (pricing, cart, pizza-builder, menu normalization,
  validation) — no framework rewrite, just shared files. Both
  increments now shipped: pricing/menu normalization, then cart state
  + pizza-builder/cart-pane UI, all consolidated into
  `order/ordering-core.js`. See the "Cart state and pizza-builder UI
  consolidated" dated entry for the second increment's detail.

**Priority 5 — content / conversion polish**
- [x] Prepare menu/order UI for more real food photography (owner is
  sourcing photos separately) — responsive layouts, stronger visual
  prominence for the Original Panzarotti/specialty pies/signature items

## Cart state and pizza-builder UI consolidated, 2026-09-07 (Claude Code)

The second (and last planned) increment of the Priority 4 item above.
`order/index.html` (customer kiosk, always `mode==='customer'`) and
`staff/index.html` (Staff Hub POS, always `mode==='pos'`) each carried a
full, near-duplicate copy of 14 identically-named functions covering
cart state, the menu/cart pane HTML builders, and all their wiring:
`resetOrderCtx`, `addLine`, `changeQty`, `buildMenuPaneHTML`,
`buildCartPaneHTML`, `wireCategoryBar`, `wireItemButtons`,
`renderSpecialtyPizzas`, `wireSpecialtyButtons`, `renderPizzaBuilder`,
`wireSeg`, `updateChangeDue`, `renderCart`, `renderOrderLayout` — plus
the small cart-drawer helpers `updateCartButtonBadge`, `openMobileCart`,
`closeMobileCart`, `wireMobileCart`, and `saveCartToStorage` (needed by
the now-shared `renderCart`). All of it now lives once in
`order/ordering-core.js`, loaded by both pages.

Before merging, diffed every one of those functions line-by-line
between the two files rather than assuming either copy was current.
8 were already byte-identical (safe to move as-is). The other 6 had
real, deliberate differences that needed reconciling by hand rather
than picking one file's version wholesale:
- `wireItemButtons` — sold-out toast text differs by audience
  ("is sold out right now" for customers vs. "is marked sold out —
  clear it in Menu Editor to sell it" for staff); kept as an explicit
  `mode` branch in the merged function.
- `resetOrderCtx` — merged field shape now carries every field either
  page uses (`promoCode`/`discountAmount`/`discountLabel`/
  `formLoadedAt` from the customer side, `editingOrderId` from POS);
  harmless unused fields on the other page.
- `buildMenuPaneHTML`, `renderCart` — `order/index.html`'s copies were
  strict supersets (paused-ordering banner, menu-hero photos, signature
  badges, discount row, mobile-cart badge, cart persistence — each
  already gated behind `mode==='customer'` or a null-checked DOM
  lookup), so those became the canonical versions with no behavior
  change for POS.
- `buildCartPaneHTML` — the one real trap. `order/index.html`'s POS
  fallback branch (dead code — that page never renders in `pos` mode)
  had gone stale after this session's earlier `order/index.html`-only
  work (the Check Address button, the tip UI) and no longer matched
  what `staff/index.html` actually serves. Used `staff/index.html`'s
  live POS branch, unchanged, rather than the tempting-but-wrong
  shortcut of reusing `order/index.html`'s fuller-looking-but-stale one.
- `renderOrderLayout` — the other real trap. `order/index.html` wires
  the tip-percentage buttons and promo-code button inside one
  `if (mode==='customer')` block, since in that file only customers see
  tip UI. But `staff/index.html`'s POS cart pane *also* has a tip
  section (counter tips, driver tips on phone-in deliveries) and wires
  it unconditionally. Copying `order/index.html`'s version verbatim
  would have silently broken tip buttons in POS. The merged function
  keeps promo-button wiring customer-only (self-guarded by a null
  check, since POS has no promo UI) but moved tip-segment wiring
  outside any mode check, matching `staff/index.html`'s working
  behavior. Mobile-cart wiring, saved-address autofill, and the
  online-ordering-pause disable stayed customer-only exactly as
  before.

Also removed, now that both files were already open for this: the dead
vestigial customer-ordering-flow copy inside `staff/index.html`
(`initCustomerView`, `submitCustomerOrder`, `showOrderConfirmation`) —
never called from anywhere in that file (confirmed via
`goToRole`/`initPosView`), flagged as safe-to-delete-later in
`HANDOFF.md` since before this session started.

Verified with `node --check` on every inline `<script>` block in both
files plus `ordering-core.js`, then a live end-to-end Playwright run
against production Supabase on a local static server: a real customer
order through the kiosk (specialty pizza + build-your-own, tip applied,
cart badge, full checkout) and a real POS order through Staff Hub
(login, add item, tip applied — confirming the `renderOrderLayout` fix
above actually works — cash tendered/change due, ring-up, cart reset
after submit). Both produced real orders (`T730573`, `T700885`/
`T732832`); all three deleted from `orders` afterward.

## High-contrast mode extended to the ordering kiosk, 2026-09-07 (Claude Code)

The follow-up flagged in the Priority 3 entry below: `order/index.html`
now has the same high-contrast toggle as the homepage, same
implementation (the same three custom properties overridden under
`:root[data-contrast="high"]`, applied before first paint via an early
script). Deliberately shares the exact same `localStorage` key
(`cifellisHighContrast`) as the homepage's toggle rather than a
separate one — since both pages are the same origin, turning it on
either place carries over to the other automatically, no extra code
needed for that beyond just reusing the key. `staff/index.html` (an
internal tool, not public-facing) remains out of scope.

Verified directly: toggling on the homepage and then navigating to the
kiosk shows it already applied at `domcontentloaded` (no flash), the
kiosk's own toggle reflects and controls the same shared state, and
toggling off from the kiosk updates the stored preference correctly.

## Priority 1: reliability / production hardening, 2026-09-07 (Claude Code)

First batch from the owner's structured "Next Development Roadmap." Four
items, all shipped.

**Branded 404 page.** New `404.html` at the repo root (GitHub Pages
serves this automatically for any unmatched path under a project site).
Self-contained (its own inline styles, doesn't depend on the rest of the
site loading correctly) with Home / Order Online / Menu / Call links.
Uses root-relative paths (`/cifellis-pizza-website/...`) matching every
other absolute link already in this codebase — which means, same as
`robots.txt`/`sitemap.xml`/the canonical tags, it'll need updating
during the eventual custom-domain migration (see "4b. Custom domain
migration" below) — added to that checklist.

**Service worker fallback bug, fixed in all three (`sw.js`,
`order/sw.js`, `staff/sw.js`).** All three had the same bug: on ANY
failed same-origin GET, they fell back to serving `index.html` — not
just for page navigations, but for a failed JS/CSS/image/font/`.glb`
request too. In practice this only ever fires when a visitor is truly
offline (a normal 404 for a missing file resolves as a successful fetch
with a 404 status, never hitting the failure path at all) — but for
that offline-and-not-yet-cached case, a script tag or `<model-viewer>`
getting HTML back where it expected JS or a binary model fails with a
confusing parse error instead of a clean "you're offline" signal.
Fixed: the index.html fallback now only applies when `request.mode ===
'navigate'` (an actual page load); everything else either serves its
own cached copy if one exists, or fails as a normal network error, same
as if there were no service worker at all. Bumped `CACHE_NAME` in all
three (v1 → v2) so this fix reaches already-installed clients on their
next visit, not just new ones. Verified directly: going offline and
fetching a JS file that was never cached now correctly throws a network
error instead of returning HTML; a navigation request while offline
still correctly serves the cached app shell.

**Anti-abuse architecture, prepared for a future upgrade.** The
honeypot + timing check in `order/index.html`'s checkout now live in
one named function, `passesAntiSpamChecks()`, with the exact extension
point documented inline for adding a real challenge later (Cloudflare
Turnstile or hCaptcha, both free) if actual abuse ever shows up:
render the widget's container near the submit button, read its
response token, and verify it server-side before the insert is
allowed — rather than trusting a client-side "the widget rendered"
signal, which proves nothing on its own.

The longer-term architectural question the owner raised — moving
anonymous order creation behind a Supabase Edge Function instead of a
direct client-side table insert — is worth writing down even though it
isn't built yet: an Edge Function would let order creation do things a
plain PostgREST insert + trigger can't cleanly do: verify a Turnstile
token against Cloudflare's siteverify endpoint (an outbound HTTPS call
mid-request, not something a Postgres trigger does well without
`pg_net` and its own complexity), rate-limit with real request context
(IP address, not just phone number — the current trigger's only real
gap, since a bot randomizing phone numbers per request isn't caught by
`enforce_order_rate_limit`), and keep all of that logic in one place
written in real application code (TypeScript/Deno) instead of split
across client JS and PL/pgSQL. This is a genuinely bigger change (new
tooling — the Supabase CLI and a `supabase functions deploy` step not
currently part of this project's workflow — and a new trust model,
since the Edge Function would need the `service_role` key server-side
to bypass RLS the way the client currently doesn't need to) — not
attempted now, flagged here so it doesn't need rediscovering from
scratch. Worth doing once (or before) real abuse shows up, not
preemptively.

**Delivery address checking, reworked in `order/geo.js`.** No longer
fires a geocode lookup on a debounced timer while typing — instead, an
explicit "Check Address" button next to the field (added in both
`order/index.html`'s customer/POS forms and `staff/index.html`'s
duplicate of the same form). Repeat lookups of the same address text
within a session (re-clicking Check Address without changing it, or
typing back to something already checked) are served from an in-memory
cache instead of hitting Nominatim/OSRM again. `geo.js` itself is
unchanged in shape — still the one file to swap for a paid geocoder
later, per its own header comment — this only changed when/how often
it's called, not what it calls. Verified directly: typing an address no
longer fires any geocode request; clicking Check Address fires exactly
one; clicking it again unchanged fires zero more (served from cache).

## Priority 2: performance / customer UX, 2026-09-07 (Claude Code)

Second batch from the owner's roadmap. Three items.

**Smarter 3D model loading, without reintroducing the lazy-load
deadlock.** `loading="eager"` stays (removing it is exactly what caused
the original bug — this hero sits below a full-screen intro splash, and
model-viewer's default behaves like viewport-based lazy loading). What
changed: the `<model-viewer>` tag no longer carries `src` in its initial
markup at all; a small script sets `heroModel.src` after
`requestIdleCallback` (falling back to a 400ms `setTimeout` where
that's unavailable). This gives the intro splash's own video first
claim on bandwidth for its critical first frame, while never making the
model's load depend on scroll position or visibility — the one thing
that actually caused the deadlock before.

**Repeat-visitor intro.** First visit still gets the full cinematic
splash, untouched. A return visit (`localStorage`, not
`sessionStorage` — "I was here yesterday" should count, not just
"earlier in this same tab") auto-scrolls past the intro ~250ms after
load instead of requiring a manual scroll or click every single time.
The splash section, video, and manual "Scroll Down" control are all
still fully there — a returning visitor who wants to see it again just
scrolls back up. Added an "Order Now" button directly on the intro
content itself, for anyone who wants to skip straight to ordering
without scrolling through the rest of the page at all.

**Persistent mobile conversion bar** (Order / Call / Directions),
fixed to the bottom of the viewport under 760px, safe-area aware
(`env(safe-area-inset-*)` on all sides, not just bottom). Marketing
site only (`index.html`) — deliberately not the ordering kiosk, which
already has its own floating cart button/badge in that same corner
that this would collide with; noted directly in the code as a warning
for if this pattern is ever extended there. **A real bug caught before
shipping:** the intro's own "Scroll Down" hint is positioned 26px from
the bottom of its full-viewport-height section — which the new fixed
bottom bar now covers, since a `position:fixed` element sits outside
normal document flow and doesn't push content up on its own. Fixed by
pushing `.intro-scroll` up to clear the bar's height on the same mobile
breakpoint; also nudged the existing `#toTop` button and the footer's
bottom padding to clear it the same way. Confirmed the bar is
completely absent above the 760px breakpoint (no accidental effect on
desktop).

## Priority 3: privacy / accessibility / recovery, 2026-09-07 (Claude Code)

Third batch. Three items.

**Customer-facing policies** — new `policies.html`: Privacy Policy,
Ordering/Cancellation/Refunds, Text Message Consent, and Delivery &
Location Data, as one page with anchored sections rather than four
separate pages (simpler to link, and small-business policy pages
commonly work this way). Written to describe what this specific system
actually does — not a generic template — grounded in reading the real
code: pay-in-person (no card data collected through the site), the
actual Supabase/RLS access model, Cloudflare's cookieless analytics,
localStorage (not cookies) for cart/intro state, the real SMS opt-in
behavior (recorded today, sending itself not wired up yet — see item 2
in the "What's fully working" section below), and driver location
tracking scoped to active deliveries only (matches the Driver Map
feature's own scoping, described honestly as the same system, not a
separate hidden one). Flagged at the top as accurate-to-practice, not
lawyer-reviewed. Linked from the homepage footer and directly under the
Place Order button on checkout.

**Disaster-recovery documentation** — new `DISASTER-RECOVERY.md` at the
repo root, for whoever runs this project, not customers: diagnosing a
Supabase-vs-GitHub-Pages outage, backup/restore steps (`pg_dump`/
`psql`, since free-tier Supabase doesn't include automatic backups —
checked which tier gets them before writing this as if it were a given
extra), a printed-menu-backup habit tied to Menu Editor saves, and how
active orders are handled when an outage hits mid-service. No
credentials anywhere in it, by design — every step says *where* to find
what it needs (the Supabase dashboard), never the value itself.

**High-contrast accessibility mode**, `index.html` only for this pass
(the marketing site was the explicit original scope; the ordering
kiosk would need the same treatment as a natural follow-up, not
claimed as done here). Dark theme stays the default in both modes, per
the owner's explicit call on that earlier in this project — this
boosts contrast within the existing palette rather than introducing a
light theme. Implemented as one global override of the three custom
properties (`--paper-dim`, `--line-on-ink`, `--line-on-paper`) most of
the page's dim text and hairline borders already read through, rather
than touching each rule individually — a toggle button in the header
(persisted to `localStorage`) flips a `data-contrast="high"` attribute
on `<html>`, set by a tiny script placed before the stylesheet even
loads so a returning visitor with it on never sees a flash of normal
contrast first. `prefers-reduced-motion` handling (already respected
for the intro video) is untouched either way. Verified directly:
toggling swaps the color values live, the choice survives a reload and
is already applied at `domcontentloaded` (before first paint), and
`aria-pressed` tracks state correctly for assistive tech.

## Priority 4: reduce duplicated ordering logic, 2026-09-07 (Claude Code)

A real, live refactor of code both apps depend on for money math — done
carefully, and deliberately narrow rather than a full merge. Confirmed
first that `order/index.html` and `staff/index.html` had genuinely
diverged: `staff/index.html`'s `computeTotals()` was missing the
`discount` parameter added earlier this session for promo codes
entirely (harmless today, since Staff POS has no promo-code UI to call
it with one — but it's exactly the kind of drift this task exists to
prevent, and proof the risk is real, not theoretical).

**New `order/ordering-core.js`**, loaded by both pages via `<script
src>`, same as `db-supabase.js`/`geo.js` already are. Contains what was
confirmed byte-identical (or safely unifiable — one file had richer
category `photo`/`placeholder` fields than the other; kept the fuller
version, harmless where unused) between the two files: the hardcoded
fallback menu constants (`TAX_RATE`, `PIZZA_SIZES`, `TOPPINGS`,
`SPECIALTY_PIZZAS`, `CATEGORIES`, `SPECIALS_BY_DAY`, `DAY_NAMES`),
`applyMenuConfig()`/`loadMenuConfig()`, and the pricing/formatting
helpers `money()`, `escapeHtml()`, `lineLabel()`, `computeTotals()` —
the last of these now correctly supports the `discount` parameter in
both apps, closing the exact drift found above.

**Deliberately not extracted in this pass:** cart state
(`orderCtx`/`resetOrderCtx`), the pizza-builder UI, and
`buildCartPaneHTML`/`buildMenuPaneHTML`/`renderCart` — these remain
separate per-file, because they're not actually identical (the POS
cart pane has no promo-code field or SMS opt-in, for instance) and
merging them safely is a larger, separate piece of work than "pricing
math and menu normalization," which is what was asked for this round.
Flagging this explicitly so "gradually" means an actual next step
exists to pick up, not that the duplication problem is fully solved.

Also added `ordering-core.js` (and `geo.js`, which was missing too) to
both `order/sw.js` and `staff/sw.js`'s precached shell file list, and
bumped both `CACHE_NAME`s again (v2 → v3) — a new critical shared file
should be available offline from the first visit, not just after
runtime caching happens to grab it.

Tested end-to-end against the real live backend on both apps: the
customer kiosk's menu renders (21 categories), a real placed order's
displayed subtotal/tax/total matched exactly what landed in the
database; Staff POS rang up a separate real order with matching
totals; Analytics, Menu Editor (correct tax rate), Till, and Kitchen
Board all confirmed rendering with no errors. Test orders cleaned up
afterward.

## Priority 5: prepare for more food photography, 2026-09-07 (Claude Code)

Last item on the owner's roadmap. The owner is sourcing real photos
separately — nothing to integrate yet — so this is genuinely prep, not
photo placement:

**Responsive image handling confirmed already solid.** The category
banner images (`order/index.html`'s kiosk) already use
`object-fit:cover`, full-width/fixed-height for a consistent crop
regardless of source image dimensions, `loading="lazy"`, and an
`onerror` fallback straight to the existing placeholder SVG — exactly
what dropping in new, real photos needs, with zero code changes (per
the existing convention already noted in this file's "Smaller polish
items" section: a same-named real photo in `images/menu/` replaces the
placeholder automatically).

**Stronger visual prominence for Original Panzarotti and the Specialty
Pies**, on both the homepage's static menu preview and the live kiosk
— a "Signature" badge plus a subtle highlighted card treatment (gold-
tinted background/border), no new photos required to see the effect
now. Implemented as a small `isSignatureItem(cat, it)` helper in
`order/index.html` (currently just flags the `panzarotti` category —
the shop's own namesake dish, the one already named in this site's
daily-specials list) rather than a hardcoded one-off, so flagging more
items later (once there's an actual list of which dishes should stand
out, informed by the incoming photos) is a one-line change, not a new
feature. Deliberately not added to `staff/index.html`'s POS — that's
an internal tool where an eye-catching badge doesn't serve a purpose,
this is customer-browsing polish specifically.

Verified visually on both the homepage's Panzarotti section and the
live kiosk's Panzarotti category — badge and highlight render
correctly on both, no console errors.

**With this, every item on the owner's "Next Development Roadmap" (see
the tracker at the top of this file) is shipped.**

## Polish round: 3D hero pizza, anti-spam, Staff Hub UI cleanup, 2026-09-07 (Claude Code)

A batch of owner-requested polish items, all shipped together.

**3D pizza in the homepage hero.** The owner supplied `Pepperoni
pizza.glb` (a real 3D model, ~1.1MB). Added as `models/pepperoni-
pizza.glb`, rendered with `<model-viewer>` (Google's web component,
loaded from jsdelivr like every other CDN script in this project).
The existing hand-drawn SVG pizza is the real fallback, not just a
loading spinner: it's shown immediately (inline, zero load time),
and only fades out once the 3D model's `load` event actually fires;
if the model-viewer script or the .glb fails for any reason, nothing
happens and the SVG just stays up indefinitely. Tuned the camera
(`camera-orbit`, `field-of-view`, min/max orbit clamp) so it reads
well at the requested 440px/1:1 hero size, and turned off
model-viewer's built-in drag-hint icon (`interaction-prompt="none"`)
since it looked like a stray UI glitch sitting in the middle of a
decorative hero image.

**A real bug caught before this ever reached the owner:** this
homepage sits behind a full-screen intro splash (`#introSplash`) —
the hero section is below the fold until a visitor scrolls or clicks
"Scroll Down." model-viewer's default `loading="auto"` behaves like
native lazy-loading (only starts fetching once the element is near
the viewport), so without an explicit fix the 3D model would never
even start downloading until someone scrolled down — meaning anyone
who scrolled fast would see the model pop in late, or see the SVG
fallback for longer than necessary. Fixed with `loading="eager"` so
the fetch starts immediately on page load, in parallel with the
splash's own video, and is typically already finished loading by the
time a visitor scrolls to the hero at all. Only found this by loading
the real page in Playwright and checking element position/timing
directly — worth remembering for any future scroll-revealed content
on this homepage.

**Anti-spam / anti-bot safeguards**, three layers, requested
specifically to prevent bot spamming, order spamming, and false order
creation:
1. A honeypot field (visually hidden, `aria-hidden` so screen readers
   skip it entirely) on both public write-facing forms — the customer
   checkout in `order/index.html` and the driver self-application in
   `staff/apply.html`. A real visitor never sees or fills it; if it's
   filled, the submission is silently dropped.
2. A minimum-time-on-page check on checkout only (3 seconds from the
   order form appearing to clicking Place Order) — unlike the
   honeypot, a fast real customer with autofill and a restored cart
   could plausibly trip this, so it gets an actual (deliberately
   generic) toast instead of a silent no-op.
3. **The real backstop, server-side:** a Postgres trigger
   (`enforce_order_rate_limit`) blocks more than 5 customer-sourced
   orders from the same phone number in 15 minutes — this is the one
   layer that can't be bypassed by a script calling the REST API
   directly, unlike the two client-side checks above. Staff-entered
   POS orders are explicitly exempt (a busy shift legitimately rings
   up several orders for the same regular).
   None of this is a real CAPTCHA — a script specifically targeting
   this form can still work around a honeypot or a timing check. This
   stops the common, unsophisticated case; if real abuse ever shows
   up, hCaptcha or Cloudflare Turnstile (both free) would be the next
   step, deferred for now since both need a new account, same as the
   payment/SMS scaffolds already noted below.

**Staff Hub UI cleanup**, three separate requests:
- **Active-user indicator redesigned as a facepile** (overlapping
  circular avatars, initials on a color deterministically derived from
  each person's email) instead of a plain "N online" text label — the
  standard pattern collaborative tools (Figma, Linear, Google Docs) use
  for "who's here," recognizable at a glance and scales better than a
  growing text string as more staff sign in. The signed-in viewer's own
  avatar gets a gold ring. Clicking still opens the same dropdown with
  full names/roles as before.
- **"Report a Bug" moved from a text button crowding the header into a
  small icon-only circular button** — the header had grown to clock +
  presence + bug button + switch screen + sign out, genuinely crowded;
  considered a floating action button instead but rejected it since a
  persistent overlay could sit on top of and interfere with tapping
  real controls on working screens like Kitchen Board or POS, which
  matters more for an operational tool than a consumer app.
- **Role picker reorganized into three labeled sections** — Daily
  Operations (POS, Kitchen, Driver App, Till), Insights (Analytics,
  Driver Map), Management (Menu Editor, Store Settings, Driver Roster,
  Promo Codes, Bug Reports) — instead of one flat grid in whatever
  order each feature happened to be added over many sessions. A
  section with nothing visible in it for the signed-in person's role
  (e.g. "Management" for a driver-only account) hides itself entirely
  rather than showing an empty-looking heading.

Tested end-to-end: the 3D model loads and fades in correctly both
scrolled-into-view and (after the eager-loading fix) before ever being
scrolled to; all three anti-spam layers confirmed directly (honeypot
silently blocks with zero network calls fired, the timing check blocks
with a toast and a legitimate later submit succeeds, the database
trigger blocks the 6th rapid same-phone customer order while leaving
POS orders completely unaffected); the facepile renders correctly with
multiple simultaneous real sessions; role-section hiding confirmed
correct for both an admin (all three sections) and a driver-only
account (only Daily Operations). All test orders/rows cleaned up
afterward.

## Live driver map, 2026-09-07 (Claude Code)

Owner asked for this despite the backlog's own note that it's "probably
not the next thing to build" — built with the real cost that note
flagged (battery/privacy/data) deliberately minimized rather than
ignored.

**Location tracking is scoped to "this driver currently has an active
delivery out," not the whole time the Driver App happens to be open.**
That's the actual mitigation for the battery/privacy/data-usage concern
this feature was flagged with when first scoped — a driver between
deliveries, or just browsing other Staff Hub screens, reports nothing.
Uses the browser's `watchPosition` (not a polling timer), so the OS's
own location services choose the update cadence; database writes are
separately throttled to at most once every 15 seconds regardless of how
often the browser calls back. New `driver_locations` table, one row per
driver, RLS mirrors `staff_presence` exactly (own row to write, any
staff can read all of them) — a driver's own location is only ever
written by that driver, an admin or POS staff can see everyone's.

**New Staff Hub screen: Driver Map** (same audience as POS/Kitchen/
Analytics — not admin-only, not driver-only), a live Leaflet map over
free OpenStreetMap tiles (same "free, no API key" reasoning as the
Nominatim/OSRM geocoder already used for delivery distance). Each
driver gets a pin, live-updating as their location changes; the shop
itself gets a fixed pin for reference. **Handles a driver who closes
the tab mid-delivery** by treating anything not updated in over 2
minutes as "may be offline" (grayed out, "last seen Xm" in the popup)
rather than presenting a stale position as current — the row only gets
deleted outright once a driver cleanly finishes their last delivery or
clocks out; an abrupt disconnect just goes stale and visibly says so.

**A real bug caught and fixed before this ever reached testing:**
`staff/index.html` already loads `order/geo.js` (for the delivery
distance lookup), which declares its own top-level `const
SHOP_LOCATION` — my first pass declared a second one for the map,
which is a hard `SyntaxError` (redeclaring a `const` across script tags
in the same page throws, it doesn't just shadow), silently killing the
*entire* script block it was in and leaving `initDriverMapView`
undefined. Fixed by reusing the existing global instead of redeclaring
it — worth remembering given how much cross-file duplication already
exists in this project (see `HANDOFF.md`'s note on that): a new global
name should be checked against what `order/geo.js` and the rest of
`staff/index.html` already declare before adding it, not assumed free.
Caught by actually loading the page in Playwright rather than syntax-
checking alone — a syntax checker sees each `<script>` block in
isolation and would never have flagged a cross-block redeclaration.

Tested end-to-end against the real live backend with Playwright's
geolocation mocking: a driver claiming a delivery starts reporting a
location that lands in the database with the exact mocked coordinates,
the Driver Map correctly shows both the driver's pin and the shop's,
completing the delivery stops tracking and removes the row, and the
map drops the marker in real time afterward. Also confirmed the
permission boundary: general staff can see Driver Map, a driver-only
account cannot. All test rows cleaned up.

## Promo code engine, 2026-09-07 (Claude Code)

Owner's policy decision (2026-09-07): **one redemption per phone number
per code** — a customer can't reuse the same code twice, but a different
code is fine. Enforced with a real unique constraint on
`(code, phone)` in a new `promo_redemptions` table, not just a UI
check — same "the check that matters lives in the database" principle
as every other trust boundary in this project.

**New `redeem_promo_code(code, phone)` Postgres function** (security
definer, like `rate_delivery()`): validates the code exists, is active,
and isn't expired, then atomically inserts the redemption row (the
unique constraint is what actually blocks a repeat) and returns the
discount. Raises a specific exception per failure reason (invalid,
inactive, expired, already used) rather than a bare boolean — surfaced
to the customer as the exact error text, since promo UX benefits from
knowing *why* a code didn't work.

**Checkout UI** (`order/index.html`): a Promo Code field in the cart
pane, "Apply" validates against the phone number already entered above
(tied to it at that moment — if the phone field changes afterward, the
discount is dropped and the customer's asked to re-apply, since the
redemption was already consumed against the old number). Discount shows
as its own line between Subtotal and Tax on the cart, the receipt, and
the confirmation screen. Discount is applied to the *taxable* subtotal
(a coupon reduces what's actually taxed, the standard treatment), not
tacked on after tax.

**New admin-only Staff Hub screen: Promo Codes** — create a code
(percent or fixed dollar amount off, optional expiry), deactivate/
reactivate existing ones, see a live redemption count per code.

**Small general-purpose addition:** `order/db-supabase.js`'s adapter
gained a `.rpc(name, params)` passthrough — `redeem_promo_code()` needed
to be callable from the same shared client instance the rest of the
kiosk already uses (this project deliberately keeps one Supabase client
per page), and there was no existing way to call a Postgres function
through the Firestore-shaped wrapper. Available for anything else that
needs it later, same as the earlier `collection().get()` addition.

**One schema quirk worth flagging:** `promo_codes` uses `code` (not
`id`) as its real primary key, but the Staff Hub's adapter always calls
`.doc(id)` against a column literally named `id`. Added a surrogate
`id uuid unique` column purely so Promo Codes management could use the
same adapter pattern every other admin screen already does, rather than
writing one-off raw-client code just for this table.

Tested end-to-end against the real live backend, including placing (and
then deleting) a real order through the actual checkout flow: created a
10%-off code from the admin screen, applied it at checkout with a math
check (subtotal $20 → $2 discount → tax on $18 → confirmed the exact
cents landed in both the UI and the saved order row), confirmed the
same phone reusing the code is rejected, a different phone succeeds,
and deactivating the code blocks further redemptions. All test rows
(order, redemption, code) cleaned up afterward.

## Driver leaderboard, 2026-09-07 (Claude Code)

Added to the Driver App screen itself (not admin-only) since the whole
point of a leaderboard is drivers seeing how they stack up — this is
gamification for drivers, not a management report. Needed no new
schema: every stat it shows (deliveries, miles, tips, average rating)
was already tracked per-order and computed the same way the existing
per-driver stats panel does, just aggregated across every approved
driver instead of one.

Three period tabs (This Week / This Month / All-Time, rolling windows —
not calendar-boundary weeks, consistent with how "today" is computed
everywhere else in this app), ranked by delivery count, a trophy on
whoever's in first, the signed-in driver's own row highlighted and
tagged "(you)". Drivers with zero deliveries in the selected period
just don't appear, rather than cluttering the board with empty rows.

Tested end-to-end against the real live backend with two real driver
test accounts and real completed delivery orders: correct ranking (2
deliveries beat 1), correct miles/tips/average-rating math, correct
"(you)" tagging from the second driver's own perspective, period switch
works. Test orders cleaned up afterward.

## Live bug reporting, 2026-09-07 (Claude Code)

First Tier 3 item — picked over the other Tier 3 entries specifically
because it didn't need a decision or information only the owner would
have (promo codes need a fraud policy call, the driver map and keypad
shortcuts need info about hardware/cost tradeoffs the owner would weigh
in on). A "Report a Bug" button now sits in the Staff Hub header for
every signed-in staff member — describes what's broken, auto-tags which
screen they were on, goes straight into a new admin-only "Bug Reports"
screen (open reports first, most recently resolved below, Mark Resolved
button). Staff don't need to see the list, just the ability to add to
it — mirrors the write-only/read-restricted split already used for
similar staff-vs-admin screens in this project.

**A real, live bug caught building this feature, worth flagging for
whoever reads this next:** the Bug Reports screen subscribes live
(`onSnapshot`) so a report or resolution shows up immediately in every
open tab — but `bug_reports` was never added to the `supabase_realtime`
publication the way `orders`/`drivers`/`driver_shifts` are, so Postgres
change notifications for it were never actually being broadcast. The
underlying database writes worked fine either way (confirmed directly
via SQL) — only the *live* re-render silently never fired, so a report
would sit unresolved-looking on screen even after clicking "Mark
Resolved" until the page was manually reloaded. Fixed in `schema.sql`
by adding the same realtime-publication block the other three tables
use. Worth remembering for any future onSnapshot-based screen: the
other newer tables added this session (`store_settings`,
`register_shifts`, `staff_presence`) all deliberately use one-shot
`.get()` fetches instead and don't need this — it's specifically
`onSnapshot` usage that requires the table be in the publication.

Tested end-to-end against the real live backend, including
re-confirming after the realtime fix: a non-admin test account can't
see the Bug Reports card at all, submitting a report from POS records
the right message/screen/reporter, the admin's live view shows it
immediately, resolving it updates instantly with no reload needed, and
the resolution correctly records who resolved it and when. Cleaned up
all test rows afterward, confirmed the table's empty.

## CRM/analytics improvements, 2026-09-07 (Claude Code)

Second Tier 2 item, the "CRM/analytics improvements" backlog bullet's
three sub-items, all built together since they touch the same data:

**Repeat-customer flagging beyond Analytics.** A small gold "Regular"
badge now shows next to a customer's name on Kitchen Board tickets and
the POS live queue — not just in the Analytics tab — whenever 2+ orders
on file share that phone number. Both those screens already fetch the
full live orders table before filtering down to active-only, so this
reuses that same fetch (`buildRegularsIndex()`) rather than a separate
query.

**Sparklines on the Analytics stat cards.** "Orders Today" and "Revenue
Today" now show a 7-day trend line (a small inline SVG polyline, no
charting library) under the number — shape only, no axis or numbers, so
it reads as "trending up/down/flat" at a glance rather than something to
study.

**Horizontal timeline of today's order events.** A new section on
Analytics: every order placed today plotted as a dot across a 24-hour
bar, colored by outcome (in progress / completed / cancelled), hover for
ticket/time/status/total. Deliberately built from *all* of today's
orders including cancellations — the only place on this screen that
shows cancelled orders at all, since a cancellation is still a real
event of the day even though it's excluded from every revenue number
elsewhere on the page.

Tested end-to-end against the real live backend: inserted a historical
order and a same-day, same-phone active order, confirmed the Regular
badge renders on both Kitchen Board and the POS queue for the active
one, confirmed both sparklines and timeline dots render with no console
errors. Cleaned up test orders afterward, confirmed no leftover rows.

## Active-user indicator (who's online), 2026-09-07 (Claude Code)

First Tier 2 item. A small "● N online" widget in the Staff Hub header
(next to the clock) — click it to see who else is signed in and which
screen each person is on right now.

**Deliberately not Supabase Realtime Presence.** That was the obvious
first approach, but Realtime presence/broadcast channels aren't gated
by RLS the way table reads are — anyone holding the project's public
anon key (which the customer kiosk also uses, by design, since anon
keys are meant to be public) could join a presence channel by a
guessable name and see staff email addresses without ever signing in
as staff, since there's no server-side check tying channel access to
`is_staff()`. Built a plain `staff_presence` table instead, with the
exact same `is_staff()`-gated RLS as everything else in this project —
any signed-in staff member can read the whole table, but each row can
only ever be written by its own owner (`id = auth.uid()`). Confirmed
directly with an anon (unauthenticated) client against the live
project: even with a real row in the table, an anon `select` returns
zero rows.

**How it works:** every ~20 seconds while any Staff Hub screen is open,
and immediately on every role switch, the client upserts its own row
(email + current screen + timestamp). "Online" means seen in the last
45 seconds (2-3x the heartbeat interval). Own row is deleted on sign-out
so a stale session doesn't show as online for the last 45 seconds after
leaving; if the tab is just closed without signing out, the row simply
ages out of the online window on its own — no special handling needed.

Tested end-to-end with two simultaneous real sessions (different
browser contexts, both real test accounts) against the live backend:
each correctly saw "2 online" with the other's email prefix and current
screen, the widget's dropdown listed both with "(you)" on the right
one, signing one out dropped the other's count to 1, and both rows were
gone from the table once fully signed out.

## Kitchen notification sound + badge, and Till/end-of-day management, 2026-09-07 (Claude Code)

The remaining two Tier 1 backlog items, same session as the pause/Store
Settings work above.

**Kitchen notification sound + badge.** Kitchen Board now dings (a
synthesized two-note chime via the Web Audio API -- no sourced audio
file, no licensing question, per the research note below) and shows a
red count badge next to "Current Orders" whenever a genuinely new order
arrives (status freshly `'new'`, not just any status change -- advancing
a ticket yourself doesn't ring it) while Kitchen Board is the active
screen. The badge also prefixes the browser tab title (`(3) Staff Hub |
...`) so a counter person working the register still notices a new
order even with the Staff Hub in a background tab. Clears on click or
when the window regains focus. Deliberately doesn't ding for whatever's
already sitting in `'new'` the moment you open Kitchen Board -- only for
what arrives after.

**Till / End-of-day management** (new Staff Hub role, `register_shifts`
table). Built to the shape in this file's own research note below:
opening the register records a starting cash count; a live report while
the register is open shows counter cash/card totals, tips, order count,
and average ticket, computed from completed orders since the register
opened; closing the register takes a counted cash amount, computes
over/short against expected drawer cash, and snapshots the whole report
onto the closed row (so history doesn't drift if orders are edited
later). Available to the same audience as POS/Kitchen/Analytics (any
non-driver-only staff, not admin-gated) -- whoever's actually working
the register needs to open/close their own till.

One correctness point worth flagging for whoever reads this next:
**delivery cash is deliberately excluded from "expected drawer cash."**
A delivery order's cash is collected by the driver at the door, not
physically in the shop's register, until the driver returns and settles
up -- something a naive "sum all cash orders" implementation would get
wrong and make the till look short for no real reason. Delivery cash/card
totals are still shown, just called out separately as "with drivers, not
the drawer." Also: a completed order counts toward whichever shift was
open when it was *completed* (`updatedAt`, the closest thing to a
completion timestamp that exists), not whichever shift was open when it
was *placed* -- so an order placed right at shift changeover counts as
cash for whoever was actually holding the register when it was paid for.
Enforced server-side that only one register can be open at a time (a
partial unique index on `register_shifts`, not just a UI check) --
tested directly that a second concurrent open is rejected at the
database level.

Tested end-to-end against the real live backend: opened a register,
inserted a completed counter-cash order and a completed delivery-card
order via direct SQL, confirmed the live report split them correctly
(counter cash counted, delivery card called out separately, tips/order
count/avg ticket all correct), closed with a deliberately short count
and confirmed the over/short math and history row were both right,
confirmed the one-open-shift-at-a-time constraint rejects a second
concurrent open at the database level, confirmed a driver-only test
account can't see the Till card. Cleaned up every test row afterward
(orders and register_shifts) and confirmed zero rows left behind.

**Feature backlog status:** all five Tier 1 items are now shipped. Tier
2 (system clock -- already bundled into the pause/Store Settings work
above; active-user indicators, deeper CRM/analytics, high-contrast mode,
micro-interactions) is next if wanted, otherwise see Tier 3 for lower-
priority/bigger-scope items.

## Pause online orders + Store Settings screen, 2026-09-07 (Claude Code)

First work picked up from the `HANDOFF.md` handoff, with direct
Postgres access this time (a connection string from the owner) — schema
changes were applied straight via `psql`-equivalent instead of the
paste-into-dashboard dance the claude.ai session was stuck with. Built
the two highest-priority Tier 1 backlog items together, since the
backlog itself said they belonged on one settings surface.

**New: `store_settings` table** (singleton row, same shape as
`menu_config` — public read, admin-only write, version-bump trigger),
now part of `supabase/schema.sql`. Holds `ordersPaused`, `pauseMessage`,
`hoursOverrideActive`, `hoursOverrideNote`, and `receiptMessage`.

**Pause/throttle online orders.** The kiosk (`order/index.html`) now
loads this row at boot and again right before final submit (so a pause
flipped mid-visit still catches the order, not just a stale page-load
check). When paused: a banner explains why above the menu, the Place
Order button disables with "Online Ordering Paused" instead of
submitting, and `submitCustomerOrder()` itself refuses even if the UI
were somehow bypassed. Staff-entered POS orders are untouched by design
— this only gates the customer-facing kiosk.

**New Staff Hub screen: Store Settings** (`data-role="storesettings"`,
admin-only — hidden from the role picker entirely for non-admins, same
as Driver Roster and Menu Editor since the least-privilege pass). Edits
the pause toggle + message, a holiday/special-hours override banner
text, and the receipt footer message, with the same optimistic-
concurrency save check Menu Editor uses (refuses to overwrite if someone
else saved since you opened the screen).

**Kitchen Board pause badge.** A one-tap "Online Orders: On / Paused"
badge in the Kitchen Board header, per the backlog's suggested
placement — visible to every staff member on that screen (so kitchen
staff know orders are paused even if they can't act on it) but only
clickable for admins, who can flip it without leaving Kitchen Board.
Same underlying `store_settings` row Store Settings edits; a toggle from
either place is reflected in the other on next load.

**Receipt message customization.** `buildReceiptHTML()` in
`order/index.html` (the customer's printable/PDF receipt, already
shipped) now renders the live `receiptMessage` instead of a hardcoded
"Thank you for your order!" line — the one place a receipt message
already existed to customize, since the print-bridge hardware path
(item 3 below) isn't wired into the UI yet.

**Holiday/special hours override, on the homepage.** `index.html` had
zero Supabase dependency before this — added the Supabase JS CDN script
+ `order/supabase-config.js` and one small inline fetch (public read
only, no adapter needed) that shows a banner under the static hours
table when `hoursOverrideActive` is on. Scoped deliberately narrow: it's
a banner over the existing static hours, not a rewrite of the whole
hours system into the database — kept the actual regular hours as plain
HTML, unchanged.

**System clock**, bundled in per the backlog's own note ("bundling with
Store Settings since both live in the same header area") — a small
live clock in the Staff Hub header next to Switch Screen / Sign Out,
updated every 15s.

**Tested end-to-end against the real, live Supabase backend** (a
working Postgres connection this session, unlike the claude.ai session
that came before) via Playwright against a local static server: baseline
kiosk/homepage behavior unchanged when nothing's paused; admin toggles
pause + hours override from Store Settings; Kitchen Board badge updates
and is clickable only for admin (confirmed read-only, non-clickable for
`claude-test-staff`); kiosk picks up the pause (banner, disabled button,
blocked submit) and homepage picks up the hours banner; receipt message
plumbing confirmed. Reset `store_settings` back to defaults after
testing and confirmed via direct query — nothing live was left paused.

**Feature backlog status:** both Tier 1 items above are done; Sold Out
toggle was already shipped before this session (confirmed in code,
despite the checkbox below still showing unchecked from when the
backlog was first written). Till/end-of-day management and the kitchen
notification sound are the two Tier 1 items still open.

## Feature backlog, added 2026-09-07

A large batch of feature requests came in at once. Organized here by
priority so nothing gets lost, with the reasoning for each tier —
not just a flat list. "Effort" is relative to this project, not
absolute. Checked off items link to where they ended up.

### Tier 1 — operationally important, build first
Things that directly protect the kitchen or the money, for a shop
actually taking live orders.

- [x] **Temporary "out of stock" toggle** (Menu Editor). Ran out of
  wings mid-shift — hide/disable an item on the kiosk in one tap
  without deleting it or touching pricing. Small addition to the
  Menu Editor already built. Shipped in an earlier session (see git
  log), before this backlog entry was even written down.
- [x] **Pause/throttle online orders**. The one every pizza-shop-with-
  online-ordering story eventually needs: a kitchen slammed on a
  Friday night with no way to stop new online orders piling on top
  of a 45-minute backlog. Needs a store-status flag the kiosk checks
  before showing the order form, plus a one-tap control somewhere
  staff-facing (Kitchen Board header is the natural spot). Shipped
  2026-09-07 — see "Pause online orders + Store Settings screen" above.
- [x] **Store Settings screen** (admin-only, new Staff Hub role):
  holiday/special hours override (the hours shown on the homepage and
  used for "today's special" are currently hardcoded), receipt
  message customization, and the pause-orders toggle above all live
  here as one settings surface rather than scattered controls. Shipped
  2026-09-07 — see "Pause online orders + Store Settings screen" above.
  ("Today's special" itself is still computed from `SPECIALS_BY_DAY` in
  `menu_config`, unrelated to this override — only the homepage's plain
  hours table got an override banner.)
- [x] **Till / End-of-day management**. Needs research into what this
  actually means for a single-register pizza shop before building
  anything — see the research note further down. Likely: a cash-drawer
  starting/ending count, a shift-close report (cash vs. card totals,
  tips, order count) staff can run at close, not a full accounting
  system. Shipped 2026-09-07 — see "Kitchen notification sound + badge,
  and Till/end-of-day management" above.
- [x] **Kitchen notification sound + badge** for new orders. A counter
  person who isn't staring at the screen needs to *hear* a new order
  land. Needs an actual audio asset (see note on sourcing below) and a
  badge count on the Kitchen Board / browser tab title. Shipped
  2026-09-07 — used a synthesized Web Audio chime (see "UI audio
  assets" research note below), not a sourced file — see "Kitchen
  notification sound + badge, and Till/end-of-day management" above.

### Tier 2 — real value, moderate effort
- [ ] **System clock** in the Staff Hub header — trivial on its own,
  bundling with Store Settings since both live in the same header
  area.
- [x] **Active-user indicators** — who else is signed into the Staff
  Hub right now (useful for a small team coordinating who's on
  register vs. kitchen). Needs a lightweight presence mechanism
  (Supabase Realtime Presence is built for exactly this). Shipped
  2026-09-07 — used a plain RLS-gated table instead of Realtime
  Presence, see "Active-user indicator (who's online)" above for why.
- [x] **CRM/analytics improvements**: repeat-customer flagging beyond
  what Analytics already shows, small inline sparkline-style charts
  instead of just numbers, a horizontal timeline of today's order
  events. Shipped 2026-09-07 — see "CRM/analytics improvements" above.
- [ ] **High-contrast / day mode toggle**. The whole site is currently
  one dark theme by design (matches the brand), so this is a real
  toggle to build (a second color scheme), not just respecting a
  system preference.
- [ ] **Micro-interactions / hover states** — polish pass across
  buttons, cards, transitions. Ongoing/incremental rather than a single
  task.

### Tier 3 — bigger scope or lower ROI for a shop this size
Not because they're bad ideas — because each is either a meaningfully
larger build, or brings ongoing costs/risks worth being deliberate
about before starting.

- [x] **Live driver map**. Needs a driver's phone to continuously
  report location while a delivery's out — real battery/privacy/data-
  usage cost to the driver, and meaningfully more infrastructure
  (frequent location writes, a map view, handling a driver who closes
  the tab mid-delivery). Worth it if delivery volume grows; probably
  not the next thing to build for a single shop's current volume. Owner
  asked for it anyway. Shipped 2026-09-07 — see "Live driver map" above.
- [x] **Promo code engine**. New schema (codes, redemption limits,
  expiry, stacking rules), and a decision needed on fraud/abuse
  handling (one code per phone number? per order?) before writing any
  code. Owner decided: one per phone. Shipped 2026-09-07 — see "Promo
  code engine" above.
- [x] **Driver leaderboards / gamification**. Fun, and drivers already
  have miles/tips/ratings tracked (Analytics, Driver App history) that
  a leaderboard could be built from relatively cheaply once wanted —
  low urgency until there are enough drivers for a leaderboard to mean
  anything. Owner asked for it despite low current driver count.
  Shipped 2026-09-07 — see "Driver leaderboard" above.
- [ ] **External numeric keypad shortcuts**. Real hardware-integration
  question: is this a USB keypad the browser sees as keyboard input
  (works today with zero code, standard keycodes), or something needing
  actual driver-level integration? Needs to know the actual hardware
  before scoping.
- [x] **Live bug reporting** (a way for staff to flag something broken
  from inside the app, mid-shift). Useful long-term, not urgent while
  a person can review the codebase directly the way this session has
  been doing. Shipped 2026-09-07 — see "Live bug reporting" above.
- [ ] **UI audio asset library** beyond the one kitchen notification
  sound — sourcing/licensing real audio files is a different kind of
  work than writing code (can't fabricate copyright-clear audio the
  way text/code gets written), scope this down to what's actually
  needed rather than building a "library" speculatively.

### Research notes

**Till / End-of-day management, for a shop this size.** The standard
shape at small independent restaurants (not enterprise POS) is:
1. **Start of day**: whoever opens registers a starting cash amount
   ("opened the drawer with $150").
2. **During the day**: nothing changes about how orders work — this
   is a reporting layer on top of existing order data, not a new
   payment system.
3. **End of day / shift close**: a report pulling from `orders` for
   that shift/day — total cash orders, total card orders, total tips,
   order count, average ticket — compared against an actual counted
   cash amount the closer enters, surfacing the difference (over/short)
   rather than trying to prevent it.
4. Optionally, a **shift concept** tying this to who was on register
   (ties in with the active-user-indicator idea above and the existing
   driver shift-clock pattern already built for drivers — the same
   `driver_shifts` table shape, generalized, could work for register
   shifts too).
This is a report + a light "shift" record, not a redesign of how
orders or payments work — payment is still cash-in-hand or card-in-
person, this just adds reconciliation on top. Worth confirming this
matches what's actually wanted before building the schema.

**UI audio assets.** Can't source copyrighted sound-effect libraries
(same reasoning as not reproducing song lyrics — a sound effect pack
is someone else's licensed work). Options: (a) generate a simple tone/
chime programmatically with the Web Audio API — no licensing question
at all since it's synthesized, not sourced, and is genuinely enough
for a "new order" alert; (b) the shop provides its own royalty-free
or purchased sound file to drop in. (a) is the pragmatic default
unless a specific sound is wanted.

## Least-privilege Staff Hub access + manager driver assignment, 2026-09-07

Staff Hub role cards now only show what the signed-in person actually has
access to, computed from the `isAdmin`/`isDriver` flags already on the
`staff` table (no schema change needed):
- Admin: everything (POS, Kitchen, Driver App, Analytics, Driver Roster,
  Menu Editor).
- General staff (neither admin nor driver): POS, Kitchen, Analytics.
- Driver-only staff: Driver App only.

This is also the fix for a reported bug: `admin@cifellis.com` seeing
"No driver profile found" on Driver App. That screen used to be shown to
every signed-in staff member regardless of whether they had a linked
`drivers` row at all; an admin who isn't a driver would see the card,
click it, and hit that error. Now the card simply isn't shown to anyone
without `isDriver` set, so the error only surfaces in the one case it's
actually meant for (an `isDriver` flag set without a matching drivers
row, which shouldn't normally happen but is still handled gracefully).
Enforced here for the UI/UX; the real security boundary was and remains
the RLS policies in `schema.sql` — hiding a button never was what
protected the data, this just stops people from being shown screens
that don't apply to them.

Also added: an admin can now assign an unclaimed "ready" delivery
straight to a specific driver from Kitchen Board, instead of only being
able to wait for a driver to self-claim it from the Driver App. Uses the
exact same `driver`/`driverId` fields self-claim already writes, so
Analytics, delivery history, and everything else treats an assigned
delivery identically to a claimed one. Verified live end-to-end (a
manually-inserted "ready" order, assigned via the real UI, confirmed
`out_for_delivery` with the right driver in the database) and cleaned
up. Building this surfaced a small missing piece in the Supabase
adapter — `order/db-supabase.js`'s `collection()` had `.doc(id).get()`
for a single row and `.onSnapshot()` for a live query, but nothing for
a one-shot "give me every row once" fetch, which the drivers dropdown
needed. Added `collection().get()` to match (same doc shape as
`onSnapshot`'s callback, just one fetch instead of a subscription) —
general-purpose, available for anything else that needs the same thing
later.

**Test credentials for each role** (all `@cifellispizza.local`, password
`claudeTestPw2026`, all temporary — see the existing removal note
below, which now covers all three):
- `claude-test@cifellispizza.local` — admin + driver (sees everything)
- `claude-test-staff@cifellispizza.local` — general staff (POS/Kitchen/
  Analytics)
- `claude-test-driver@cifellispizza.local` — driver-only (Driver App
  only)

## Mobile ordering fixes + cart persistence + login UX, 2026-09-07

**Fixed: Place Order button unreachable on mobile.** Root cause: the
mobile cart drawer (`order/index.html`) had `overflow-y: visible` with a
capped `max-height: 82vh`. Once cart contents (items + tip selector +
delivery form + the button itself) exceeded that height, the button was
pushed below the visible drawer with no way to scroll to it — not
literally invisible, just permanently out of reach. Confirmed with a
real mobile-viewport test (Pixel 7 emulation) before and after; fixed
with `overflow-y: auto` on the drawer.

**Cart now survives a page reload.** Saved to `localStorage` on every
change, restored on load, expires after 6 hours (long enough to survive
an accidental reload, short enough that nobody reorders a stale cart
from a previous visit without noticing), and clears itself once an
order is actually placed.

**Friendlier login errors** (Staff Hub). Used to be one generic
"Incorrect email or password" for every failure. Now distinguishes
wrong credentials, an unconfirmed account, rate limiting, and network
failures, clears the password field, and adds a brief shake animation
so the message actually gets noticed.

**Clickable logo**, both apps: in the kiosk it returns to the menu
(closing the mobile cart drawer or account view if open); in the Staff
Hub it returns to the role picker, same as the existing "Switch screen"
button.

## Menu Editor + a serious RLS bug found along the way, 2026-09-07

Built, at the owner's request, a way for an admin to edit menu items,
prices, and daily specials from the Staff Hub instead of needing a code
change + deploy for every price update.

**New: `menu_config` table** (now part of `supabase/schema.sql` — see
"One file, not several" below). A single admin-editable JSON row holding
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

Fixed in `schema.sql` itself: function definitions moved before the
policies that use them, all three `staff` policies rewired to call
`is_staff()`/`is_admin()`. **Confirmed fixed live** — re-tested directly
against the production database after the owner ran the updated schema:
`staff` queries that used to error now succeed, `App.isAdmin` correctly
reads `true` for an admin account, and a full Driver Roster approval
(pending self-application → click Approve → `drivers.approved` flips to
`true` and a matching `staff` row is created) was exercised end-to-end
through the real Staff Hub UI and verified in the database afterward.

**One file, not several.** The RLS fix and the `menu_config` table both
started as separate one-off patch files (`staff-rls-recursion-fix.sql`,
`menu-config-migration.sql`) so they could be run individually while
sorting out sandbox network limits. Once both were confirmed working
live, they were folded into `schema.sql` itself and the standalone files
deleted — `schema.sql` is the single file for a from-scratch rebuild,
every statement in it safe to re-run (every table is `if not exists`,
every policy is dropped-then-recreated, the menu seed is
`on conflict do nothing`), so catching an existing project up on a
future schema change is always just: copy the whole current file,
paste into the SQL Editor, Run.

**⚠️ Remove before real production use:** temporary test accounts were
created for AI-assisted testing on 2026-09-07 — the persistent admin/
driver account `claude-test@cifellispizza.local` (`staff` + `drivers`
rows, plus the Supabase Auth user), and one *momentarily*-created
second driver account used only to verify the approval flow end-to-end
(created, approved, then fully deleted from `drivers`, `staff`, and
Auth in the same test — nothing from that one should remain, but worth
a quick look in Authentication > Users to confirm). Two more persistent
test accounts were added later the same day for role-visibility testing
— see "Test credentials for each role" above
(`claude-test-staff@cifellispizza.local`,
`claude-test-driver@cifellispizza.local`). Delete all three persistent
`claude-test*@cifellispizza.local` accounts (rows + Auth users) before
this site takes real customer orders. See git log around this date for
exact timestamps if anything needs auditing.

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
9. `404.html`'s four link `href`s are root-relative
   (`/cifellis-pizza-website/...`) — update to just `/...` once served
   from a custom domain's root instead of a GitHub Pages subpath.

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
