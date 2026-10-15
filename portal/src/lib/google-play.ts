/**
 * Google Play 订阅校验（Play Developer API · purchases.subscriptionsv2）。
 * 与 apple-iap.ts 对称：客户端购买后把 purchaseToken 发来，服务端向 Google 核验、
 * 据真实状态写 subscriptions 表（platform='google_play'）。
 *
 * 依赖环境变量（Vercel）：
 *   GOOGLE_PLAY_SERVICE_ACCOUNT  服务账号 JSON（整段，需有 androidpublisher 权限）
 *   GOOGLE_PLAY_PACKAGE_NAME     可选，默认 com.mirrorspeed.vpn
 */
import { GoogleAuth } from 'google-auth-library'

const PACKAGE = process.env.GOOGLE_PLAY_PACKAGE_NAME || 'com.mirrorspeed.vpn'
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export type GoogleApplyResult =
  | { result: 'applied'; status: string; expires_at: string | null; user_id: string }
  | { result: 'no_user' | 'unknown_product' | 'error'; detail?: string }

let _auth: GoogleAuth | null = null
function auth(): GoogleAuth {
  if (_auth) return _auth
  const raw = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT
  if (!raw) throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT env not set')
  const credentials = JSON.parse(raw)
  _auth = new GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  })
  return _auth
}

/** 向 Play Developer API 查询某 purchaseToken 的订阅状态（subscriptionsv2）。 */
export async function fetchGoogleSubscription(purchaseToken: string): Promise<any> {
  const client = await auth().getClient()
  const at = (await client.getAccessToken()).token
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}` +
    `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${at}` } })
  if (!res.ok) {
    const t = await res.text().catch(() => '')
    throw new Error(`Play API ${res.status}: ${t.slice(0, 300)}`)
  }
  return res.json()
}

// SubscriptionPurchaseV2.subscriptionState → 本地状态 + 是否自动续订
function mapState(state: string | undefined, expiryMs: number, now: number): { status: string; auto: boolean } {
  const live = expiryMs > now
  switch (state) {
    case 'SUBSCRIPTION_STATE_ACTIVE':          return { status: live ? 'active' : 'expired', auto: true }
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD': return { status: live ? 'active' : 'expired', auto: true }
    case 'SUBSCRIPTION_STATE_CANCELED':        return { status: live ? 'active' : 'expired', auto: false } // 已取消但用到期
    case 'SUBSCRIPTION_STATE_ON_HOLD':         return { status: 'past_due', auto: true }
    case 'SUBSCRIPTION_STATE_PAUSED':          return { status: live ? 'active' : 'expired', auto: false }
    default:                                   return { status: live ? 'active' : 'expired', auto: false } // EXPIRED/PENDING/未知
  }
}

/**
 * 核验 Google 购买并写入 subscriptions。幂等（按 store_purchase_token 唯一键 upsert）。
 * 用户归属：登录用户 > obfuscatedExternalAccountId(购买时 setObfuscatedAccountId) > 已有记录。
 */
export async function applyGoogleTransaction(
  admin: any,
  opts: { purchaseToken: string; productId?: string; userId?: string },
): Promise<GoogleApplyResult> {
  const sub = await fetchGoogleSubscription(opts.purchaseToken)

  const line = Array.isArray(sub.lineItems) && sub.lineItems.length ? sub.lineItems[0] : null
  const productId = opts.productId || line?.productId
  if (!productId) return { result: 'unknown_product', detail: 'no productId' }

  const { data: existing } = await admin.from('subscriptions')
    .select('id, user_id, status').eq('store_purchase_token', opts.purchaseToken).maybeSingle()

  const obf = sub.externalAccountIdentifiers?.obfuscatedExternalAccountId as string | undefined
  const userId = opts.userId
    ?? (obf && UUID_RE.test(obf) ? obf.toLowerCase() : undefined)
    ?? existing?.user_id
  if (!userId) return { result: 'no_user' }
  const { data: profile } = await admin.from('profiles').select('id').eq('id', userId).maybeSingle()
  if (!profile) return { result: 'no_user', detail: 'profile not found' }

  const { data: plan } = await admin.from('plans')
    .select('id').eq('google_product_id', productId).maybeSingle()
  if (!plan) return { result: 'unknown_product', detail: productId }

  const now = Date.now()
  const expiryIso: string | null = line?.expiryTime ?? null
  const expiryMs = expiryIso ? Date.parse(expiryIso) : 0
  const { status, auto } = mapState(sub.subscriptionState, expiryMs, now)

  const row: Record<string, any> = {
    user_id: userId,
    plan_id: plan.id,
    status,
    platform: 'google_play',
    expires_at: expiryMs ? new Date(expiryMs).toISOString() : null,
    store_product_id: productId,
    store_purchase_token: opts.purchaseToken,
    store_order_id: sub.latestOrderId ?? null,
    auto_renewing: auto,
    cancel_at_period_end: !auto,
  }

  // 每用户仅一条 active（唯一索引）：激活前停用该用户其它 active 订阅。
  if (status === 'active') {
    let q = admin.from('subscriptions').update({ status: 'cancelled' })
      .eq('user_id', userId).eq('status', 'active')
    if (existing) q = q.neq('id', existing.id)
    await q
  }

  const { error } = existing
    ? await admin.from('subscriptions').update(row).eq('id', existing.id)
    : await admin.from('subscriptions').insert({
        ...row,
        started_at: new Date(sub.startTime ? Date.parse(sub.startTime) : now).toISOString(),
      })
  if (error) return { result: 'error', detail: error.message }

  return { result: 'applied', status, expires_at: row.expires_at, user_id: userId }
}
