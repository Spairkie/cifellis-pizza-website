# Print Bridge

Turns an order into an actual printed receipt on a thermal printer. Runs
as a small always-on Node.js process on a mini PC (or Raspberry Pi) near
the printer, not as part of the website itself, since a browser can't
talk to a USB or network printer directly.

```
Staff Hub (browser)  --WebSocket-->  Print Bridge (this folder)  --USB/LAN-->  Printer
```

## What works right now

- A real ESC/POS receipt is generated from an order object (`escpos.js`)
  with your shop's header, the itemized order, subtotal/tax/tip/total,
  and a paper cut at the end.
- Sending that receipt to a **network (LAN/Wi-Fi) printer** works today
  (`transport.js`, `sendOverLan`) — this covers most modern receipt
  printers with an Ethernet or Wi-Fi port.
- The WebSocket server (`index.js`) accepts print jobs and reports
  success/failure back to whoever asked for the print.
- Once running, it reports a health heartbeat to Supabase every 2
  minutes, so Staff Hub > System Health shows this service as Healthy/
  Degraded instead of an unknown "Not Configured" — no setup needed
  beyond starting the bridge.

## What's still a stub

- **USB printers.** The right vendor/product ID and endpoint are specific
  to your printer model, so this needs to be filled in once you have the
  actual hardware — see the comment at the top of `transport.js`.
- **The Staff Hub doesn't call this yet.** `index.js` has the exact
  `printReceipt()` function to add to `staff/index.html` and where to
  call it from (when a new order comes in), commented at the bottom of
  the file. It's a few lines, left out until there's a real printer to
  test against.

## Setup

1. On the mini PC that will sit near the printer, install
   [Node.js](https://nodejs.org) (LTS is fine).
2. Copy this `print-bridge/` folder to that machine (or just clone the
   whole repo there).
3. ```
   cd print-bridge
   npm install
   cp .env.example .env
   ```
4. Edit `.env`: set `PRINTER_HOST` to your printer's IP address (check
   the printer's self-test/network status page, or your router's
   connected-devices list). Set `BRIDGE_TOKEN` to something random once
   you're on a real network.
5. ```
   npm start
   ```
   You should see `Print Bridge listening on ws://0.0.0.0:9001`.
6. Test it without touching the Staff Hub at all, from any machine on
   the same network with Node installed:
   ```js
   const ws = new WebSocket('ws://<mini-pc-ip>:9001');
   ws.onopen = () => ws.send(JSON.stringify({
     type: 'print',
     token: '<your BRIDGE_TOKEN>',
     order: {
       ticket: 'TEST-1', orderType: 'pickup', customerName: 'Test',
       items: [{ name:'Large Pepperoni', qty:1, unitPrice:15.99 }],
       subtotal: 15.99, tax: 1.10, tip: 0, total: 17.09,
     },
   }));
   ws.onmessage = (e) => console.log(e.data);
   ```
   If a receipt prints, the bridge and printer are talking correctly.

## Running it in the background permanently

Once it's working, use a process manager so it survives reboots, e.g.
[pm2](https://pm2.keymetrics.io/):
```
npm install -g pm2
pm2 start index.js --name print-bridge
pm2 save
pm2 startup
```
or a systemd service if you're comfortable with that on Linux.

## Why not just print from the browser?

Browsers deliberately can't send raw bytes to a USB or network device
for security reasons — the closest you get is the OS print dialog,
which is built for full pages, not 58mm receipt tape with paper cuts.
A tiny local service is the standard way every real-world POS system
handles this.
