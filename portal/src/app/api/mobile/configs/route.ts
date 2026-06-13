import { createAdminClient } from '@/lib/supabase/server'
import { createClient } from '@supabase/supabase-js'
import { generateWgConf } from '@/lib/wireguard'
import { ensureDeviceCrypto } from '@/lib/device-crypto'
import { lookup as dnsLookup } from 'node:dns/promises'
import { NextRequest, NextResponse } from 'next/server'
import type { Database } from '@/types/database.types'

// 按需建 peer 模型（见 docs/on-demand-provisioning.md）：
//   - 每个设备有一对**全局密钥** + 一个**全局唯一 IP**（跨服务器复用）。
//   - configs 不再在每台服务器预建 peer；只用设备密钥**生成各节点的 WG 配置**返回。
//   - 服务器侧的 peer 由客户端连接前调 /api/mobile/ensure-peer 按需添加。

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

interface ServerRow {
  id:           string
  display_name: string
  flag_emoji:   string | null
  location:     string | null
  endpoint:     string
  port:         number
  public_key:   string
  port_secret:  string | null
  api_url:      string
  awg_jc:       number
  awg_jmin:     number
  awg_jmax:     number
  awg_s1:       number
  awg_s2:       number
  awg_h1:       number
  awg_h2:       number
  awg_h3:       number
  awg_h4:       number
  cf_relay_url: string | null
  active_peers: number | null
  max_peers:    number | null
  load_percent: number | null
  status:       string | null
}

// GET /api/mobile/configs?device_id=<optional>
export async function GET(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const admin    = createAdminClient()
  const deviceId = req.nextUrl.searchParams.get('device_id')

  // ── 订阅状态（付费订阅 OR 邀请奖励期内均视为付费）────────
  const [{ data: sub }, { data: profile }] = await Promise.all([
    admin.from('subscriptions').select('status').eq('user_id', user.id).eq('status', 'active').maybeSingle(),
    admin.from('profiles').select('referral_bonus_expires_at').eq('id', user.id).single(),
  ])
  const hasActiveBonus = (profile as any)?.referral_bonus_expires_at
    ? new Date((profile as any).referral_bonus_expires_at) > new Date()
    : false
  const isPaidUser = !!sub || hasActiveBonus

  // ── 免费额度（付费用户不限制）────────────────────────────
  let dailyQuotaBytes:   number | null = null
  let dailyQuotaSeconds: number | null = null
  if (!isPaidUser) {
    const { data: cfgRows } = await admin
      .from('app_config' as any).select('key, value')
      .in('key', ['free_daily_bytes', 'free_daily_seconds'])
    const m = new Map((cfgRows ?? []).map((r: any) => [r.key, r.value]))
    dailyQuotaBytes   = m.has('free_daily_bytes')   ? parseInt(m.get('free_daily_bytes'), 10)   : 524288000
    dailyQuotaSeconds = m.has('free_daily_seconds') ? parseInt(m.get('free_daily_seconds'), 10) : 3600
  }

  // ── 设备列表 ──────────────────────────────────────────────
  const devQuery = admin.from('vpn_devices').select('id, device_label').eq('user_id', user.id).eq('is_active', true)
  if (deviceId) devQuery.eq('id', deviceId)
  const { data: devicesRaw } = await devQuery
  const devices = (devicesRaw ?? []) as Array<{ id: string; device_label: string }>
  if (!devices.length) {
    return NextResponse.json({ devices: [], _debug: 'no_devices' })
  }

  // ── 所有活跃服务器（无需 api_secret：configs 不再 provisioning）──
  const { data: serversRaw } = await (admin.from('vpn_servers') as any)
    .select(`id, display_name, flag_emoji, location, endpoint, port, public_key, port_secret, api_url,
             awg_jc, awg_jmin, awg_jmax, awg_s1, awg_s2, awg_h1, awg_h2, awg_h3, awg_h4,
             cf_relay_url, active_peers, max_peers, load_percent, status`)
    .eq('is_active', true)
    .order('sort_order') as { data: ServerRow[] | null }
  const servers = (serversRaw ?? []) as ServerRow[]

  // ── 解析每台 endpoint 公网 IP（AllowedIPs carve-out 防 WG-in-WG 环路）──
  const endpointHosts = Array.from(new Set(servers.map(s => s.endpoint).filter(Boolean)))
  const endpointIp = new Map<string, string>()
  await Promise.all(endpointHosts.map(async host => {
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) { endpointIp.set(host, host); return }
    try { const { address } = await dnsLookup(host, { family: 4 }); endpointIp.set(host, address) } catch { /* keep */ }
  }))

  // ── 逐设备组装：确保设备密钥/IP，再用它生成各节点配置 ──────
  const result = await Promise.all(devices.map(async dev => {
    const crypto = await ensureDeviceCrypto(admin, dev.id)

    const serverConfigs = (!crypto) ? [] : servers.map(srv => {
      const awgParams = (srv.awg_jc > 0) ? {
        jc: srv.awg_jc, jmin: srv.awg_jmin, jmax: srv.awg_jmax,
        s1: srv.awg_s1, s2: srv.awg_s2,
        h1: srv.awg_h1, h2: srv.awg_h2, h3: srv.awg_h3, h4: srv.awg_h4,
      } : undefined

      let relayHost = srv.endpoint
      try { relayHost = new URL(srv.api_url).hostname } catch { /* keep */ }

      const wgConf = generateWgConf({
        clientPrivateKey: crypto.privateKey,
        clientIp:         crypto.vpnIp,
        serverPublicKey:  srv.public_key,
        presharedKey:     '',                       // 设备级密钥不带 PSK
        serverEndpoint:   srv.endpoint,
        serverPort:       srv.port,
        awgParams,
        serverPublicIp:   endpointIp.get(srv.endpoint),
      })

      return {
        id:           srv.id,
        display_name: srv.display_name,
        flag_emoji:   srv.flag_emoji   ?? '',
        location:     srv.location     ?? '',
        endpoint:     srv.endpoint,
        relay_host:   relayHost,
        port:         srv.port,
        wg_conf:      wgConf,
        port_secret:  srv.port_secret  ?? null,
        cf_relay_url: srv.cf_relay_url ?? null,
        active_peers: srv.active_peers ?? 0,
        max_peers:    srv.max_peers    ?? 0,
        load_percent: srv.load_percent ?? 0,
        status:       srv.status       ?? 'online',
      }
    })

    return {
      id:                  dev.id,
      label:               dev.device_label,
      daily_quota_bytes:   dailyQuotaBytes,
      daily_quota_seconds: dailyQuotaSeconds,
      daily_bytes_used:    0,        // 时间制试用为强制额度；字节仅展示，按需模型下置 0
      is_suspended:        false,
      servers:             serverConfigs,
    }
  }))

  const totalServers = result.reduce((s, d) => s + d.servers.length, 0)
  console.log(`[mobile/configs] user=${user.id} devices=${result.length} servers=${totalServers} paid=${isPaidUser} (on-demand)`)
  return NextResponse.json({ devices: result })
}
