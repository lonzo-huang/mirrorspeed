import Stripe from 'stripe'

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-06-20',
  typescript: true,
})

// 货币对应的 Stripe Price ID（在 .env 中配置）
export const STRIPE_PRICE_IDS: Record<string, string> = {
  usd: process.env.STRIPE_PRICE_USD!,
  eur: process.env.STRIPE_PRICE_EUR!,
  cny: process.env.STRIPE_PRICE_CNY!,
}

// 确保 Stripe Customer 存在，返回 customer ID
export async function ensureStripeCustomer(userId: string, email: string, name?: string): Promise<string> {
  const { createAdminClient } = await import('@/lib/supabase/server')
  const admin = createAdminClient()

  // 从数据库读取已有 customer ID
  const { data: profile } = await admin
    .from('profiles').select('stripe_customer_id').eq('id', userId).single()

  if (profile?.stripe_customer_id) return profile.stripe_customer_id

  // 在 Stripe 创建新 Customer（metadata 保存 Supabase user ID 用于 webhook 关联）
  const customer = await stripe.customers.create({
    email,
    name: name ?? email,
    metadata: { supabase_user_id: userId },
  })

  // 写回数据库
  await admin.from('profiles')
    .update({ stripe_customer_id: customer.id })
    .eq('id', userId)

  return customer.id
}
