import { createAdminClient } from '@/lib/supabase/server'
import { createClient } from '@supabase/supabase-js'
import { NextRequest, NextResponse } from 'next/server'
import type { Database } from '@/types/database.types'
import { verifyTransaction, type AppleTransaction } from '@/lib/apple-iap'
import { applyTransaction } from '@/lib/apple-iap-db'

export const runtime = 'nodejs'   // 需要 node:crypto 的 X509，不能跑 edge

async function getUserFromBearer(req: NextRequest) {
  const auth = req.headers.get('authorization') ?? ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null
  if (!token) return null
  const supabase = createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { autoRefreshToken: false, persistSession: false } },
  )
  const { data: { user } } = await supabase.auth.getUser(token)
  return user
}

/**
 * POST /api/mobile/iap/apple
 * Body: { signed_transactions: string[] }   // StoreKit 2 的 JWS 交易（可多笔=恢复购买）
 *
 * 客户端购买成功或点「恢复购买」后调用。服务器本地验签（证书链锚定 Apple Root CA），
 * 再把订阅写进 subscriptions 表。会员状态一律以服务器为准，客户端只读结果。
 */
export async function POST(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const body = await req.json().catch(() => ({}))
  const list: string[] = Array.isArray(body?.signed_transactions)
    ? body.signed_transactions
    : body?.signed_transaction ? [body.signed_transaction] : []
  if (list.length === 0) {
    return NextResponse.json({ error: 'missing signed_transactions' }, { status: 400 })
  }

  const admin = createAdminClient()
  let applied = 0
  const errors: string[] = []

  for (const jws of list) {
    let txn: AppleTransaction
    try {
      txn = verifyTransaction(jws)
    } catch (e) {
      errors.push(String(e))
      continue
    }
    try {
      await applyTransaction(admin, user.id, txn)
      applied++
    } catch (e) {
      errors.push(String(e))
    }
  }

  if (applied === 0) {
    return NextResponse.json(
      { error: 'no valid transaction', details: errors }, { status: 400 })
  }

  const { data: sub } = await admin
    .from('subscriptions')
    .select('status, expires_at, plan_id')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()

  return NextResponse.json({ ok: true, applied, subscription: sub ?? null })
}
