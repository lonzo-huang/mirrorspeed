import { createAdminClient } from '@/lib/supabase/server'
import { createClient }      from '@supabase/supabase-js'
import { ensureDeviceCrypto } from '@/lib/device-crypto'
import { NextRequest, NextResponse } from 'next/server'
import type { Database } from '@/types/database.types'

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

// POST /api/mobile/device
// Body: { platform, device_name, device_id?: string }
// - If device_id is provided and belongs to the user, return it (and create peers if missing).
// - Otherwise create a new device (max 2 per user).
export async function POST(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const admin = createAdminClient()

  // 免费用户也允许注册设备（流量额度由 cron 统一管控）
  // 付费用户通过订阅校验享有无限流量
  const { data: sub } = await admin
    .from('subscriptions')
    .select('id, status')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()
  // sub 为 null = 免费用户，继续流程（不再拒绝）

  const body = await req.json().catch(() => ({}))
  const { platform, device_name, device_id: cachedDeviceId, fingerprint } = body as {
    platform: string; device_name: string; device_id?: string; fingerprint?: string
  }
  if (!platform || !device_name) {
    return NextResponse.json({ error: '缺少必填字段 platform / device_name' }, { status: 400 })
  }

  // 复用已有设备：确保其全局密钥 + IP 就绪（on-demand：连接时才在服务器建 peer，此处不预建）。
  const reuse = async (d: { id: string; device_label: string; sub_token: string }) => {
    await ensureDeviceCrypto(admin, d.id)
    return NextResponse.json({ device_id: d.id, device_label: d.device_label, sub_token: d.sub_token })
  }

  // ── Case 1: app 已缓存 device_id 且属于本用户 → 复用 ──
  // 但若该设备已有指纹且与本次上送的指纹不一致，说明是“被旧 bug 合并/缓存串号”的另一台
  // 终端，不能复用，转入指纹匹配/新建，避免两台终端永远共用一行。
  if (cachedDeviceId) {
    const { data: existing } = await (admin.from('vpn_devices') as any)
      .select('id, device_label, sub_token, fingerprint')
      .eq('id', cachedDeviceId).eq('user_id', user.id).eq('is_active', true).maybeSingle()
    if (existing) {
      const fpMismatch = fingerprint && existing.fingerprint && existing.fingerprint !== fingerprint
      if (!fpMismatch) {
        // 首次带指纹的旧设备：顺手补写指纹，便于后续按指纹稳定匹配。
        if (fingerprint && !existing.fingerprint) {
          await (admin.from('vpn_devices') as any).update({ fingerprint }).eq('id', existing.id)
        }
        return reuse(existing)
      }
    }
  }

  // ── Case 2: 按硬件指纹匹配同一台设备（同设备重装/丢缓存时复用；不同设备不会被合并）──
  if (fingerprint) {
    const { data: byFp } = await admin.from('vpn_devices')
      .select('id, device_label, sub_token')
      .eq('user_id', user.id).eq('fingerprint', fingerprint).eq('is_active', true).maybeSingle()
    if (byFp) return reuse(byFp)
  }

  // ── Case 3: 新设备（受上限约束）──
  // 免费版 2 台，付费版 4 台。超限返回结构化错误码，客户端按系统语言本地化提示并引导升级。
  const isPaid = !!sub
  const MAX_DEVICES = isPaid ? 4 : 2
  const { count: devCount } = await admin.from('vpn_devices')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id).eq('is_active', true)
  if ((devCount ?? 0) >= MAX_DEVICES) {
    return NextResponse.json(
      {
        error: `设备数量已达上限（${MAX_DEVICES}台），请在网页端删除旧设备后再试`,
        code: 'DEVICE_LIMIT',
        max: MAX_DEVICES,
        is_paid: isPaid,
      },
      { status: 409 },
    )
  }

  const { data: dev, error: dbErr } = await admin.from('vpn_devices').insert({
    user_id:         user.id,
    subscription_id: sub?.id ?? null,
    device_label:    device_name,
    os_hint:         platform,
    fingerprint:     fingerprint ?? null,
    is_active:       true,
  }).select('id, device_label, sub_token').single()

  if (dbErr || !dev) {
    console.error('[mobile/device] insert failed:', dbErr)
    return NextResponse.json({ error: `创建设备失败: ${dbErr?.message ?? 'unknown'}` }, { status: 500 })
  }

  // on-demand：生成设备全局密钥 + 分配全局 IP（不在所有服务器预建 peer）。
  const crypto = await ensureDeviceCrypto(admin, dev.id)
  if (!crypto) {
    await admin.from('vpn_devices').delete().eq('id', dev.id)   // 回滚，便于重试
    return NextResponse.json({ error: '设备初始化失败，请重试' }, { status: 500 })
  }

  return NextResponse.json({
    device_id:    dev.id,
    device_label: dev.device_label,
    sub_token:    dev.sub_token,
  })
}
