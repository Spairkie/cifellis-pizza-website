// SMS order notification scaffold: NOT wired to a real SMS sender yet.
//
// The idea: text a customer when their order status changes (e.g.
// "Your order is ready for pickup!" or "Your driver is on the way").
// This is a Supabase Edge Function, deployed separately from the static
// site, that would do the actual sending. Nothing calls it yet.
//
// -----------------------------------------------------------------
// HOW TO FINISH THIS (Twilio is the common choice)
// -----------------------------------------------------------------
//
// 1. Create a Twilio account, buy a phone number, get your Account SID
//    and Auth Token.
//
// 2. Install the Supabase CLI and deploy this function:
//      supabase functions deploy send-order-sms
//    Set the Twilio credentials as function secrets (never commit
//    them to this repo):
//      supabase secrets set TWILIO_ACCOUNT_SID=... TWILIO_AUTH_TOKEN=... TWILIO_FROM_NUMBER=...
//
// 3. Fill in sendSms() below with a real fetch() call to the Twilio
//    Messages API (https://www.twilio.com/docs/sms/send-messages).
//
// 4. Trigger this function when an order's status changes. Two ways:
//      a) A Postgres Database Webhook (Supabase dashboard > Database >
//         Webhooks) on the `orders` table, firing on UPDATE, calling
//         this function's URL. Simplest, no extra code.
//      b) Call it directly from staff/index.html right after a status
//         update succeeds (in updateOrder()), passing the order id.
//    Either way, only send when phoneOptIn is true on the order, and
//    update smsStatus to 'sent' or 'failed' afterward (both columns
//    already exist in supabase/schema.sql) so you can see what went
//    out from the Staff Hub.
//
// 5. Respect phoneOptIn. The Customer Kiosk should have a checkbox for
//    this (see order/index.html's "Text me updates" field) — never
//    text someone who didn't check it.

interface OrderRecord {
  id: string;
  ticket: string;
  phone: string;
  phoneOptIn: boolean;
  status: string;
  orderType: string;
}

function messageForStatus(order: OrderRecord): string | null {
  switch (order.status) {
    case "ready":
      return `Cifelli's: order ${order.ticket} is ready for pickup!`;
    case "out_for_delivery":
      return `Cifelli's: order ${order.ticket} is out for delivery.`;
    default:
      return null; // No text for 'new', 'preparing', 'completed', 'cancelled'.
  }
}

async function sendSms(toPhone: string, body: string): Promise<void> {
  throw new Error(
    "sendSms() is not implemented yet. See supabase/functions/send-order-sms/index.ts " +
    "for the Twilio setup steps."
  );
}

Deno.serve(async (req: Request) => {
  const payload = await req.json();
  // Shape depends on how this is triggered. A Database Webhook sends
  // { type, table, record, old_record }; a direct call could send the
  // order object directly. This handles both.
  const order: OrderRecord = payload.record ?? payload;

  if (!order || !order.phoneOptIn || !order.phone) {
    return new Response(JSON.stringify({ skipped: true }), { status: 200 });
  }

  const body = messageForStatus(order);
  if (!body) {
    return new Response(JSON.stringify({ skipped: true }), { status: 200 });
  }

  try {
    await sendSms(order.phone, body);
    return new Response(JSON.stringify({ sent: true }), { status: 200 });
  } catch (err) {
    return new Response(
      JSON.stringify({ sent: false, error: String(err) }),
      { status: 500 }
    );
  }
});
