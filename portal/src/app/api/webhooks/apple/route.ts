import { createAdminClient } from '@/lib/supabase/server'
import { NextRequest, NextResponse } from 'next/server'
import { verifyAppleJWS, verifyTransaction } from '@/lib/apple-iap'
import { applyTransaction } from '@/lib/apple-iap-db'

export const runtime = 'nodejs'

/**
 * App Store Server Notifications V2 接收端。
 * 在 App Store Connect →「App 信息 → App Store 服务器通知」里把生产/沙盒 URL
 * 都填成： https://www.mirrorspeed.com/api/webhooks/apple
 *
 * 苹果不用共享密钥，而是把整个通知体做成 JWS 签名 —— 验签即鉴权，
 * 所以这里不需要任何环境变量。
 *
 * 续订、退款、到期、用户取消都靠它推过来；只靠客户端上报会漏（用户可能再也不开 App）。
 */
interface NotificationPayload {
  notificationType: string
  subtype?: string
  notificationUUID: string
  data?: {
    bundleId?: string
    environment?: string
    signedTransactionInfo?: string
    signedRenewalInfo?: string
  }
}

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null) as { signedPayload?: string } | null
  if (!body?.signedPayload) {
    return NextResponse.json({ error: 'missing signedPayload' }, { status: 400 })
  }

  let note: NotificationPayload
  try {
    note = verifyAppleJWS<NotificationPayload>(body.signedPayload)
  } catch (e) {
    console.error('[apple-webhook] 验签失败:', e)
    // 验签失败一律拒绝，且**不要**重试（不是我们的通知）
    return NextResponse.json({ error: 'invalid signature' }, { status: 400 })
  }

  const signedTxn = note.data?.signedTransactionInfo
  if (!signedTxn) {
    // 有些通知类型(如 TEST)不带交易，直接确认收到即可
    return NextResponse.json({ ok: true, ignored: note.notificationType })
  }

  try {
    const txn = verifyTransaction(signedTxn)
    const admin = createAdminClient()

    // 通过 originalTransactionId 找到这条订阅属于哪个用户。
    // 首次购买时客户端已经上报过（/api/mobile/iap/apple），所以这里一定能找到；
    // 万一找不到（例如用户换了账号），记录下来人工处理，不要凭空创建。
    const { data: existing } = await admin
      .from('subscriptions')
      .select('user_id')
      .eq('apple_original_transaction_id', txn.originalTransactionId)
      .maybeSingle()

    if (!existing?.user_id) {
      console.warn('[apple-webhook] 未知订阅，忽略:',
        note.notificationType, txn.originalTransactionId)
      // 返回 200，否则苹果会反复重投
      return NextResponse.json({ ok: true, unmatched: true })
    }

    await applyTransaction(admin, existing.user_id, txn)
    console.log('[apple-webhook]', note.notificationType, note.subtype ?? '',
      txn.productId, txn.originalTransactionId)
    return NextResponse.json({ ok: true })
  } catch (e) {
    console.error('[apple-webhook] 处理失败:', e)
    // 返回 500 让苹果重试（最多重试 5 次，间隔递增）
    return NextResponse.json({ error: 'processing failed' }, { status: 500 })
  }
}
