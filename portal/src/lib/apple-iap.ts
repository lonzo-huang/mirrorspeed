/**
 * Apple App Store 内购（自动续期订阅）服务端逻辑。
 *
 * - 签名校验：官方 @apple/app-store-server-library + 内嵌 Apple Root CA - G3，
 *   校验证书链 + ES256 签名 + bundleId/appAppleId，杜绝伪造通知/收据。
 * - 环境：先按 Production 校验，INVALID_ENVIRONMENT 时回退 Sandbox
 *   （App 审核员用沙盒账号购买，但请求打到生产服务器，两者都必须接受）。
 * - 落库：subscriptions(platform='apple')，以 originalTransactionId 为唯一键。
 *
 * 环境变量：
 *   APPLE_BUNDLE_ID        默认 com.mirrorspeed.mirrorspeedVpn
 *   APPLE_APP_ID           App Store Connect 里的数字 Apple ID（生产环境校验必需）
 *   APPLE_IAP_KEY_ID       App Store Connect API 内购密钥 Key ID（/verify 用 transactionId 查询时需要）
 *   APPLE_IAP_ISSUER_ID    Issuer ID
 *   APPLE_IAP_PRIVATE_KEY  .p8 私钥全文（可用 \n 表示换行）
 */
import {
  AppStoreServerAPIClient, APIException, Environment,
  SignedDataVerifier, VerificationException, VerificationStatus,
  type JWSTransactionDecodedPayload,
} from '@apple/app-store-server-library'

// Apple Root CA - G3（DER，base64）。SHA-256 指纹：
// 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
const APPLE_ROOT_CA_G3 =
  'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA=='

export const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID || 'com.mirrorspeed.mirrorspeedVpn'

const ROOTS = [Buffer.from(APPLE_ROOT_CA_G3, 'base64')]
const APP_APPLE_ID = process.env.APPLE_APP_ID ? Number(process.env.APPLE_APP_ID) : undefined

let _prod: SignedDataVerifier | null = null
let _sandbox: SignedDataVerifier | null = null

function verifier(env: Environment): SignedDataVerifier {
  if (env === Environment.PRODUCTION) {
    if (!APP_APPLE_ID) throw new Error('APPLE_APP_ID not configured')
    return (_prod ??= new SignedDataVerifier(ROOTS, true, Environment.PRODUCTION, APPLE_BUNDLE_ID, APP_APPLE_ID))
  }
  return (_sandbox ??= new SignedDataVerifier(ROOTS, true, Environment.SANDBOX, APPLE_BUNDLE_ID))
}

/** 先生产后沙盒：仅当生产环境报 INVALID_ENVIRONMENT（或生产未配置）时回退沙盒。 */
async function withEnvFallback<T>(fn: (v: SignedDataVerifier) => Promise<T>): Promise<T> {
  if (APP_APPLE_ID) {
    try {
      return await fn(verifier(Environment.PRODUCTION))
    } catch (e) {
      if (!(e instanceof VerificationException && e.status === VerificationStatus.INVALID_ENVIRONMENT)) throw e
    }
  }
  return fn(verifier(Environment.SANDBOX))
}

export const decodeNotification = (signedPayload: string) =>
  withEnvFallback(v => v.verifyAndDecodeNotification(signedPayload))
export const decodeTransaction = (signed: string) =>
  withEnvFallback(v => v.verifyAndDecodeTransaction(signed))
export const decodeRenewalInfo = (signed: string) =>
  withEnvFallback(v => v.verifyAndDecodeRenewalInfo(signed))

/** 用 transactionId 向 App Store Server API 查询已签名交易（先生产，404 回退沙盒）。 */
export async function fetchSignedTransaction(transactionId: string): Promise<string> {
  const keyId = process.env.APPLE_IAP_KEY_ID
  const issuerId = process.env.APPLE_IAP_ISSUER_ID
  const key = process.env.APPLE_IAP_PRIVATE_KEY?.replace(/\\n/g, '\n')
  if (!keyId || !issuerId || !key) throw new Error('App Store Server API key not configured')

  for (const env of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      const client = new AppStoreServerAPIClient(key, keyId, issuerId, APPLE_BUNDLE_ID, env)
      const res = await client.getTransactionInfo(transactionId)
      if (res.signedTransactionInfo) return res.signedTransactionInfo
    } catch (e) {
      if (e instanceof APIException && e.httpStatusCode === 404) continue
      throw e
    }
  }
  throw new Error('transaction not found')
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export type ApplyResult =
  | { result: 'applied'; status: string; expires_at: string | null; user_id: string }
  | { result: 'no_user' | 'unknown_product' | 'wrong_bundle' | 'error'; detail?: string }

/**
 * 把一笔已验证的苹果交易落到 subscriptions。
 * @param opts.userId       已登录用户（/verify 场景）；通知场景用 appAccountToken 或已有记录反查
 * @param opts.autoRenewing 来自续订信息
 * @param opts.graceUntil   计费宽限期截止（ms），期内视为有效
 * @param opts.billingRetry 进入扣费重试（无宽限期）→ past_due
 */
export async function applyAppleTransaction(
  admin: any,
  txn: JWSTransactionDecodedPayload,
  opts: { userId?: string; autoRenewing?: boolean; graceUntil?: number; billingRetry?: boolean } = {},
): Promise<ApplyResult> {
  if (txn.bundleId && txn.bundleId !== APPLE_BUNDLE_ID) return { result: 'wrong_bundle', detail: txn.bundleId }
  const otid = txn.originalTransactionId
  if (!otid) return { result: 'error', detail: 'no originalTransactionId' }

  const { data: existing } = await admin.from('subscriptions')
    .select('id, user_id, status').eq('store_purchase_token', otid).maybeSingle()

  // 用户归属：登录用户 > appAccountToken(客户端购买时传入 user id) > 已有记录
  let userId = opts.userId
    ?? (txn.appAccountToken && UUID_RE.test(txn.appAccountToken) ? txn.appAccountToken.toLowerCase() : undefined)
    ?? existing?.user_id
  if (!userId) return { result: 'no_user' }
  const { data: profile } = await admin.from('profiles').select('id').eq('id', userId).maybeSingle()
  if (!profile) return { result: 'no_user', detail: 'profile not found' }

  const { data: plan } = await admin.from('plans')
    .select('id').eq('apple_product_id', txn.productId ?? '').maybeSingle()
  if (!plan) return { result: 'unknown_product', detail: txn.productId }

  // 状态判定
  const now = Date.now()
  const effectiveExpiry = Math.max(txn.expiresDate ?? 0, opts.graceUntil ?? 0)
  let status: string
  if (txn.revocationDate) status = 'cancelled'                 // 退款 / 撤销
  else if (effectiveExpiry > now) status = 'active'
  else if (opts.billingRetry) status = 'past_due'
  else status = 'expired'

  const cur = (txn.currency ?? '').toLowerCase()
  const row: Record<string, any> = {
    user_id: userId,
    plan_id: plan.id,
    status,
    platform: 'apple',
    currency: ['usd', 'eur', 'cny'].includes(cur) ? cur : 'usd',
    amount_paid_cents: typeof txn.price === 'number' ? Math.round(txn.price / 10) : null,  // milliunits → cents
    expires_at: effectiveExpiry ? new Date(effectiveExpiry).toISOString() : null,
    store_product_id: txn.productId,
    store_purchase_token: otid,
    store_order_id: txn.transactionId,
    cancel_at_period_end: opts.autoRenewing === false,
  }
  if (typeof opts.autoRenewing === 'boolean') row.auto_renewing = opts.autoRenewing

  // 每用户仅一条 active（唯一索引）：激活苹果订阅前，停用该用户其它 active 订阅
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
        started_at: new Date(txn.originalPurchaseDate ?? txn.purchaseDate ?? now).toISOString(),
      })
  if (error) return { result: 'error', detail: error.message }

  return { result: 'applied', status, expires_at: row.expires_at, user_id: userId }
}
