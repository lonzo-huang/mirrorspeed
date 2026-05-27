import { createAdminClient } from '@/lib/supabase/server'
import { createClient }      from '@supabase/supabase-js'
import { NextRequest, NextResponse } from 'next/server'
import type { Database } from '@/types/database.types'

// ── 邀请码字符集（排除易混淆字符：0/O/I/1/L）──────────────────────────────
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'

function generateReferralCode(): string {
  return Array.from({ length: 6 }, () =>
    CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)]
  ).join('')
}

async function getUserFromBearer(req: NextRequest) {
  const auth  = req.headers.get('authorization') ?? ''
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

// ── GET /api/mobile/referral ──────────────────────────────────────────────────
// 返回当前用户的邀请信息：邀请码、邀请人数、累计获得天数、奖励到期时间
export async function GET(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const admin = createAdminClient()

  // 获取或生成邀请码
  const { data: profile } = await admin
    .from('profiles')
    .select('referral_code, referred_by, referral_bonus_expires_at')
    .eq('id', user.id)
    .single()

  if (!profile) {
    return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
  }

  // 懒生成邀请码（首次访问时）
  let code = profile.referral_code
  if (!code) {
    // 生成唯一邀请码（最多重试 5 次）
    for (let i = 0; i < 5; i++) {
      const candidate = generateReferralCode()
      const { error } = await admin
        .from('profiles')
        .update({ referral_code: candidate })
        .eq('id', user.id)
        .is('referral_code', null) // 防止并发重复写入
      if (!error) { code = candidate; break }
    }
    if (!code) {
      return NextResponse.json({ error: '生成邀请码失败，请重试' }, { status: 500 })
    }
  }

  // 统计邀请数量和累计奖励天数
  const { data: rewards } = await admin
    .from('referral_rewards')
    .select('bonus_days')
    .eq('referrer_id', user.id)

  const inviteCount     = rewards?.length ?? 0
  const totalBonusDays  = rewards?.reduce((sum, r) => sum + r.bonus_days, 0) ?? 0
  const bonusExpiresAt  = profile.referral_bonus_expires_at

  // 查询 referred_by 对应的邀请码（展示给用户看）
  let referredByCode: string | null = null
  if (profile.referred_by) {
    const { data: referrer } = await admin
      .from('profiles')
      .select('referral_code')
      .eq('id', profile.referred_by)
      .single()
    referredByCode = referrer?.referral_code ?? null
  }

  const shareUrl = `https://mirrorspeed.com/?ref=${code}`

  return NextResponse.json({
    referral_code:      code,
    share_url:          shareUrl,
    invite_count:       inviteCount,
    total_bonus_days:   totalBonusDays,
    bonus_expires_at:   bonusExpiresAt,
    referred_by_code:   referredByCode,  // null = 未被邀请
  })
}

// ── POST /api/mobile/referral/apply ─────────────────────────────────────────
// Body: { code: string }
// 绑定邀请人（只能绑定一次；不触发奖励，奖励在付款后由 Stripe webhook 发放）
export async function POST(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const body = await req.json().catch(() => ({}))
  const { code } = body as { code?: string }
  if (!code || code.trim().length === 0) {
    return NextResponse.json({ error: '请输入邀请码' }, { status: 400 })
  }

  const upperCode = code.trim().toUpperCase()
  const admin     = createAdminClient()

  // 检查当前用户是否已绑定邀请人
  const { data: myProfile } = await admin
    .from('profiles')
    .select('referred_by, referral_code')
    .eq('id', user.id)
    .single()

  if (!myProfile) {
    return NextResponse.json({ error: '用户信息不存在' }, { status: 404 })
  }
  if (myProfile.referred_by) {
    return NextResponse.json({ error: '你已经绑定过邀请码，无法重复绑定' }, { status: 409 })
  }
  if (myProfile.referral_code === upperCode) {
    return NextResponse.json({ error: '不能使用自己的邀请码' }, { status: 400 })
  }

  // 查找邀请码对应的用户
  const { data: referrer } = await admin
    .from('profiles')
    .select('id')
    .eq('referral_code', upperCode)
    .single()

  if (!referrer) {
    return NextResponse.json({ error: '邀请码无效，请检查后重试' }, { status: 404 })
  }

  // 绑定邀请人
  await admin
    .from('profiles')
    .update({ referred_by: referrer.id })
    .eq('id', user.id)

  await admin.from('audit_log').insert({
    user_id: user.id,
    action:  'referral_applied',
    detail:  { referrer_id: referrer.id, code: upperCode },
  })

  return NextResponse.json({
    success:    true,
    message:    '邀请码绑定成功！订阅后你的邀请人将获得额外使用时长。',
    referrer_id: referrer.id,
  })
}
