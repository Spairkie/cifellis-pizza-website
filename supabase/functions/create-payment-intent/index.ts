// Payment intent creation: NOT wired to a real Stripe account yet.
//
// The one piece of real payments that has to happen server-side (a
// Stripe secret key can never go in frontend code) -- this Edge
// Function is the only thing that ever tells Stripe how much to
// charge, and it always computes that amount itself from the order
// already sitting in the database. It never trusts a client-supplied
// amount, for the exact same reason create_order() (supabase/
// schema.sql) never trusts a client-supplied price: the amount charged
// must always come from something the server itself computed.
//
// -----------------------------------------------------------------
// HOW THIS FITS TOGETHER (the full online-payment flow, once wired up)
// -----------------------------------------------------------------
//
//   1. Customer checks out normally through create_order() (order/
//      index.html) -- completely unchanged. The order exists with
//      paymentStatus 'unpaid' before any payment conversation starts,
//      same as a "pay in person" card order today.
//   2. If the customer chooses to pay online right now (a checkout
//      option that only appears once paymentsConfigured() is true --
//      see order/payments.js), the client calls THIS function with
//      only the orderId. Nothing else -- no amount, no card details.
//   3. This function looks up that order's real `total` from the
//      database, creates a Stripe PaymentIntent for exactly that
//      amount, records the PaymentIntent id on the order (paymentProvider
//      + paymentIntentId, both columns already exist in
//      supabase/schema.sql), and returns the PaymentIntent's
//      client_secret to the browser.
//   4. The browser uses Stripe.js + that client_secret to collect card
//      details and confirm the payment directly with Stripe -- the
//      card number itself never touches this backend at all.
//   5. Stripe calls supabase/functions/stripe-webhook/ (a separate
//      function, see that file) when the charge actually succeeds or
//      fails. That webhook -- not this function, not the browser -- is
//      the only thing that ever marks the order paymentStatus 'paid'.
//      "Provider webhook as payment truth": the client declaring
//      success on its own is never good enough.
//
// -----------------------------------------------------------------
// HOW TO FINISH THIS
// -----------------------------------------------------------------
//
// 1. Create a Stripe account, get your secret key (Dashboard >
//    Developers > API keys -- the "Secret key", not the publishable
//    one, which goes in order/payments.js instead, safe for the
//    frontend the same way the Supabase anon key is).
//
// 2. Install the Supabase CLI and deploy both payment functions:
//      supabase functions deploy create-payment-intent
//      supabase functions deploy stripe-webhook
//    Set secrets (never commit these):
//      supabase secrets set STRIPE_SECRET_KEY=sk_live_...
//      supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...  (from step 4)
//      supabase secrets set SUPABASE_SERVICE_ROLE_KEY=...    (Project Settings > API)
//
// 3. Fill in createStripePaymentIntent() below with a real fetch() to
//    Stripe's API (https://stripe.com/docs/api/payment_intents/create)
//    -- or use the official Stripe Deno SDK
//    (https://github.com/stripe/stripe-node works via npm: specifiers
//    in Deno) if you'd rather not hand-rolled the HTTP call.
//
// 4. In the Stripe Dashboard, add a webhook endpoint pointing at this
//    project's stripe-webhook function URL, subscribed to at least
//    payment_intent.succeeded and payment_intent.payment_failed. Stripe
//    gives you the signing secret for STRIPE_WEBHOOK_SECRET above at
//    that point.
//
// 5. Set window.STRIPE_PUBLISHABLE_KEY in order/payments.js and load
//    Stripe.js in order/index.html (both already documented there).
//
// Until all of this is done, callers get a clear thrown error instead
// of a half-wired call that silently pretends to charge a card.

interface CreateIntentRequest {
  orderId: string;
}

async function createStripePaymentIntent(
  amountInCents: number,
  currency: string,
  metadata: Record<string, string>,
): Promise<{ id: string; client_secret: string }> {
  throw new Error(
    "createStripePaymentIntent() is not implemented yet. See " +
      "supabase/functions/create-payment-intent/index.ts for the Stripe setup steps."
  );
}

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { orderId } = (await req.json()) as CreateIntentRequest;
    if (!orderId) {
      return new Response(JSON.stringify({ error: "orderId is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Payments are not configured on this server yet." }),
        { status: 501, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Service-role read: bypasses RLS deliberately (same reasoning as
    // every security-definer function in supabase/schema.sql) -- this
    // needs to see the order regardless of who's asking, but only ever
    // reads the fields below, never anything the caller sends.
    const orderRes = await fetch(
      `${supabaseUrl}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}&select=id,ticket,total,paymentStatus,paymentProvider`,
      {
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
        },
      },
    );
    const orders = await orderRes.json();
    const order = Array.isArray(orders) ? orders[0] : null;
    if (!order) {
      return new Response(JSON.stringify({ error: "Order not found." }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (order.paymentStatus === "paid") {
      return new Response(JSON.stringify({ error: "This order has already been paid." }), {
        status: 409,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // The only amount that ever reaches Stripe -- computed here, from
    // the order create_order() already priced authoritatively, never
    // from anything this request itself supplied.
    const amountInCents = Math.round(Number(order.total) * 100);
    const intent = await createStripePaymentIntent(amountInCents, "usd", {
      orderId: order.id,
      ticket: order.ticket,
    });

    // Record the PaymentIntent on the order immediately (service-role
    // write, same trust level as the read above) so the webhook can
    // find its way back to this order later by paymentIntentId alone.
    await fetch(`${supabaseUrl}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
      method: "PATCH",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ paymentProvider: "stripe", paymentIntentId: intent.id }),
    });

    return new Response(JSON.stringify({ clientSecret: intent.client_secret }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err && (err as Error).message || err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
