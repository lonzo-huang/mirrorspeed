'use server'

import { createServerSupabaseClient } from '@/lib/supabase/server'
import { stripe, STRIPE_PRICE_IDS, ensureStripeCustomer } from '@/lib/stripe'

const PLAN_PRICE_MAP: Record<string, string | undefined> = {
  monthly:  process.env.STRIPE_PRICE_MONTHLY,
  yearly:   process.env.STRIPE_PRICE_YEARLY,
  biennial: process.env.STRIPE_PRICE_BIENNIAL,
}

export async function createCheckoutSession(plan: string, origin: string): Promise<{ url: string | null; error?: string }> {
  const supabase = await createServerSupabaseClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { url: null, error: 'Unauthorized' }

  const priceId = PLAN_PRICE_MAP[plan]
  if (!priceId || priceId.startsWith('price_placeholder')) {
    return { url: null, error: 'DEMO_MODE' }
  }

  const { data: existingSub } = await supabase
    .from('subscriptions').select('id').eq('user_id', user.id)
    .eq('status', 'active').maybeSingle()
  if (existingSub) return { url: null, error: 'Already subscribed' }

  const { data: profile } = await supabase
    .from('profiles').select('email, display_name').eq('id', user.id).single()

  const customerId = await ensureStripeCustomer(
    user.id,
    profile?.email ?? user.email!,
    profile?.display_name ?? undefined
  )

  const session = await stripe.checkout.sessions.create({
    customer: customerId,
    payment_method_types: ['card'],
    mode: 'subscription',
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${origin}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${origin}/pricing`,
    metadata: { supabase_user_id: user.id, plan },
    subscription_data: { metadata: { supabase_user_id: user.id } },
    allow_promotion_codes: true,
  })

  return { url: session.url }
}
