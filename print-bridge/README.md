# Print Bridge

Turns an order into an actual printed receipt on a thermal printer, and
can kick a cash drawer plugged into that printer. Runs as a small
always-on Node.js process on a mini PC (or Raspberry Pi) near the
printer, not as part of the website itself, since a browser can't talk
to a USB or network printer directly.

```
Staff Hub (browser) --https--> Supabase (print_jobs table)
                                      |
                                      | polled every few seconds
                                      v
                          Print Bridge (this folder) --LAN/USB--> Printer + drawer
```

The Staff Hub queues a job by writing an ordinary row to Supabase (no
different from placing an order — just https, no special networking).
This bridge polls for pending jobs and prints them. See the "WHY
POLLING" comment at the top of `index.js` if you're wondering why this
isn't a direct WebSocket push from the browser — short version: the
Staff Hub is served over https, and every modern browser blocks a plain
`ws://` connection from an https page as mixed content, so a direct push
can't actually work without a real TLS certificate on this bridge.

## What works right now

- A real ESC/POS receipt is generated from an order object (`escpos.js`)
  with your shop's header, the itemized order, subtotal/tax/tip/total,
  and a paper cut at the end.
- Sending that receipt to a **network (LAN/Wi-Fi) printer** works today
  (`transport.js`, `sendOverLan`) — this covers the Epson TM-m30III (the
  recommended printer, see `OWNER-TODO.md`) and most modern receipt
  printers with an Ethernet or Wi-Fi port.
- **Cash drawer kick** (`escpos.js`, `buildDrawerKick`) — the standard
  ESC/POS pulse command every drawer's RJ11/RJ12 "kick" cable responds
  to, plugged into the printer's own drawer port (no separate wiring to
  this bridge). Fires automatically as part of a cash order's receipt
  print, or on its own via a "No Sale"/"Open Drawer" job with no
  receipt attached.
- Once running, it reports a health heartbeat to Supabase every 2
  minutes, so Staff Hub > System Health shows this service as Healthy/
  Degraded instead of an unknown "Not Configured" — no setup needed
  beyond starting the bridge.

## What's still a stub

- **USB printers.** The right vendor/product ID and endpoint are specific
  to your printer model, so this needs to be filled in once you have the
  actual hardware — see the comment at the top of `transport.js`. Not
  needed for the recommended Epson TM-m30III (LAN/Wi-Fi).

## Setup

1. **Set the bridge token first, from the Supabase SQL Editor, signed in
   as an admin:**
   ```sql
   select set_print_bridge_token('a-long-random-string-here');
   ```
   Use 32+ random characters — a password manager's "generate" button is
   fine. This is the only time the plaintext value is usable anywhere;
   only its hash is stored in the database. Write it down somewhere safe
   (a password manager), since you'll need the exact same value in step
   4 below, and there's no way to read it back out of Supabase later —
   if you lose it, just run the command again with a new value.
2. On the mini PC that will sit near the printer, install
   [Node.js](https://nodejs.org) **20.6 or newer** (needed for its
   built-in `.env` file support — check with `node -v`; if you're on an
   older LTS, update it first).
3. Copy this `print-bridge/` folder to that machine (or just clone the
   whole repo there).
4. ```
   cd print-bridge
   cp .env.example .env
   ```
   Edit `.env`: set `BRIDGE_TOKEN` to the exact same string from step 1,
   and `PRINTER_HOST` to your printer's IP address (check the printer's
   self-test/network status page, or your router's connected-devices
   list — give it a static/reserved IP so this never changes).
5. ```
   npm start
   ```
   You should see `Print Bridge started. Polling for print jobs every
   4000ms.` If `BRIDGE_TOKEN` or `PRINTER_HOST` is missing, it warns you
   right away instead of failing silently later.
6. Test it without touching the Staff Hub at all, from anywhere with
   internet access and `curl` (or Postman) — this inserts a job the way
   the Staff Hub eventually will:
   ```sh
   curl -X POST 'https://<your-project>.supabase.co/rest/v1/print_jobs' \
     -H 'apikey: <your anon key>' \
     -H 'Authorization: Bearer <your anon key>' \
     -H 'Content-Type: application/json' \
     -d '{"kind":"receipt","ticket":"TEST-1","payload":{"ticket":"TEST-1","orderType":"pickup","customerName":"Test","items":[{"name":"Large Pepperoni","qty":1,"unitPrice":15.99}],"subtotal":15.99,"tax":1.10,"tip":0,"total":17.09}}'
   ```
   (Requires being signed in as staff in practice — `print_jobs` INSERT
   is staff-only, same as everything else POS-adjacent. Easiest way to
   test for real: sign in to the Staff Hub and use its own "Print"
   button once that's wired up.) If a receipt prints within a few
   seconds, the bridge and printer are talking correctly.

## Running it in the background permanently

Once it's working, use a process manager so it survives reboots, e.g.
[pm2](https://pm2.keymetrics.io/):
```
npm install -g pm2
pm2 start npm --name print-bridge -- start
pm2 save
pm2 startup
```
or a systemd service if you're comfortable with that on Linux.

## Why not just print from the browser?

Browsers deliberately can't send raw bytes to a USB or network device
for security reasons — the closest you get is the OS print dialog,
which is built for full pages, not 58mm/80mm receipt tape with paper
cuts and a drawer kick. A tiny local service is the standard way every
real-world POS system handles this.
