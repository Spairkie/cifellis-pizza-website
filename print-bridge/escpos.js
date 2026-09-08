/*
 * A small, dependency-free ESC/POS command encoder.
 *
 * ESC/POS is the command language almost every thermal receipt printer
 * understands (Epson TM-series, Star, and the countless generic
 * "80mm thermal printer" models sold for POS kiosks). It's just a
 * sequence of bytes: some are printable text, some are control codes
 * like "bold on" or "cut the paper". This module builds that byte
 * sequence from a plain JS description of a receipt; it doesn't talk
 * to any hardware itself (see transport.js for that).
 *
 * This only implements the handful of commands a pizza-shop receipt
 * needs. The full ESC/POS spec is much bigger (barcodes, images,
 * multiple character sets, etc.) — extend as needed.
 */

const ESC = 0x1b;
const GS = 0x1d;

class ReceiptBuilder {
  constructor(){
    this.chunks = [Buffer.from([ESC, 0x40])]; // ESC @ : initialize printer
  }

  text(str){
    this.chunks.push(Buffer.from(str, 'ascii'));
    return this;
  }

  line(str = ''){
    return this.text(str + '\n');
  }

  bold(on){
    this.chunks.push(Buffer.from([ESC, 0x45, on ? 1 : 0])); // ESC E n
    return this;
  }

  align(mode){ // 'left' | 'center' | 'right'
    const n = mode === 'center' ? 1 : mode === 'right' ? 2 : 0;
    this.chunks.push(Buffer.from([ESC, 0x61, n])); // ESC a n
    return this;
  }

  doubleSize(on){
    this.chunks.push(Buffer.from([GS, 0x21, on ? 0x11 : 0x00])); // GS ! n
    return this;
  }

  divider(width = 32){
    return this.line('-'.repeat(width));
  }

  feed(lines = 1){
    this.chunks.push(Buffer.from([ESC, 0x64, lines])); // ESC d n
    return this;
  }

  cut(){
    this.feed(2);
    this.chunks.push(Buffer.from([GS, 0x56, 0x00])); // GS V 0 : full cut
    return this;
  }

  toBuffer(){
    return Buffer.concat(this.chunks);
  }
}

/* Two columns on one line, e.g. "2x Large Pepperoni" .... "$27.98",
   padded to the given character width (32 or 42 for most 80mm/58mm
   printers at the default font). */
function twoCol(left, right, width = 32){
  const space = Math.max(1, width - left.length - right.length);
  return left + ' '.repeat(space) + right;
}

function money(n){
  return '$' + Number(n || 0).toFixed(2);
}

/* Build a full kitchen/customer receipt buffer from an order object
   shaped like the ones in supabase/schema.sql (camelCase fields). */
function buildReceipt(order, { width = 32 } = {}){
  const r = new ReceiptBuilder();

  r.align('center').bold(true).doubleSize(true)
    .line("Cifelli's Pizza")
    .doubleSize(false).bold(false)
    .line('700 Chews Landing Rd')
    .line('Lindenwold, NJ 08021')
    .line('(856) 435-8799')
    .divider(width);

  r.align('left').bold(true)
    .line('Ticket: ' + (order.ticket || ''))
    .bold(false)
    .line('Type: ' + (order.orderType || ''))
    .line('Name: ' + (order.customerName || ''));
  if (order.phone) r.line('Phone: ' + order.phone);
  if (order.address) r.line('Addr: ' + order.address);
  r.divider(width);

  (order.items || []).forEach((it) => {
    const label = `${it.qty}x ${it.name}${it.size ? ' (' + it.size + ')' : ''}`;
    r.line(twoCol(label, money(it.unitPrice * it.qty), width));
    if (it.notes) r.line('   ' + it.notes);
  });
  r.divider(width);

  r.line(twoCol('Subtotal', money(order.subtotal), width));
  r.line(twoCol('Tax', money(order.tax), width));
  if (order.tip) r.line(twoCol('Tip', money(order.tip), width));
  r.bold(true).line(twoCol('Total', money(order.total), width)).bold(false);

  if (order.notes) r.divider(width).line('Notes: ' + order.notes);

  r.divider(width).align('center').line('Thank you!').cut();
  return r.toBuffer();
}

/* Cash drawer "kick" pulse (ESC p m t1 t2) -- the standard command every
   ESC/POS printer forwards to a drawer plugged into its RJ11/RJ12 drawer
   port. m=0 selects drawer 1 (the only drawer almost anyone has); t1/t2
   are the pulse on/off time in 2ms units -- 25/250 (~50ms/~500ms) is the
   commonly-used default that works with virtually every drawer. */
function buildDrawerKick(){
  return Buffer.from([ESC, 0x70, 0x00, 0x19, 0xfa]);
}

module.exports = { ReceiptBuilder, buildReceipt, buildDrawerKick, twoCol, money };
