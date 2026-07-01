import Stripe from 'stripe'

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-06-20',
  typescript: true,
})

// 四个套餐对应的 Stripe Price ID（在 Vercel 环境变量中配置）
// 价格均以 USD 结算，页面对中国区用户显示人民币等价金额
export const STRIPE_PRICE_IDS: Record<string, string> = {
  yearly:    process.env.STRIPE_PRICE_YEARLY!,    // $12/yr  → $1/mo
  biennial:  process.env.STRIPE_PRICE_BIENNIAL!,  // $21.60/2yr → $0.90/mo
  halfyear:  process.env.STRIPE_PRICE_HALFYEAR!,  // 半年循环 Price（需在 Stripe 新建后配置此环境变量）
  monthly:   process.env.STRIPE_PRICE_MONTHLY!,   // $3/mo
  quarterly: process.env.STRIPE_PRICE_QUARTERLY!, // $4.50/qtr → $1.50/mo
}

// 确保 Stripe Customer 存在，返回 customer ID
export async function ensureStripeCustomer(userId: string, email: string, name?: string): Promise<string> {
  const { createAdminClient } = await import('@/lib/supabase/server')
  const admin = createAdminClient()

  const { data: profile } = await admin
    .from('profiles').select('stripe_customer_id').eq('id', userId).single()

  if (profile?.stripe_customer_id) return profile.stripe_customer_id

  const customer = await stripe.customers.create({
    email,
    name: name ?? email,
    metadata: { supabase_user_id: userId },
  })

  await admin.from('profiles')
    .update({ stripe_customer_id: customer.id })
    .eq('id', userId)

  return customer.id
}
