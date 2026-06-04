// @ts-nocheck — Deno runtime, not Node/TypeScript
import Stripe from 'https://esm.sh/stripe@14.0.0?target=deno'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-06-20',
  httpClient: Stripe.createFetchHttpClient(),
})

Deno.serve(async (req) => {
  const body = await req.text()
  const sig  = req.headers.get('stripe-signature') ?? ''

  let event: Stripe.Event
  try {
    event = await stripe.webhooks.constructEventAsync(
      body, sig, Deno.env.get('STRIPE_WEBHOOK_SECRET')!)
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    console.error('Webhook signature failed:', msg)
    return new Response(`Webhook Error: ${msg}`, { status: 400 })
  }

  if (event.type !== 'checkout.session.completed') {
    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const session = event.data.object as Stripe.Checkout.Session
  const email   = session.customer_details?.email?.toLowerCase()
  if (!email) {
    console.error('No customer email in session')
    return new Response('No email', { status: 400 })
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const { data: { users }, error: listErr } = await sb.auth.admin.listUsers()
  if (listErr) {
    console.error('listUsers error:', listErr.message)
    return new Response('Auth error', { status: 500 })
  }

  const user = users.find((u) => u.email?.toLowerCase() === email)
  if (!user) {
    console.error('No Supabase user found for email:', email)
    return new Response('User not found', { status: 404 })
  }

  const premiumUntil = new Date()
  premiumUntil.setFullYear(premiumUntil.getFullYear() + 1)

  const { error: upsertErr } = await sb.from('profiles').upsert({
    id:            user.id,
    premium_until: premiumUntil.toISOString(),
  })

  if (upsertErr) {
    console.error('profiles upsert error:', upsertErr.message)
    return new Response('DB error', { status: 500 })
  }

  console.log(`Premium granted to ${email} until ${premiumUntil.toISOString()}`)
  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
