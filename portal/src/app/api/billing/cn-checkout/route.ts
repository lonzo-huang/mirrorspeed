import { createServerSupabaseClient, createAdminClient } from '@/lib/supabase/server'
import { stripe, ensureStripeCustomer } from '@/lib/stripe'
import { NextRequest, NextResponse } from 'next/server'

// CNY amounts in fen (cents) for each plan
const CNY_AMOUNTS: Record<string, number> = {
  monthly:   2400,   // ¥24
  quarterly: 3600,   // ¥36
  yearly:    9600,   // ¥96
  biennial:  16800,  // ¥168
}

// POST /api/billing/cn-checkout — Alipay / WeChat Pay (one-time, CNY)
export async function POST(req: NextRequest) {
  try {
    const supabase = await createServerSupabaseClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const body   = await req.json()
    const plan   = body.plan as string
    const method = body.method as 'alipay' | 'wechat_pay'

    if (!CNY_AMOUNTS[plan]) {
      return NextResponse.json({ error: `Invalid plan "${plan}"` }, { status: 400 })
    }
    if (method !== 'alipay' && method !== 'wechat_pay') {
      return NextResponse.json({ error: 'method must be alipay or wechat_pay' }, { status: 400 })
    }

    // Check existing active subscription
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

    const appUrl = (process.env.NEXT_PUBLIC_APP_URL ?? req.nextUrl.origin).replace(/\/$/, '')
    const amount = CNY_AMOUNTS[plan]

    // WeChat Pay requires a special wechat_pay_params object
    const paymentMethodOptions: Record<string, any> = {}
    if (method === 'wechat_pay') {
      paymentMethodOptions.wechat_pay = { client: 'web' }
    }

    const session = await stripe.checkout.sessions.create({
      customer:             customerId,
      payment_method_types: [method],
      payment_method_options: Object.keys(paymentMethodOptions).length > 0
        ? paymentMethodOptions : undefined,
      mode:                 'payment',
      line_items: [{
        price_data: {
          currency:     'cny',
          unit_amount:  amount,
          product_data: {
            name:        `MirrorSpeed ${plan.charAt(0).toUpperCase() + plan.slice(1)} Plan`,
            description: `One-time activation for ${plan} subscription`,
          },
        },
        quantity: 1,
      }],
      success_url: `${appUrl}/dashboard/billing?session={CHECKOUT_SESSION_ID}`,
      cancel_url:  `${appUrl}/dashboard/billing?cancelled=1`,
      payment_intent_data: {
        metadata: {
          supabase_user_id: user.id,
          plan,
          payment_type: 'cn_onetime',
        },
      },
      metadata: { supabase_user_id: user.id, plan, payment_type: 'cn_onetime' },
      locale: 'zh',
    })

    return NextResponse.json({ url: session.url })

  } catch (err: any) {
    console.error('[cn-checkout] error:', err)
    return NextResponse.json(
      { error: err?.message ?? String(err) },
      { status: 500 }
    )
  }
}
