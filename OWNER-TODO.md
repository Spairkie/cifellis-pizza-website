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

## 2. Receipt printer + cash drawer

**Recommended: Epson TM-m30III (Ethernet)** — ~$275, built specifically
for tablet/cloud-POS setups like this one, has a cash-drawer kick port,
and is the transport `print-bridge/` already talks to (LAN/Wi-Fi, not
USB). Skip the Star Micronics TSP143IIIU you were looking at before —
it's USB-only, the harder path for no benefit here.
[Buy on Amazon](https://www.amazon.com/TM-m30III-Desktop-Direct-Thermal-Printer/dp/B0DN552V88)
· [$275 at Lavu](https://shop.lavu.com/products/epson-tm-m30iii-receipt-printer-ethernet-interface)

**Cash drawer** (the piece that was missing entirely from the plan) —
any RJ11/RJ12 drawer works, it plugs into the printer, not this bridge.
[MUNBYN 16" cash drawer, ~$60–80, explicitly Epson-compatible](https://www.amazon.com/clp/B082ZXBMX1)
is a reasonable, well-reviewed pick.

**Also need:** a cheap mini PC or Raspberry Pi near the printer to run
the bridge service — doesn't need to be the same device running the
Staff Hub.
[Raspberry Pi 5 starter kit, ~$120–140](https://www.amazon.com/CanaKit-Raspberry-Essentials-Starter-Kit/dp/B0CVQT445P)
is plenty for this — it just polls Supabase every few seconds and
forwards bytes to the printer, nothing demanding.

**Ongoing cost:** 80mm thermal paper runs ~$1–1.60/roll in bulk (a
50-roll case is roughly $50–75 total).

**What's built and ready (2026-09-09):** the print-and-drawer-kick
pipeline is fully implemented — a "Print" button on every POS order and
an "Open Drawer" button in Till, both queue a job Supabase-side; the
bridge polls for it and prints (kicking the drawer too, automatically,
on any cash order). The only things left are buying the hardware above
and a **five-minute one-time setup step**: run
`select set_print_bridge_token('...');` in the Supabase SQL Editor and
put the same value in the bridge's `.env` — see `print-bridge/README.md`
for the exact steps. Nothing else to build.

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
