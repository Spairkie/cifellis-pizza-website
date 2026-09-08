# Owner's To-Do List

Things that are blocked on you specifically — an account to create, a
piece of hardware to buy, content only you can provide — not on more
code. This is your personal tracking list; `ROADMAP.md` has the full
technical detail behind each item if you want it (linked below), and
records the from-scratch history of everything already built. Check
things off here as you get to them; nothing in this file is read by
the app itself.

## [ ] Add SMS order notifications

**What you need:** a Twilio account — buy a phone number, get an
Account SID and Auth Token. No free tier for production sending
(trial credit only); budget roughly $1/month for the number plus
~$0.0079 per text.

**What's already built and waiting on this:** the checkbox on the
order form ("Text me when my order's ready"), the `phoneOptIn` column
on every order, and the actual Edge Function code itself
(`supabase/functions/send-order-sms/`) — deploying it is what's left.
Full detail: `ROADMAP.md` → "2. SMS order notifications."

## [ ] Add real card payments

**Decision needed from you first:** which processor (Stripe is the
standard choice for a business this size — flat ~2.9% + 30c, no
monthly fee), and whether delivery orders should require payment
upfront or keep today's pay-on-arrival model.

**What you need once decided:** a Stripe account (or your chosen
processor's). The frontend steps are already written out in
`order/payments.js`.

Full detail: `ROADMAP.md` → "1. Real card payments."

## [ ] Set up receipt printing

**What you need:** a thermal receipt printer (network/Wi-Fi ones are
the easy path — 58mm or 80mm, look for "ESC/POS" in the listing) and a
cheap mini PC or Raspberry Pi to run the print bridge near it. If you
want USB instead of network, that also needs your printer's vendor/
product ID off the actual hardware.

**What's already built and waiting on this:** `print-bridge/` — the
ESC/POS formatting and sending to a network printer is tested and
working code, just needs real hardware to point at, plus one button
wired up in the Staff Hub to actually call it (the function to add is
commented at the bottom of `print-bridge/index.js`).

Full detail: `ROADMAP.md` → "3. Receipt printing."

## [ ] Upload real food photography

**What you need:** photos of the menu items, however you're sourcing
them.

**What's already built and waiting on this:** drop a photo into
`images/menu/` using the matching filename below and it replaces the
placeholder automatically — no code change, no deploy step beyond the
usual `git add`/commit/push (or just committing the new image file
directly). Also true for the homepage's other photo spots (storefront,
hero shots) if you ever want to refresh those.

Category banner filenames currently still on placeholders:
- `images/menu/stromboli.jpg`
- `images/menu/calzone.jpg`
- `images/menu/wings.jpg`
- `images/menu/hoagie.jpg`
- `images/menu/burger.jpg`
- `images/menu/pasta.jpg`
- `images/menu/salad.jpg`

Once real photos exist, worth revisiting which other items (beyond the
Panzarotti and Specialty Pies already flagged) should get the
"Signature" prominence treatment — that's a one-line change per item
once you have a list in mind. Full detail: `ROADMAP.md` → "6. Smaller
polish items" and "Priority 5" entry.

## Also sitting in the backlog, lower urgency

Not urgent enough to be above the fold here, but written down in
`ROADMAP.md`'s Tier 3 section so nothing gets lost:
- **External numeric keypad shortcuts** — you confirmed it's a
  standard keyboard, so this already works today with zero code;
  flag it again once you land on an exact model if you want dedicated
  shortcuts built (e.g. auto-focus + Enter-to-submit on POS's cash-
  tendered field).
- **Custom domain migration** (`cifelli.com`) — full checklist already
  written in `ROADMAP.md` → "4b," including the DNS steps that are on
  you, not something code can do for you.
- **Google Search Console / Bing / Google Business Profile** — SEO
  setup, intentionally paused until the domain migration above, so it
  isn't done twice.
