/*
 * Sends a raw ESC/POS byte buffer to the actual printer.
 *
 * Two transports:
 *
 * - LAN (implemented, works today): most network/Ethernet or Wi-Fi
 *   thermal printers listen on raw TCP port 9100 (the old "JetDirect"
 *   port) and just want the ESC/POS bytes written straight to the
 *   socket. No driver needed. This is the easiest way to get a real
 *   printer working with this bridge, if your printer has an Ethernet
 *   port or Wi-Fi and you can find its IP (check the printer's self-
 *   test page, or your router's device list).
 *
 * - USB (stubbed, needs a real device to finish): USB thermal printers
 *   usually show up as a USB "printer class" or sometimes a raw HID/bulk
 *   device. The `usb` npm package (native bindings to libusb) can talk
 *   to it directly, but the exact vendor/product ID and endpoint
 *   numbers are specific to your printer model, so this is left as a
 *   TODO to fill in once you have the actual hardware in hand:
 *     1. `npm install usb`
 *     2. Plug in the printer, run `node -e "console.log(require('usb').getDeviceList())"`
 *        to find its vendorId/productId.
 *     3. Fill in sendOverUsb() below using that device and its OUT
 *        endpoint (usually the first bulk OUT endpoint on interface 0).
 *   On Linux you may also be able to skip all of this and just
 *   `cat receipt.bin > /dev/usb/lp0` — worth trying first.
 */

const net = require('net');

function sendOverLan(buffer, { host, port = 9100, timeoutMs = 5000 }){
  return new Promise((resolve, reject) => {
    if (!host) return reject(new Error('sendOverLan: printer "host" (IP address) is required'));
    const socket = new net.Socket();
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error(`Timed out connecting to printer at ${host}:${port}`));
    }, timeoutMs);

    socket.connect(port, host, () => {
      socket.write(buffer, (err) => {
        clearTimeout(timer);
        socket.end();
        if (err) reject(err); else resolve();
      });
    });
    socket.on('error', (err) => { clearTimeout(timer); reject(err); });
  });
}

async function sendOverUsb(_buffer, _opts){
  throw new Error(
    'sendOverUsb() is not implemented yet — it depends on your specific ' +
    'printer\'s USB vendor/product ID. See the comment at the top of ' +
    'transport.js for how to fill it in once you have the hardware.'
  );
}

/* opts: { transport: 'lan'|'usb', host, port } */
function send(buffer, opts){
  if (opts.transport === 'usb') return sendOverUsb(buffer, opts);
  return sendOverLan(buffer, opts);
}

module.exports = { send, sendOverLan, sendOverUsb };
