import { createServerSupabaseClient } from '@/lib/supabase/server'
import { stripe, STRIPE_PRICE_IDS, ensureStripeCustomer } from '@/lib/stripe'
import { NextRequest, NextResponse } from 'next/server'

// POST /api/billing/checkout — 创建 Stripe Checkout Session
export async function POST(req: NextRequest) {
  const supabase = await createServerSupabaseClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { plan } = await req.json()
  const priceId = STRIPE_PRICE_IDS[plan as string]
  if (!priceId) return NextResponse.json({ error: 'Invalid plan' }, { status: 400 })

  // 检查是否已有有效订阅
  const { data: existingSub } = await supabase
    .from('subscriptions').select('id').eq('user_id', user.id)
    .eq('status', 'active').maybeSingle()

  if (existingSub) {
    return NextResponse.json({ error: '您已有有效订阅，请在账单页面管理' }, { status: 400 })
  }

  const { data: profile } = await supabase
    .from('profiles').select('email, display_name, stripe_customer_id').eq('id', user.id).single()

  const customerId = await ensureStripeCustomer(
    user.id,
    profile?.email ?? user.email!,
    profile?.display_name ?? undefined
  )

  const appUrl = process.env.NEXT_PUBLIC_APP_URL!

  // 创建 Stripe Checkout Session（订阅模式）
  const session = await stripe.checkout.sessions.create({
    customer:               customerId,
    payment_method_types:   ['card'],
    mode:                   'subscription',
    line_items: [{
      price:    priceId,
      quantity: 1,
    }],
    // 订阅成功后跳转至账单页，携带 session_id 供验证
    success_url: `${appUrl}/dashboard/billing?session={CHECKOUT_SESSION_ID}`,
    cancel_url:  `${appUrl}/dashboard/billing?cancelled=1`,
    // metadata 用于 webhook 关联 Supabase 用户
    subscription_data: {
      metadata: {
        supabase_user_id: user.id,
        plan,
      },
    },
    metadata: { supabase_user_id: user.id, plan },
    allow_promotion_codes: true,
    locale: 'auto',
  })

  return NextResponse.json({ url: session.url })
}
