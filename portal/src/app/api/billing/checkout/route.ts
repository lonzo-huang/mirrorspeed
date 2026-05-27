import { createServerSupabaseClient } from '@/lib/supabase/server'
import { stripe, STRIPE_PRICE_IDS, ensureStripeCustomer } from '@/lib/stripe'
import { NextRequest, NextResponse } from 'next/server'

// POST /api/billing/checkout — 创建 Stripe Checkout Session
export async function POST(req: NextRequest) {
  try {
    const supabase = await createServerSupabaseClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const body = await req.json()
    const plan = body.plan as string
    const priceId = STRIPE_PRICE_IDS[plan]

    if (!priceId) {
      return NextResponse.json(
        { error: `Invalid plan "${plan}". Check STRIPE_PRICE_* env vars in Vercel.` },
        { status: 400 }
      )
    }

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
      (profile as any)?.email ?? user.email!,
      (profile as any)?.display_name ?? undefined
    )

    // 优先用环境变量，否则从请求 Origin 推导
    const appUrl = (process.env.NEXT_PUBLIC_APP_URL ?? req.nextUrl.origin).replace(/\/$/, '')

    const session = await stripe.checkout.sessions.create({
      customer:             customerId,
      automatic_payment_methods: { enabled: true },
      mode:                      'subscription',
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: `${appUrl}/dashboard/billing?session={CHECKOUT_SESSION_ID}`,
      cancel_url:  `${appUrl}/dashboard/billing?cancelled=1`,
      subscription_data: {
        metadata: { supabase_user_id: user.id, plan },
      },
      metadata: { supabase_user_id: user.id, plan },
      allow_promotion_codes: true,
      locale: 'auto',
    })

    return NextResponse.json({ url: session.url })

  } catch (err: any) {
    console.error('[checkout] error:', err)
    return NextResponse.json(
      { error: err?.message ?? String(err) },
      { status: 500 }
    )
  }
}
