/*
 * Payments scaffold: NOT a working payment integration.
 *
 * Right now, "Card" is just a label the customer picks so the counter
 * knows to bring the card reader over, exactly like "Cash". No money
 * moves through this file yet. It exists so that when you're ready to
 * take real online card payments, there is one obvious place to wire
 * it up instead of hunting through order/index.html.
 *
 * Tip already works today, independent of this file: the customer picks
 * a tip percentage or a custom amount, it's added to the total, and it's
 * stored on the order (see the `tip` column in supabase/schema.sql). All
 * that's missing for online payments is actually charging a card for
 * that total instead of collecting cash/card in person.
 *
 * -------------------------------------------------------------------
 * HOW TO WIRE UP A REAL PROCESSOR (Stripe is the easiest fit here)
 * -------------------------------------------------------------------
 *
 * 1. Create a Stripe account, get a publishable key (safe for the
 *    frontend, like the Supabase anon key) and a secret key (never put
 *    this in frontend code).
 *
 * 2. You need ONE small server-side endpoint, because creating a
 *    PaymentIntent requires the secret key. A Supabase Edge Function is
 *    the natural fit here since you already have a Supabase project:
 *      supabase/functions/create-payment-intent/index.ts
 *    It would receive { amount, orderId } and return a `client_secret`
 *    using the Stripe secret key (set as a Supabase Function secret,
 *    never committed to this repo).
 *
 * 3. In this file, implement createPaymentIntent() below to call that
 *    Edge Function, then use Stripe.js (loaded via a <script> tag, like
 *    the Supabase client already is) to confirm the card payment with
 *    the returned client_secret.
 *
 * 4. On success, update the order's paymentStatus to 'paid' and store
 *    the Stripe paymentIntentId (both columns already exist in
 *    supabase/schema.sql) before calling submitOrder(), or as a
 *    follow-up update right after.
 *
 * 5. Only take the order off "Card" and treat it as prepaid once step 4
 *    confirms success, not just because the customer picked "Card" as
 *    the button — that's the difference between "card, pay in person"
 *    (today's behavior) and "card, already paid" (the goal).
 *
 * None of the functions below do anything real yet, they throw so a
 * half-wired call fails loudly instead of silently pretending to charge
 * a card.
 */

/* Call this once, near the top of order/index.html, once you've added
   Stripe.js: <script src="https://js.stripe.com/v3/"></script>
   and set STRIPE_PUBLISHABLE_KEY below (mirrors supabase-config.js). */
window.STRIPE_PUBLISHABLE_KEY = '';

async function createPaymentIntent(amountInCents, orderMeta){
  throw new Error(
    'createPaymentIntent() is not implemented yet. See order/payments.js ' +
    'for the steps to wire up Stripe (or another processor).'
  );
}

async function confirmCardPayment(clientSecret, cardElement){
  throw new Error(
    'confirmCardPayment() is not implemented yet. See order/payments.js.'
  );
}

/* Small helper other code can check without importing Stripe: is online
   card payment actually configured, or should the UI keep behaving the
   way it does today (card = pay in person)? */
function paymentsConfigured(){
  return !!window.STRIPE_PUBLISHABLE_KEY;
}
