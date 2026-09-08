/*
 * Print Bridge: a small local service that turns an order into an
 * actual receipt printout.
 *
 * The Staff Hub (staff/index.html) runs in a browser, which has no way
 * to talk to a USB or network printer directly. This is the piece that
 * sits on a mini PC (or even a Raspberry Pi) next to the printer,
 * listens for print jobs over a WebSocket, and sends the resulting
 * ESC/POS bytes to the printer over USB or LAN.
 *
 *          Staff Hub (browser)  --WebSocket-->  Print Bridge (this)  --USB/LAN-->  Printer
 *
 * STATUS: this runs and will genuinely print to a network (LAN) ESC/POS
 * printer once PRINTER_HOST is set below. USB support is stubbed (see
 * transport.js) because the right USB settings depend on your specific
 * printer model. Nothing in the Staff Hub calls this yet, see the
 * bottom of this file and staff/index.html's printReceipt() stub for
 * how to connect the two.
 *
 * -------------------------------------------------------------------
 * SETUP
 * -------------------------------------------------------------------
 *   cd print-bridge
 *   npm install
 *   cp .env.example .env      # then edit .env with your printer's IP
 *   npm start
 *
 * Leave it running on whatever mini PC sits next to the printer. It
 * does not need to be the same machine that runs the Staff Hub browser
 * tab, only the same local network.
 */

const { WebSocketServer } = require('ws');
const { buildReceipt } = require('./escpos');
const transport = require('./transport');

const PORT = Number(process.env.BRIDGE_PORT || 9001);
const AUTH_TOKEN = process.env.BRIDGE_TOKEN || ''; // set this in production, see README
const PRINTER_TRANSPORT = process.env.PRINTER_TRANSPORT || 'lan'; // 'lan' | 'usb'
const PRINTER_HOST = process.env.PRINTER_HOST || ''; // printer's IP, for LAN transport
const PRINTER_PORT = Number(process.env.PRINTER_PORT || 9100);
const RECEIPT_WIDTH = Number(process.env.RECEIPT_WIDTH || 32); // 32 chars ~= 58mm, 42 ~= 80mm

const wss = new WebSocketServer({ port: PORT });
console.log(`Print Bridge listening on ws://0.0.0.0:${PORT}`);
if (!PRINTER_HOST && PRINTER_TRANSPORT === 'lan'){
  console.warn('PRINTER_HOST is not set — print jobs will fail until you set it in .env');
}

/*
 * Health heartbeat (Staff Hub > System Health, Phase 4: Operational
 * Monitoring): reports "I'm alive" every 2 minutes so an admin can see
 * from the browser whether this service is actually running, without
 * needing to walk over and check the mini PC. Uses the same public
 * Supabase anon key already shipped in every page of this site (see
 * order/supabase-config.js) and one narrow RPC
 * (report_service_heartbeat, supabase/schema.sql) that can only ever
 * upsert this one named row -- same trust model as everything else
 * public-writable in that file. Entirely best-effort: a failed
 * heartbeat POST is logged and otherwise ignored, never allowed to
 * affect actual printing.
 */
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://yzehosyrsygvbddskpqs.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'sb_publishable_Bqdzh16tXCHmSj3zJUSWbw_hY_y9hcJ';
const HEARTBEAT_INTERVAL_MS = 2 * 60 * 1000;

async function sendHeartbeat(status, detail){
  try{
    await fetch(`${SUPABASE_URL}/rest/v1/rpc/report_service_heartbeat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SUPABASE_ANON_KEY,
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      },
      body: JSON.stringify({ p_service: 'print-bridge', p_status: status, p_detail: detail }),
    });
  }catch(err){
    console.warn('Heartbeat POST failed (non-fatal, printing is unaffected):', err && err.message || err);
  }
}

const heartbeatDetail = () => `transport=${PRINTER_TRANSPORT}${PRINTER_TRANSPORT === 'lan' ? `, host=${PRINTER_HOST || '(not set)'}` : ''}`;
sendHeartbeat(PRINTER_HOST || PRINTER_TRANSPORT !== 'lan' ? 'healthy' : 'degraded', heartbeatDetail());
setInterval(() => {
  sendHeartbeat(PRINTER_HOST || PRINTER_TRANSPORT !== 'lan' ? 'healthy' : 'degraded', heartbeatDetail());
}, HEARTBEAT_INTERVAL_MS);

wss.on('connection', (ws) => {
  ws.on('message', async (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); }
    catch { return ws.send(JSON.stringify({ ok:false, error:'Invalid JSON' })); }

    if (AUTH_TOKEN && msg.token !== AUTH_TOKEN){
      return ws.send(JSON.stringify({ ok:false, error:'Unauthorized' }));
    }

    if (msg.type !== 'print' || !msg.order){
      return ws.send(JSON.stringify({ ok:false, error:'Expected { type: "print", order: {...} }' }));
    }

    try {
      const buffer = buildReceipt(msg.order, { width: RECEIPT_WIDTH });
      await transport.send(buffer, {
        transport: PRINTER_TRANSPORT,
        host: PRINTER_HOST,
        port: PRINTER_PORT,
      });
      ws.send(JSON.stringify({ ok:true, ticket: msg.order.ticket }));
    } catch (err) {
      console.error('Print failed:', err);
      ws.send(JSON.stringify({ ok:false, error: String(err && err.message || err) }));
    }
  });

  ws.send(JSON.stringify({ ok:true, hello:'print-bridge', transport: PRINTER_TRANSPORT }));
});

/*
 * What staff/index.html needs to add to actually use this (not done
 * yet, since it needs a real printer + a chosen BRIDGE_TOKEN to test
 * against):
 *
 *   function printReceipt(order){
 *     const ws = new WebSocket('ws://<mini-pc-ip>:9001');
 *     ws.onopen = () => ws.send(JSON.stringify({ type:'print', order, token: '<same as BRIDGE_TOKEN>' }));
 *     ws.onmessage = (e) => {
 *       const res = JSON.parse(e.data);
 *       if (!res.ok) showToast('Print failed: ' + res.error);
 *     };
 *   }
 *
 * Call it wherever a new order should trigger a kitchen ticket, e.g.
 * right after a new order appears in the POS/Kitchen Board queue.
 *
 * Note on https: the Staff Hub is served over https (GitHub Pages).
 * Most browsers block a plain ws:// connection from an https page
 * except to "localhost". If the bridge runs on a different machine
 * than the browser, you'll need either: (a) run the Staff Hub from
 * that same mini PC (so it's http://localhost from its own point of
 * view), or (b) put a real TLS certificate on the bridge and use wss://.
 * Worth solving once you're actually hooking up hardware, not before.
 */
