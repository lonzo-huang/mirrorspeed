/**
 * POST /api/iap/apple/notifications
 * App Store Server Notifications V2 接收端（App Store Connect 里填写此 URL，生产/沙盒同一个）。
 *
 * 苹果推送 { signedPayload }（JWS）。流程：校验签名 → 按 notificationUUID 去重 →
 * 解码交易与续订信息 → 更新 subscriptions。
 *   SUBSCRIBED / DID_RENEW / OFFER_REDEEMED  → active（按 expiresDate）
 *   DID_FAIL_TO_RENEW                        → 宽限期内仍 active，否则 past_due
 *   EXPIRED / GRACE_PERIOD_EXPIRED           → expired
 *   REFUND / REVOKE                          → cancelled（revocationDate）
 *   DID_CHANGE_RENEWAL_STATUS                → 更新 auto_renewing
 *   TEST                                     → 仅记录
 * 返回 200 表示已处理；非 200 苹果会重试（数据库故障时返回 500 以便重试）。
 */
import { NextRequest, NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/server'
import { applyAppleTransaction, decodeNotification, decodeRenewalInfo, decodeTransaction } from '@/lib/apple-iap'

export const dynamic = 'force-dynamic'
export const runtime = 'nodejs'

export async function POST(req: NextRequest) {
  let signedPayload: string | undefined
  try { signedPayload = (await req.json())?.signedPayload } catch { /* fallthrough */ }
  if (!signedPayload) return NextResponse.json({ error: 'signedPayload required' }, { status: 400 })

  // 1) 校验签名（伪造/篡改的请求在这里被拒绝）
  let n: Awaited<ReturnType<typeof decodeNotification>>
  try {
    n = await decodeNotification(signedPayload)
  } catch (e: any) {
    console.error('[iap/apple/notify] signature verification failed', e?.status ?? e)
    return NextResponse.json({ error: 'invalid signature' }, { status: 400 })
  }

  const admin = createAdminClient() as any
  const uuid = n.notificationUUID ?? `no-uuid-${Date.now()}`
  const type = String(n.notificationType ?? '')
  const subtype = n.subtype ? String(n.subtype) : null
  const env = n.data?.environment ? String(n.data.environment) : null

  // 2) 去重：已成功处理过的通知直接确认
  const { data: seen } = await admin.from('apple_notifications')
    .select('result').eq('notification_uuid', uuid).maybeSingle()
  if (seen?.result === 'applied' || seen?.result === 'ignored') return NextResponse.json({ ok: true, duplicate: true })

  const log = (fields: Record<string, any>) => admin.from('apple_notifications').upsert({
    notification_uuid: uuid, notification_type: type, subtype, environment: env, ...fields,
  })

  if (type === 'TEST' || !n.data?.signedTransactionInfo) {
    await log({ result: 'ignored' })
    return NextResponse.json({ ok: true })
  }

  try {
    // 3) 解码交易 + 续订信息
    const txn = await decodeTransaction(n.data.signedTransactionInfo)
    const renewal = n.data.signedRenewalInfo ? await decodeRenewalInfo(n.data.signedRenewalInfo) : null

    const graceUntil = subtype === 'GRACE_PERIOD' ? (renewal?.gracePeriodExpiresDate ?? undefined) : undefined
    const billingRetry = type === 'DID_FAIL_TO_RENEW' || Number(n.data.status) === 3
    const autoRenewing = renewal?.autoRenewStatus != null ? Number(renewal.autoRenewStatus) === 1 : undefined

    // 4) 落库
    const r = await applyAppleTransaction(admin, txn, { autoRenewing, graceUntil, billingRetry })
    await log({
      original_transaction_id: txn.originalTransactionId ?? null,
      user_id: r.result === 'applied' ? r.user_id : null,
      result: r.result === 'error' ? `error:${r.detail ?? ''}`.slice(0, 200) : r.result,
    })

    if (r.result === 'error') return NextResponse.json({ error: r.detail }, { status: 500 })  // 让苹果重试
    return NextResponse.json({ ok: true, result: r.result })
  } catch (e: any) {
    console.error('[iap/apple/notify] processing failed', type, e)
    await log({ result: `error:${String(e?.message ?? e)}`.slice(0, 200) })
    return NextResponse.json({ error: 'processing failed' }, { status: 500 })
  }
}
