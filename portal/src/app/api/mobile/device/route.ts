import { createAdminClient } from '@/lib/supabase/server'
import { createClient }      from '@supabase/supabase-js'
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

/** Create WireGuard peers on every active server for a given device. */
async function provisionPeers(
  admin:    ReturnType<typeof createAdminClient>,
  userId:   string,
  deviceId: string,
) {
  const { data: servers } = await admin
    .from('vpn_servers').select('id, name, api_url').eq('is_active', true)

  if (!servers?.length) return { ok: false, error: '当前没有可用的 VPN 服务器，请稍后再试' }

  const VPN_API_SECRET = process.env.VPN_API_SECRET!
  const { encryptKey } = await import('@/lib/clash')
  const { buildPeerName } = await import('@/lib/wireguard')

  const results = await Promise.allSettled(servers.map(async server => {
    // 确定性命名（与 /api/mobile/configs 的自动配置完全一致），保证同一
    // device+server 永远同名、幂等。
    const peerName = buildPeerName(deviceId, server.id)
    const res = await fetch(`${server.api_url}/peers`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json', 'X-API-Secret': VPN_API_SECRET },
      body:    JSON.stringify({ peer_name: peerName }),
    })
    if (!res.ok) {
      const err = await res.text()
      throw new Error(`VPN server ${server.name} returned ${res.status}: ${err}`)
    }
    const peerInfo = await res.json()
    const { error } = await admin.from('vpn_device_peers').insert({
      device_id:         deviceId,
      server_id:         server.id,
      user_id:           userId,
      peer_name:         peerName,
      public_key:        peerInfo.public_key,
      private_key_enc:   encryptKey(peerInfo.private_key),
      preshared_key_enc: encryptKey(peerInfo.preshared_key),
      vpn_ip:            peerInfo.vpn_ip,
    })
    // 23505 = 唯一索引冲突：另一并发请求已为该 (device, server) 建好 peer。
    // 视为成功（已存在），不重复报错。
    if (error && (error as { code?: string }).code !== '23505') {
      throw new Error(`DB insert failed for ${server.name}: ${error.message}`)
    }
  }))

  const failed = results.filter(r => r.status === 'rejected') as PromiseRejectedResult[]
  if (failed.length === results.length) {
    const reasons = failed.map(f => f.reason?.message ?? String(f.reason)).join('; ')
    return { ok: false, error: `VPN 服务器通信失败: ${reasons}` }
  }
  return { ok: true, error: null }
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
  const { platform, device_name, device_id: cachedDeviceId } = body as {
    platform: string; device_name: string; device_id?: string
  }
  if (!platform || !device_name) {
    return NextResponse.json({ error: '缺少必填字段 platform / device_name' }, { status: 400 })
  }

  // ── Case 1: app already has a device_id cached ──────────────────────────────
  if (cachedDeviceId) {
    const { data: existing } = await admin
      .from('vpn_devices')
      .select('id, device_label, sub_token')
      .eq('id', cachedDeviceId)
      .eq('user_id', user.id)
      .eq('is_active', true)
      .maybeSingle()

    if (existing) {
      // Ensure this device has peers (may be missing if VPN API was down at registration)
      const { count: peerCount } = await admin
        .from('vpn_device_peers')
        .select('id', { count: 'exact', head: true })
        .eq('device_id', existing.id)
        .eq('is_active', true)

      if ((peerCount ?? 0) === 0) {
        const { ok, error } = await provisionPeers(admin, user.id, existing.id)
        if (!ok) return NextResponse.json({ error }, { status: 502 })
      }

      return NextResponse.json({
        device_id:    existing.id,
        device_label: existing.device_label,
        sub_token:    existing.sub_token,
      })
    }
    // device_id not found / not owned by user — fall through to create a new one
  }

  // ── Case 2: check if user already has an active device (re-use first one) ──
  // This handles the case where app lost its cached device_id
  const { data: userDevices } = await admin
    .from('vpn_devices')
    .select('id, device_label, sub_token')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(2)

  if (userDevices && userDevices.length > 0) {
    // Re-use the most recently created device
    const existing = userDevices[0]

    const { count: peerCount } = await admin
      .from('vpn_device_peers')
      .select('id', { count: 'exact', head: true })
      .eq('device_id', existing.id)
      .eq('is_active', true)

    if ((peerCount ?? 0) === 0) {
      const { ok, error } = await provisionPeers(admin, user.id, existing.id)
      if (!ok) return NextResponse.json({ error }, { status: 502 })
    }

    return NextResponse.json({
      device_id:    existing.id,
      device_label: existing.device_label,
      sub_token:    existing.sub_token,
    })
  }

  // ── Case 3: new device ────────────────────────────────────────────────────────
  // Check device limit
  if ((userDevices?.length ?? 0) >= 2) {
    return NextResponse.json({ error: '设备数量已达上限（2台），请在网页端删除旧设备后再试' }, { status: 409 })
  }

  // Create device record (no device_fingerprint column in schema)
  const { data: dev, error: dbErr } = await admin
    .from('vpn_devices')
    .insert({
      user_id:         user.id,
      subscription_id: sub?.id ?? null,
      device_label:    device_name,
      os_hint:         platform,
      is_active:       true,
    })
    .select('id, device_label, sub_token')
    .single()

  if (dbErr || !dev) {
    console.error('[mobile/device] insert failed:', dbErr)
    return NextResponse.json(
      { error: `创建设备失败: ${dbErr?.message ?? 'unknown'}` },
      { status: 500 },
    )
  }

  // Create WireGuard peers on all active servers
  const { ok, error: peerErr } = await provisionPeers(admin, user.id, dev.id)
  if (!ok) {
    // Roll back device record so the user can retry
    await admin.from('vpn_devices').delete().eq('id', dev.id)
    return NextResponse.json({ error: peerErr }, { status: 502 })
  }

  return NextResponse.json({
    device_id:    dev.id,
    device_label: dev.device_label,
    sub_token:    dev.sub_token,
  })
}
