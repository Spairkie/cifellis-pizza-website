/*
 * Print Bridge: a small local service that turns an order into an
 * actual receipt printout, and can kick the cash drawer.
 *
 * The Staff Hub (staff/index.html) runs in a browser, which has no way
 * to talk to a USB or network printer directly. This is the piece that
 * sits on a mini PC (or even a Raspberry Pi) next to the printer,
 * checks Supabase for print jobs the Staff Hub has queued, and sends
 * the resulting ESC/POS bytes to the printer over LAN (or USB, once
 * that transport is filled in -- see transport.js).
 *
 *   Staff Hub (browser) --https--> Supabase (print_jobs table)
 *                                        ^
 *                                        | poll, every few seconds
 *                                        |
 *                              Print Bridge (this) --LAN/USB--> Printer/drawer
 *
 * STATUS: this runs and will genuinely print to a network (LAN) ESC/POS
 * printer once PRINTER_HOST is set below, and kick a drawer plugged into
 * that printer's drawer port. USB printer support is stubbed (see
 * transport.js) because the right USB settings depend on your specific
 * printer model.
 *
 * -------------------------------------------------------------------
 * WHY POLLING, NOT A WEBSOCKET PUSH FROM THE BROWSER
 * -------------------------------------------------------------------
 * An earlier version of this file ran a WebSocket server the Staff Hub
 * connected to directly. That can't actually work: the Staff Hub is
 * served over https (GitHub Pages), and every modern browser refuses a
 * plain ws:// connection from an https page as "mixed content" -- not
 * just to a remote machine, to any host, including localhost. There's
 * no code-level workaround short of a real TLS certificate on this
 * bridge (a genuine option, just more to maintain than a small shop
 * needs). Polling Supabase sidesteps the whole problem: this is a
 * Node process, not a browser page, so none of that applies to it --
 * it just makes an ordinary https request, the same way the heartbeat
 * below already does.
 *
 * -------------------------------------------------------------------
 * SETUP
 * -------------------------------------------------------------------
 *   1. In the Supabase SQL Editor, signed in as an admin, run:
 *        select set_print_bridge_token('<a long random string>');
 *      (32+ random characters -- a password manager's "generate" button
 *      is fine. This is the one and only time the plaintext value is
 *      usable; only its hash is stored.)
 *   2. cd print-bridge && cp .env.example .env
 *   3. Edit .env: PRINTER_HOST (your printer's IP) and BRIDGE_TOKEN
 *      (the exact same string from step 1).
 *   4. npm start
 *
 * Leave it running on whatever mini PC sits near the printer. It does
 * not need to be the same machine that runs the Staff Hub browser tab,
 * or even the same moment in time -- a job just waits in the queue
 * (Staff Hub > System Health shows this service as Healthy/Down) until
 * this process is running and picks it up.
 */

const { buildReceipt, buildDrawerKick } = require('./escpos');
const transport = require('./transport');

const PRINTER_TRANSPORT = process.env.PRINTER_TRANSPORT || 'lan'; // 'lan' | 'usb'
const PRINTER_HOST = process.env.PRINTER_HOST || ''; // printer's IP, for LAN transport
const PRINTER_PORT = Number(process.env.PRINTER_PORT || 9100);
const RECEIPT_WIDTH = Number(process.env.RECEIPT_WIDTH || 42); // 32 chars ~= 58mm, 42 ~= 80mm
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN || '';
const POLL_INTERVAL_MS = Number(process.env.POLL_INTERVAL_MS || 4000);
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://yzehosyrsygvbddskpqs.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'sb_publishable_Bqdzh16tXCHmSj3zJUSWbw_hY_y9hcJ';

if (!PRINTER_HOST && PRINTER_TRANSPORT === 'lan'){
  console.warn('PRINTER_HOST is not set — print jobs will fail until you set it in .env');
}
if (!BRIDGE_TOKEN){
  console.warn('BRIDGE_TOKEN is not set — every claim_pending_print_jobs call will be rejected until you run set_print_bridge_token() and put the same value here. See the SETUP comment at the top of this file.');
}

async function supabaseRpc(fn, body){
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok){
    throw new Error(`${fn} failed: ${res.status} ${await res.text().catch(() => '')}`);
  }
  return res.json();
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
const HEARTBEAT_INTERVAL_MS = 2 * 60 * 1000;

async function sendHeartbeat(status, detail){
  try{
    await supabaseRpc('report_service_heartbeat', { p_service: 'print-bridge', p_status: status, p_detail: detail });
  }catch(err){
    console.warn('Heartbeat POST failed (non-fatal, printing is unaffected):', err && err.message || err);
  }
}

const heartbeatDetail = () => `transport=${PRINTER_TRANSPORT}${PRINTER_TRANSPORT === 'lan' ? `, host=${PRINTER_HOST || '(not set)'}` : ''}`;
const heartbeatStatus = () => (PRINTER_HOST || PRINTER_TRANSPORT !== 'lan') && BRIDGE_TOKEN ? 'healthy' : 'degraded';
sendHeartbeat(heartbeatStatus(), heartbeatDetail());
setInterval(() => sendHeartbeat(heartbeatStatus(), heartbeatDetail()), HEARTBEAT_INTERVAL_MS);

/* One print/drawer-kick job. Never throws -- always reports completion
   back to Supabase (via complete_print_job) so a bad job doesn't sit
   "claimed" forever. */
async function processJob(job){
  try{
    let buffer;
    if (job.kind === 'drawer_kick'){
      buffer = buildDrawerKick();
    } else {
      buffer = buildReceipt(job.payload || {}, { width: RECEIPT_WIDTH });
      if (job.payload && job.payload.openDrawer){
        buffer = Buffer.concat([buffer, buildDrawerKick()]);
      }
    }
    await transport.send(buffer, { transport: PRINTER_TRANSPORT, host: PRINTER_HOST, port: PRINTER_PORT });
    console.log(`Printed job ${job.id} (${job.kind}${job.ticket ? ', ticket ' + job.ticket : ''})`);
    await supabaseRpc('complete_print_job', { p_id: job.id, p_bridge_token: BRIDGE_TOKEN, p_ok: true });
  }catch(err){
    const message = String(err && err.message || err);
    console.error(`Job ${job.id} failed:`, message);
    try{
      await supabaseRpc('complete_print_job', { p_id: job.id, p_bridge_token: BRIDGE_TOKEN, p_ok: false, p_error: message });
    }catch(reportErr){
      console.error('Also failed to report that failure back to Supabase:', reportErr && reportErr.message || reportErr);
    }
  }
}

async function pollOnce(){
  if (!BRIDGE_TOKEN) return; // already warned above -- no point hammering the RPC with a token that can't pass
  let jobs;
  try{
    jobs = await supabaseRpc('claim_pending_print_jobs', { p_bridge_token: BRIDGE_TOKEN });
  }catch(err){
    console.error('Could not check for print jobs:', err && err.message || err);
    return;
  }
  for (const job of jobs || []){
    await processJob(job); // one at a time -- a single socket to the printer, no point racing two prints together
  }
}

console.log(`Print Bridge started. Polling for print jobs every ${POLL_INTERVAL_MS}ms.`);
pollOnce();
setInterval(pollOnce, POLL_INTERVAL_MS);
