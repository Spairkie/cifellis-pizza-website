# Owner's To-Do List

Every decision or purchase left standing between here and "finished" —
ordered by what actually blocks going live vs. what's optional polish.
Nothing in this file is read by the app itself; check things off as you
get to them. `ROADMAP.md` has the technical detail behind each item,
linked below; `git log` has the build history.

## 1. Payment processing — the big one

**Decide:** (a) require payment upfront for delivery, or keep today's
pay-on-arrival model? (b) buy a physical card reader, or skip it for now?

**Stick with Stripe.** It's already half-built into this code (both
server-side Edge Functions, the client glue in `order/payments.js`) —
switching processors now means throwing that away for no real benefit.

| Processor | In-person rate | Monthly fee | Hardware |
|---|---|---|---|
| **Stripe** (in code already) | 2.7% + 5¢ | $0 | $59–$349 |
| Square | 2.6% + 10¢ | $0–$149 | $49–$899 |
| Clover | bundled, varies | $15–$85+ | $199–$1,899 |

**If you want a physical reader:** Stripe Reader M2 ($59, Bluetooth to a
phone/tablet already running the Staff Hub) is the cheapest way in.
BBPOS WisePOS E ($249) is a standalone touchscreen option if you'd
rather not tie up a tablet. Tap to Pay on a staff phone needs no reader
purchase at all.

**What's built, what's left:** server always computes the charge amount
itself, only a signature-verified webhook ever marks an order paid — the
only missing piece is a Stripe account and the "Pay Now" button, which
needs real keys to build against. Full detail: `ROADMAP.md` → "1. Real
card payments."

## 2. Receipt printer

**You're looking at:** Star Micronics TSP143IIIU (~$290–390). Good
printer — but it's **USB, not network/Wi-Fi.**

**The catch:** `print-bridge/` (already built and tested) currently only
talks to *network* printers. USB support is stubbed, waiting on exactly
this kind of printer's vendor/product ID to finish — a small, already-
scoped piece of code once you have it in hand to test against.

**Simpler alternative:** any Wi-Fi/LAN ESC/POS printer (58mm or 80mm)
works with the bridge today, zero further code.

**Also need:** a cheap mini PC or Raspberry Pi (~$40–100) near the
printer to run the bridge service — doesn't need to be the same device
running the Staff Hub.

**Ongoing cost:** 80mm thermal paper runs ~$1–1.60/roll in bulk (a
50-roll case is roughly $50–75 total).

Full detail: `ROADMAP.md` → "3. Receipt printing."

## 3. What to run the Staff Hub on

**Good news: you likely don't need to buy a "POS system."** POS, Kitchen
Board, and Driver App are already a website — any device with a modern
browser runs them, installable as an app.

**Cheapest real option:** a budget Android tablet ($80–150 each) per
screen — one at the register, one in the kitchen — plus a $15–25 stand
each. Two screens, roughly $200–350 total.

**More durable, if grease/drops/heat are a real concern:** a rugged
tablet (~$200–300, e.g. AGM PAD P2 Active).

**Don't buy:** a bundled commercial POS terminal (Clover Mini/Station,
Square Register — $850–1,900+ each). That hardware locks to its own
proprietary software — it would run a second, redundant system next to
this one, not power it.

**Decide:** how many screens, tablet vs. rugged, budget.

## 4. SMS order notifications

**Need:** a Twilio account (phone number, Account SID + Auth Token). No
free tier for production sending — budget ~$1/month plus ~$0.008/text.

**Built and waiting:** the "text me when it's ready" opt-in checkbox,
the `phoneOptIn` column, and the Edge Function itself
(`supabase/functions/send-order-sms/`) — deploying it is what's left.

Full detail: `ROADMAP.md` → "2. SMS order notifications."

## 5. Upload real food photography

**Need:** photos of the menu items.

**Built and waiting:** drop a photo into `images/menu/` with the
matching filename below and it replaces the placeholder automatically —
no code change:

`stromboli.jpg` · `calzone.jpg` · `wings.jpg` · `hoagie.jpg` ·
`burger.jpg` · `pasta.jpg` · `salad.jpg`

Once real photos exist, worth revisiting which other items (beyond the
Panzarotti/Specialty Pies already flagged) should get the "Signature"
prominence treatment. Full detail: `ROADMAP.md` → "7. Smaller polish
items."

## 6. Custom domain + SEO

**Not started** — you have `cifelli.com` but haven't asked for the
migration. Full DNS/code checklist (including the steps only you can do
at your registrar): `ROADMAP.md` → "4b." Search Console/Bing/Google
Business Profile setup is intentionally deferred until after the domain
moves, so it isn't done twice — full detail: `ROADMAP.md` → "4."

---

## Already resolved — no decision needed

- **Numeric keypad (V7/SEVEN KP400):** it's a plain USB keyboard —
  already works today in any POS number field, nothing to buy or
  configure. Revisit only if you want dedicated shortcuts (e.g.
  auto-focus + Enter-to-submit on POS's cash-tendered field) —
  `ROADMAP.md` → Backlog.
- **UI sounds:** the only one actually worth adding is a System Health
  "service went down" alert tone — everywhere else a sound was
  considered (POS submit, driver claim/complete) is already covered by
  an on-screen toast. No audio files to source or license either way —
  synthesized the same way as the existing kitchen chime.
