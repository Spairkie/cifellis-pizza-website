/*
 * Payments: the client-side half of online card payment. Inert until
 * configured -- "Card" stays exactly what it is today (a label meaning
 * "bring the card reader to the counter") until window.STRIPE_
 * PUBLISHABLE_KEY is actually set and Stripe.js is actually loaded.
 * paymentsConfigured() is the one thing the rest of the app checks
 * before ever showing a "Pay Now" option.
 *
 * Tip already works today, independent of this file: the customer picks
 * a tip percentage or a custom amount, it's added to the total, and
 * it's stored on the order (see the `tip` column in supabase/
 * schema.sql). All that was ever missing for online payments was
 * actually charging a card for that total instead of collecting cash/
 * card in person -- this file plus the two Edge Functions below are
 * that piece.
 *
 * -------------------------------------------------------------------
 * THE FULL FLOW (server-authoritative amount, webhook as payment truth)
 * -------------------------------------------------------------------
 *
 *   1. Customer checks out normally through create_order() (order/
 *      index.html) -- completely unchanged, and always happens FIRST.
 *      The order exists with paymentStatus 'unpaid' before any payment
 *      conversation starts, same as "pay in person" today.
 *   2. payForOrderNow() below calls create-payment-intent (a Supabase
 *      Edge Function, supabase/functions/create-payment-intent/) with
 *      only the orderId -- that function looks up the order's real
 *      `total` itself and creates a Stripe PaymentIntent for exactly
 *      that amount. This file never computes or sends an amount.
 *   3. Stripe.js confirms the card payment client-side with the
 *      returned client_secret. The card number itself never touches
 *      this site's own backend.
 *   4. Stripe calls supabase/functions/stripe-webhook/ server-to-server
 *      when the charge actually succeeds or fails -- THAT webhook, not
 *      this file and not the browser, is the only thing that ever marks
 *      the order paymentStatus 'paid'. A success returned to this file
 *      means "the card was charged," not "the database already shows
 *      it" -- there's a real (usually sub-second) gap between the two
 *      worth the UI accounting for (e.g. "payment received, finishing
 *      up...") rather than assuming instant consistency.
 *
 * -------------------------------------------------------------------
 * HOW TO FINISH THIS (Stripe is the easiest fit here)
 * -------------------------------------------------------------------
 *
 * 1. Create a Stripe account, get a publishable key (Dashboard >
 *    Developers > API keys) -- safe for frontend code, like the
 *    Supabase anon key. Set it below.
 *
 * 2. Load Stripe.js in order/index.html, near where supabase-js already
 *    loads: <script src="https://js.stripe.com/v3/"></script>
 *
 * 3. Finish both Edge Functions -- supabase/functions/
 *    create-payment-intent/index.ts and supabase/functions/
 *    stripe-webhook/index.ts -- each has its own "HOW TO FINISH THIS"
 *    with the Stripe secret key / webhook secret / deploy steps.
 *
 * 4. Add a "Pay Now" UI option to checkout, shown only when
 *    paymentsConfigured() is true, that calls payForOrderNow() with the
 *    orderId create_order() just returned and a Stripe Elements card
 *    field. Deliberately not built yet -- there's no way to test it
 *    without real Stripe keys, and a half-tested payment UI is worse
 *    than no payment UI.
 */

window.STRIPE_PUBLISHABLE_KEY = '';

let _stripeClient = null;
function getStripeClient(){
  if (!window.STRIPE_PUBLISHABLE_KEY || typeof Stripe === 'undefined') return null;
  if (!_stripeClient) _stripeClient = Stripe(window.STRIPE_PUBLISHABLE_KEY);
  return _stripeClient;
}

/* Checked before ever showing a "Pay Now" option instead of today's
   "card = pay in person" behavior. Requires both a real publishable key
   AND Stripe.js actually loaded -- either alone isn't enough to
   actually take a payment. */
function paymentsConfigured(){
  return !!(window.STRIPE_PUBLISHABLE_KEY && typeof Stripe !== 'undefined');
}

async function createPaymentIntent(orderId){
  if (!paymentsConfigured()){
    throw new Error('Online card payment is not set up yet -- see order/payments.js.');
  }
  if (!window.SUPABASE_URL || !window.SUPABASE_ANON_KEY){
    throw new Error('Not connected to the database.');
  }
  const res = await fetch(`${window.SUPABASE_URL}/functions/v1/create-payment-intent`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: window.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${window.SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify({ orderId }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok){
    throw new Error(data.error || `Could not start payment (${res.status}).`);
  }
  return data.clientSecret;
}

async function confirmCardPayment(clientSecret, cardElement){
  const stripe = getStripeClient();
  if (!stripe) throw new Error('Stripe.js is not loaded.');
  const result = await stripe.confirmCardPayment(clientSecret, {
    payment_method: { card: cardElement },
  });
  if (result.error){
    throw new Error(result.error.message || 'Payment failed.');
  }
  return result.paymentIntent;
}

/* The whole "pay now" flow in one call: start the PaymentIntent (server
   computes the real amount), confirm it with Stripe.js. Doesn't touch
   the order's paymentStatus itself -- see "THE FULL FLOW" above for why
   that's the webhook's job, not this function's. */
async function payForOrderNow(orderId, cardElement){
  const clientSecret = await createPaymentIntent(orderId);
  return confirmCardPayment(clientSecret, cardElement);
}
