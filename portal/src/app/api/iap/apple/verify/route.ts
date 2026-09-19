/**
 * POST /api/iap/apple/verify
 * iOS App 购买/恢复购买成功后调用，服务端向苹果核验交易并开通会员。
 *
 * Auth: Authorization: Bearer <supabase access token>
 * Body（二选一）:
 *   { transactionId: string }      —— 服务端经 App Store Server API 查询（推荐，需 APPLE_IAP_* 密钥）
 *   { signedTransaction: string }  —— StoreKit 2 的 jwsRepresentation，直接校验签名
 * 返回: { ok, status, expires_at }
 */
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createAdminClient } from '@/lib/supabase/server'
import { applyAppleTransaction, decodeTransaction, fetchSignedTransaction } from '@/lib/apple-iap'

export const dynamic = 'force-dynamic'
export const runtime = 'nodejs'

async function getUserFromBearer(req: NextRequest) {
  const auth = req.headers.get('authorization') ?? ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null
  if (!token) return null
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )
  const { data: { user } } = await supabase.auth.getUser(token)
  return user
}

export async function POST(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  let body: { transactionId?: string; signedTransaction?: string } = {}
  try { body = await req.json() } catch { /* empty */ }

  let signed = body.signedTransaction
  try {
    if (!signed && body.transactionId) signed = await fetchSignedTransaction(String(body.transactionId))
    if (!signed) return NextResponse.json({ error: 'transactionId or signedTransaction required' }, { status: 400 })

    const txn = await decodeTransaction(signed)
    const r = await applyAppleTransaction(createAdminClient(), txn, { userId: user.id })

    if (r.result !== 'applied') {
      console.error('[iap/apple/verify]', user.id, r)
      return NextResponse.json({ ok: false, error: r.result, detail: 'detail' in r ? r.detail : undefined }, { status: 422 })
    }
    return NextResponse.json({ ok: true, status: r.status, expires_at: r.expires_at })
  } catch (e: any) {
    console.error('[iap/apple/verify] failed', user.id, e)
    return NextResponse.json({ ok: false, error: 'verification_failed', detail: String(e?.message ?? e) }, { status: 400 })
  }
}
