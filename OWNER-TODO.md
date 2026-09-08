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
pipeline is fully implemented — a "Print" button on every POS order, an
"Open Drawer" button in Till, and a "Reprint an Order" search on the POS
Queue screen that finds any order at all, not just today's, by ticket
number *or* phone (a partial ticket like "4821" works too — no need to
remember the "T00" prefix), showing what's in the order before you
commit to printing it. Every request now reports back whether it
actually printed instead of leaving you guessing, and a live "Recent
Print Activity" log shows the last 24 hours — your first stop if the
printer's gone quiet. All of this queues a job Supabase-side; the bridge
polls for it and prints (kicking the drawer too, automatically, on any
cash order).
The only things left are buying the hardware above
and a **five-minute one-time setup step**: run
`select set_print_bridge_token('...');` in the Supabase SQL Editor and
put the same value in the bridge's `.env` — see `print-bridge/README.md`
for the exact steps. Nothing else to build.

Full detail: `ROADMAP.md` → "3. Receipt printing + cash drawer."

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

## 3b. Kitchen Board on a TV (optional)

Any TV works as a display — it just needs an HDMI input. The real
decision is what you plug into it to drive a browser full-screen, and
one of the obvious cheap answers turned out to have a landmine in it.

**Skip the Fire TV Stick, or be very specific about which model.**
Amazon is mid-transition to a new OS called Vega OS, which **cannot run
a kiosk browser at all** — no sideloading, no exceptions. The two newest
Fire TV Stick models (4K Select, late 2025; Fire TV Stick HD, April
2026) already run Vega OS. Only the older **4K Plus / 4K Max** models
are Android-based and can actually do this — and Amazon's own listings
don't always make the OS obvious, so confirm before buying.
[Fire TV Stick 4K Max (confirm Android-based before relying on it for this)](https://www.amazon.com/fire-tv-stick-4k-max-with-alexa-voice-remote/dp/B08MQZXN1X)

**Better cheap option, same trick, no OS-roulette:**
[Chromecast with Google TV (4K), ~$40–50](https://www.amazon.com/Chromecast-Google-Streaming-Entertainment-Search/dp/B0CMZRRBJT) —
plain Android TV throughout, not caught in any vendor platform
migration. Sideload [Fully Kiosk Browser](https://www.fully-kiosk.com)
via the "Downloader" app (same install method on either device), point
it at the Staff Hub URL, set it to auto-launch on boot with the
screensaver off.

**Most control, matches what you're already doing for the receipt
printer:** a Raspberry Pi or cheap mini PC running Chrome/Chromium with
the `--kiosk` flag — no app-store gatekeeping ever, and no dependency on
a streaming-stick vendor's OS choices. Same
[Raspberry Pi 5 starter kit](https://www.amazon.com/CanaKit-Raspberry-Essentials-Starter-Kit/dp/B0CVQT445P)
linked above works fine for this too (a second one — don't share it with
print-bridge, keep that one headless).

**Setup either way:** sign in once with a dedicated low-privilege staff
account (not admin — you don't want admin credentials sitting on a TV),
pick Kitchen Board as its role. The Staff Hub remembers a device's
chosen role and stays signed in, so a reboot goes straight back to
Kitchen Board with no re-login. Turn off the TV's screensaver/sleep
settings; if it's specifically an OLED TV, worth knowing static
dashboard content running 10+ hours a day has a long-run burn-in risk —
a regular LCD/LED TV doesn't have this issue.

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
