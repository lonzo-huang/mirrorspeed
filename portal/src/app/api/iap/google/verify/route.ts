/**
 * POST /api/iap/google/verify
 * Android App 购买/恢复购买成功后调用，服务端向 Google Play 核验并开通会员。
 *
 * Auth: Authorization: Bearer <supabase access token>
 * Body: { purchaseToken: string, productId?: string }
 * 返回: { ok, status, expires_at }
 *
 * 需要 Vercel 环境变量 GOOGLE_PLAY_SERVICE_ACCOUNT（服务账号 JSON）。见 lib/google-play.ts。
 */
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createAdminClient } from '@/lib/supabase/server'
import { applyGoogleTransaction } from '@/lib/google-play'

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

  let body: { purchaseToken?: string; productId?: string } = {}
  try { body = await req.json() } catch { /* empty */ }

  const purchaseToken = String(body.purchaseToken ?? '')
  const productId = body.productId ? String(body.productId) : undefined
  if (!purchaseToken) return NextResponse.json({ error: 'purchaseToken required' }, { status: 400 })

  try {
    const r = await applyGoogleTransaction(createAdminClient(), { purchaseToken, productId, userId: user.id })
    if (r.result !== 'applied') {
      console.error('[iap/google/verify]', user.id, r)
      return NextResponse.json(
        { ok: false, error: r.result, detail: 'detail' in r ? r.detail : undefined },
        { status: 422 },
      )
    }
    return NextResponse.json({ ok: true, status: r.status, expires_at: r.expires_at })
  } catch (e: any) {
    console.error('[iap/google/verify] failed', user.id, e)
    return NextResponse.json(
      { ok: false, error: 'verification_failed', detail: String(e?.message ?? e) },
      { status: 400 },
    )
  }
}
