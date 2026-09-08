// Stripe webhook handler: NOT wired to a real Stripe account yet.
//
// This is "provider webhook as payment truth" in code: the ONLY place
// an order's paymentStatus ever becomes 'paid'. Not the browser after
// Stripe.js reports success client-side (a closed tab, a network drop,
// or a customer lying to their own browser's dev tools could all fake
// that), not create-payment-intent (that only ever starts a payment,
// never confirms one) -- only a signed, verified event delivered
// server-to-server directly from Stripe.
//
// See supabase/functions/create-payment-intent/index.ts for the full
// flow this is one step of, and its "HOW TO FINISH THIS" section for
// the setup steps (Stripe account, secrets, CLI deploy, webhook
// registration) -- both functions are finished together.

async function verifyStripeSignature(
  payload: string,
  signatureHeader: string | null,
  webhookSecret: string,
): Promise<boolean> {
  throw new Error(
    "verifyStripeSignature() is not implemented yet. See " +
      "supabase/functions/create-payment-intent/index.ts for the Stripe setup steps. " +
      "Use Stripe's own SDK (constructEvent) or the raw HMAC-SHA256 scheme documented at " +
      "https://stripe.com/docs/webhooks/signatures -- never skip verification, an unverified " +
      "webhook is an open door for anyone to mark any order 'paid' for free."
  );
}

Deno.serve(async (req: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !webhookSecret) {
    return new Response("Payments are not configured on this server yet.", { status: 501 });
  }

  const payload = await req.text();
  const signature = req.headers.get("stripe-signature");

  let verified = false;
  try {
    verified = await verifyStripeSignature(payload, signature, webhookSecret);
  } catch (err) {
    console.error("Webhook signature verification not implemented or failed:", err);
    return new Response("Webhook not configured", { status: 501 });
  }
  if (!verified) {
    // Deliberately generic -- never tell a caller *why* verification
    // failed, that just helps someone iterate toward a forged signature.
    return new Response("Invalid signature", { status: 400 });
  }

  const event = JSON.parse(payload);
  const intent = event?.data?.object;
  const paymentIntentId = intent?.id;
  if (!paymentIntentId) {
    return new Response(JSON.stringify({ received: true, skipped: "no payment intent id" }), { status: 200 });
  }

  let newStatus: "paid" | "failed" | null = null;
  if (event.type === "payment_intent.succeeded") newStatus = "paid";
  else if (event.type === "payment_intent.payment_failed") newStatus = "failed";
  if (!newStatus) {
    // Any other event type Stripe might send to this same endpoint --
    // acknowledge it so Stripe doesn't retry, just don't act on it.
    return new Response(JSON.stringify({ received: true, skipped: event.type }), { status: 200 });
  }

  const patchRes = await fetch(
    `${supabaseUrl}/rest/v1/orders?paymentIntentId=eq.${encodeURIComponent(paymentIntentId)}`,
    {
      method: "PATCH",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ paymentStatus: newStatus }),
    },
  );

  if (!patchRes.ok) {
    console.error("Could not update order payment status:", await patchRes.text());
    // 500 so Stripe retries this delivery -- a failed write here should
    // not silently leave an order's payment status wrong forever.
    return new Response("Could not update order", { status: 500 });
  }

  return new Response(JSON.stringify({ received: true, paymentStatus: newStatus }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
