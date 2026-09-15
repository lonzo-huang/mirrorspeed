import { createAdminClient } from '@/lib/supabase/server'
import { isTransactionActive, type AppleTransaction } from '@/lib/apple-iap'

/**
 * 把一笔已验签的苹果交易落库。
 * 幂等：以 apple_original_transaction_id 为唯一键，续订/重复投递只更新到期时间。
 */
export async function applyTransaction(
  admin: ReturnType<typeof createAdminClient>,
  userId: string,
  txn: AppleTransaction,
) {
  const { data: plan } = await admin
    .from('plans')
    .select('id')
    .eq('apple_product_id', txn.productId)
    .maybeSingle()
  if (!plan) throw new Error(`unknown apple product: ${txn.productId}`)

  const active = isTransactionActive(txn)
  const status = active ? 'active' : (txn.revocationDate ? 'cancelled' : 'expired')
  const expiresAt = txn.expiresDate ? new Date(txn.expiresDate).toISOString() : null

  const { data: existing } = await admin
    .from('subscriptions')
    .select('id')
    .eq('apple_original_transaction_id', txn.originalTransactionId)
    .maybeSingle()

  if (existing) {
    await admin.from('subscriptions').update({
      user_id:    userId,
      plan_id:    plan.id,
      status,
      expires_at: expiresAt,
      store_product_id: txn.productId,
      store_order_id:   txn.transactionId,
      auto_renewing:    active,
      updated_at: new Date().toISOString(),
    }).eq('id', existing.id)
    return
  }

  // 同一用户可能已有一条其它来源(Stripe/Google)的 active 订阅：
  // subscriptions_one_active_per_user 唯一索引只允许一条 active，先把旧的置为 cancelled。
  if (active) {
    await admin.from('subscriptions')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('user_id', userId).eq('status', 'active')
  }

  await admin.from('subscriptions').insert({
    user_id:    userId,
    plan_id:    plan.id,
    status,
    currency:   'usd',
    started_at: new Date(txn.originalPurchaseDate ?? txn.purchaseDate).toISOString(),
    expires_at: expiresAt,
    platform:   'apple',
    store_product_id: txn.productId,
    store_order_id:   txn.transactionId,
    apple_original_transaction_id: txn.originalTransactionId,
    auto_renewing: active,
  })
}
