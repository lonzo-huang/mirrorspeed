import { createAdminClient } from '@/lib/supabase/server'
import { createClient } from '@supabase/supabase-js'
import { decryptKey } from '@/lib/clash'
import { generateWgConf } from '@/lib/wireguard'
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

// GET /api/mobile/configs?device_id=<optional>
// 返回用户所有（或指定）设备的全部节点 WireGuard 配置 + 流量额度信息
export async function GET(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const admin    = createAdminClient()
  const deviceId = req.nextUrl.searchParams.get('device_id')

  // ── 订阅状态（付费订阅 OR 邀请奖励期内均视为付费用户）────────
  const [{ data: sub }, { data: profile }] = await Promise.all([
    admin.from('subscriptions')
      .select('status')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .maybeSingle(),
    admin.from('profiles')
      .select('referral_bonus_expires_at')
      .eq('id', user.id)
      .single(),
  ])

  const hasActiveBonus = profile?.referral_bonus_expires_at
    ? new Date(profile.referral_bonus_expires_at) > new Date()
    : false

  const isPaidUser = !!sub || hasActiveBonus

  // ── 免费额度（来自 app_config，付费用户不限制）──────────────
  let dailyQuotaBytes: number | null = null
  if (!isPaidUser) {
    const { data: cfg } = await admin
      .from('app_config' as any)
      .select('value')
      .eq('key', 'free_daily_bytes')
      .maybeSingle()
    dailyQuotaBytes = cfg ? parseInt((cfg as any).value, 10) : 524288000 // fallback 500MB
  }

  // ── 拉取设备列表 ──────────────────────────────────────────────
  const devQuery = admin
    .from('vpn_devices')
    .select('id, device_label')
    .eq('user_id', user.id)
    .eq('is_active', true)

  if (deviceId) devQuery.eq('id', deviceId)
  const { data: devices } = await devQuery

  if (!devices?.length) {
    console.warn('[mobile/configs] No active devices for user', user.id)
    return NextResponse.json({ devices: [], _debug: 'no_devices' })
  }

  // ── 拉取所有相关 peer（含服务器信息 + 流量数据）──────────────
  const deviceIds = devices.map(d => d.id)
  const { data: peers } = await admin
    .from('vpn_device_peers')
    .select(`
      device_id, private_key_enc, preshared_key_enc, vpn_ip,
      peer_name, daily_bytes, is_suspended,
      server:vpn_servers(id, display_name, flag_emoji, location, endpoint, port, public_key, port_secret,
        api_url, awg_jc, awg_jmin, awg_jmax, awg_s1, awg_s2, awg_h1, awg_h2, awg_h3, awg_h4, cf_relay_url)
    `)
    .in('device_id', deviceIds)
    .eq('is_active', true)

  // ── 组装响应 ──────────────────────────────────────────────────
  const result = devices.map(dev => {
    const devPeers = (peers ?? []).filter(p => p.device_id === dev.id)

    // 今日总已用流量（跨所有节点累加）
    const dailyBytesUsed = devPeers.reduce((sum, p) => sum + ((p as any).daily_bytes ?? 0), 0)

    // 只要任一节点被暂停，整个设备视为暂停
    const isSuspended = devPeers.some(p => (p as any).is_suspended)

    const servers = devPeers.map(p => {
      const srv = (p as any).server
      if (!srv) return null
      // Build AWG obfuscation params (only when Jc > 0)
      const awgParams = (srv.awg_jc > 0) ? {
        jc:   srv.awg_jc,
        jmin: srv.awg_jmin,
        jmax: srv.awg_jmax,
        s1:   srv.awg_s1,
        s2:   srv.awg_s2,
        h1:   srv.awg_h1,
        h2:   srv.awg_h2,
        h3:   srv.awg_h3,
        h4:   srv.awg_h4,
      } : undefined

      // Derive relay hostname from api_url (always a domain, never a raw IP).
      // This ensures the wstunnel WebSocket TLS cert matches the hostname even
      // when the endpoint column stores a raw IP address.
      let relayHost: string = srv.endpoint
      try {
        relayHost = new URL(srv.api_url as string).hostname  // e.g. 'spain01.ionos.mirrorspeed.com'
      } catch { /* keep endpoint as fallback */ }

      const wgConf = generateWgConf({
        clientPrivateKey: decryptKey(p.private_key_enc),
        clientIp:         p.vpn_ip.includes('/') ? p.vpn_ip : `${p.vpn_ip}/32`,
        serverPublicKey:  srv.public_key,
        presharedKey:     decryptKey(p.preshared_key_enc),
        serverEndpoint:   srv.endpoint,
        serverPort:       srv.port,
        awgParams,
      })
      return {
        id:            srv.id,
        display_name:  srv.display_name,
        flag_emoji:    srv.flag_emoji  ?? '',
        location:      srv.location    ?? '',
        endpoint:      srv.endpoint,
        relay_host:    relayHost,
        port:          srv.port,
        wg_conf:       wgConf,
        port_secret:   srv.port_secret  ?? null,
        cf_relay_url:  srv.cf_relay_url ?? null,
      }
    }).filter(Boolean)

    return {
      id:                 dev.id,
      label:              dev.device_label,
      daily_quota_bytes:  dailyQuotaBytes,   // null = 无限制（付费用户）
      daily_bytes_used:   dailyBytesUsed,
      is_suspended:       isSuspended,
      servers,
    }
  })

  const totalServers = result.reduce((s, d) => s + d.servers.length, 0)
  console.log(`[mobile/configs] user=${user.id} devices=${result.length} servers=${totalServers} paid=${isPaidUser}`)
  return NextResponse.json({ devices: result })
}
