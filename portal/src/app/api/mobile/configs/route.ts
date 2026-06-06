import { createAdminClient } from '@/lib/supabase/server'
import { createClient } from '@supabase/supabase-js'
import { decryptKey, encryptKey } from '@/lib/clash'
import { generateWgConf, buildPeerName } from '@/lib/wireguard'
import { lookup as dnsLookup } from 'node:dns/promises'
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

// ── 服务器数据形状（含 api_secret，服务端专用，不下发客户端）──────────────────
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
  api_secret:   string | null
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
}

// ── 已合并 server 信息的 Peer 数据 ────────────────────────────────────────────
interface PeerData {
  device_id:         string
  server_id:         string
  peer_name:         string
  private_key_enc:   string
  preshared_key_enc: string
  vpn_ip:            string
  daily_bytes:       number
  is_suspended:      boolean
  server:            ServerRow
}

// ── 自动配置 Peer ─────────────────────────────────────────────────────────────
//
// 当 vpn_device_peers 中不存在 (device_id, server_id) 组合时，
// 调用该服务器的 vpn-api POST /peers 生成密钥对并写入 Supabase。
// 任何错误均返回 null，不影响其他服务器的配置生成。
async function provisionPeer(
  admin:    ReturnType<typeof createAdminClient>,
  userId:   string,
  deviceId: string,
  server:   ServerRow,
): Promise<PeerData | null> {
  if (!server.api_url || !server.api_secret) {
    console.warn(`[provision] server=${server.id} missing api_url or api_secret — skip`)
    return null
  }

  // 确定性命名（同一 device+server 永远同名，幂等）；与 device 注册路径一致。
  const peerName = buildPeerName(deviceId, server.id)

  // 调用 vpn-api（10 秒超时）
  let apiJson: {
    peer_name:     string
    public_key:    string
    private_key:   string
    preshared_key: string
    vpn_ip:        string
  }
  try {
    const resp = await fetch(`${server.api_url}/peers`, {
      method:  'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Secret': server.api_secret,
      },
      body:   JSON.stringify({ peer_name: peerName }),
      signal: AbortSignal.timeout(10_000),
    })

    if (!resp.ok) {
      const body = await resp.text()
      console.error(`[provision] vpn-api ${resp.status} for server=${server.id}: ${body}`)
      return null
    }
    apiJson = await resp.json()
  } catch (err) {
    console.error(`[provision] fetch error for server=${server.id}:`, err)
    return null
  }

  // 写入 Supabase（使用 as any 绕过 Supabase 复杂 join 类型推导）
  const { error } = await (admin
    .from('vpn_device_peers') as any)
    .insert({
      device_id:         deviceId,
      server_id:         server.id,
      user_id:           userId,
      peer_name:         apiJson.peer_name,
      public_key:        apiJson.public_key,
      private_key_enc:   encryptKey(apiJson.private_key),
      preshared_key_enc: encryptKey(apiJson.preshared_key),
      vpn_ip:            apiJson.vpn_ip,   // 保留 /32 前缀（如 "10.200.0.5/32"）
      is_active:         true,
    })

  if (error) {
    if ((error as any).code === '23505') {
      // 并发竞态：另一请求已提前写入，查询已有记录
      console.warn(`[provision] race condition device=${deviceId} server=${server.id} — fetching existing`)
      const { data: existing } = await (admin
        .from('vpn_device_peers') as any)
        .select('device_id, server_id, peer_name, private_key_enc, preshared_key_enc, vpn_ip, daily_bytes, is_suspended')
        .eq('device_id', deviceId)
        .eq('server_id', server.id)
        .eq('is_active', true)
        .maybeSingle() as { data: any }
      if (existing) {
        return { ...existing, server,
          daily_bytes:  existing.daily_bytes  ?? 0,
          is_suspended: existing.is_suspended ?? false } as PeerData
      }
    } else {
      console.error(`[provision] DB insert error device=${deviceId} server=${server.id}:`, error)
    }
    return null
  }

  console.log(`[provision] provisioned peer=${peerName} device=${deviceId} server=${server.id}`)
  return {
    device_id:         deviceId,
    server_id:         server.id,
    peer_name:         apiJson.peer_name,
    private_key_enc:   encryptKey(apiJson.private_key),
    preshared_key_enc: encryptKey(apiJson.preshared_key),
    vpn_ip:            apiJson.vpn_ip,
    daily_bytes:       0,
    is_suspended:      false,
    server,
  }
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

  const hasActiveBonus = (profile as any)?.referral_bonus_expires_at
    ? new Date((profile as any).referral_bonus_expires_at) > new Date()
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
  const { data: devicesRaw } = await devQuery
  const devices = (devicesRaw ?? []) as Array<{ id: string; device_label: string }>

  if (!devices.length) {
    console.warn('[mobile/configs] No active devices for user', user.id)
    return NextResponse.json({ devices: [], _debug: 'no_devices' })
  }

  const deviceIds = devices.map(d => d.id)

  // ── 并行拉取：所有活跃服务器 + 已有 Peer 记录 ───────────────
  const [{ data: activeServersRaw }, { data: existingPeersRaw }] = await Promise.all([
    // 含 api_secret（仅用于服务端 provisioning，不下发客户端）
    (admin.from('vpn_servers') as any)
      .select(`id, display_name, flag_emoji, location, endpoint, port, public_key, port_secret,
               api_url, api_secret,
               awg_jc, awg_jmin, awg_jmax, awg_s1, awg_s2, awg_h1, awg_h2, awg_h3, awg_h4,
               cf_relay_url`)
      .eq('is_active', true)
      .order('sort_order') as Promise<{ data: ServerRow[] | null; error: any }>,

    // 注意：包含 server_id 用于判断哪些 (device, server) 组合已存在
    (admin.from('vpn_device_peers') as any)
      .select(`
        device_id, server_id, peer_name, private_key_enc, preshared_key_enc, vpn_ip,
        daily_bytes, is_suspended,
        server:vpn_servers(id, display_name, flag_emoji, location, endpoint, port, public_key, port_secret,
          api_url, api_secret,
          awg_jc, awg_jmin, awg_jmax, awg_s1, awg_s2, awg_h1, awg_h2, awg_h3, awg_h4, cf_relay_url)
      `)
      .in('device_id', deviceIds)
      .eq('is_active', true) as Promise<{ data: PeerData[] | null; error: any }>,
  ])

  const activeServers  = (activeServersRaw  ?? []) as ServerRow[]
  const existingPeers  = (existingPeersRaw  ?? []) as PeerData[]

  // ── 自动配置缺失的 (device, server) Peer 组合 ───────────────
  const existingSet = new Set(existingPeers.map(p => `${p.device_id}:${p.server_id}`))

  const provisionTasks: Promise<PeerData | null>[] = []
  for (const dev of devices) {
    for (const srv of activeServers) {
      if (!existingSet.has(`${dev.id}:${srv.id}`)) {
        provisionTasks.push(provisionPeer(admin, user.id, dev.id, srv))
      }
    }
  }

  let provisioned: PeerData[] = []
  if (provisionTasks.length > 0) {
    const results = await Promise.all(provisionTasks)
    provisioned = results.filter((p): p is PeerData => p !== null)
    if (provisioned.length > 0) {
      console.log(`[mobile/configs] provisioned ${provisioned.length} new peer(s) for user=${user.id}`)
    }
  }

  // 合并已有 + 新建 Peer
  const allPeers: PeerData[] = [...existingPeers, ...provisioned]

  // ── 解析每个服务器端点的公网 IP（用于把它从 AllowedIPs 里抠掉，避免
  //    客户端把发往端点的 WG 包又路由进隧道造成封装环路）────────────────
  const endpointHosts = [...new Set(allPeers.map(p => p.server?.endpoint).filter(Boolean) as string[])]
  const endpointIp = new Map<string, string>()
  await Promise.all(endpointHosts.map(async host => {
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) { endpointIp.set(host, host); return }
    try {
      const { address } = await dnsLookup(host, { family: 4 })
      endpointIp.set(host, address)
    } catch { /* 解析失败则不抠（退回原列表） */ }
  }))

  // ── 组装响应 ──────────────────────────────────────────────────
  const result = devices.map(dev => {
    const devPeers = allPeers.filter(p => p.device_id === dev.id)

    // 今日总已用流量（跨所有节点累加）
    const dailyBytesUsed = devPeers.reduce((sum, p) => sum + (p.daily_bytes ?? 0), 0)

    // 只要任一节点被暂停，整个设备视为暂停
    const isSuspended = devPeers.some(p => p.is_suspended)

    const servers = devPeers.map(p => {
      const srv = p.server
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
        relayHost = new URL(srv.api_url).hostname  // e.g. 'spain01.ionos.mirrorspeed.com'
      } catch { /* keep endpoint as fallback */ }

      const wgConf = generateWgConf({
        clientPrivateKey: decryptKey(p.private_key_enc),
        clientIp:         p.vpn_ip.includes('/') ? p.vpn_ip : `${p.vpn_ip}/32`,
        serverPublicKey:  srv.public_key,
        presharedKey:     decryptKey(p.preshared_key_enc),
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
        // api_secret は意図的に省略 — クライアントに送信しない
      }
    }).filter(Boolean)

    return {
      id:                dev.id,
      label:             dev.device_label,
      daily_quota_bytes: dailyQuotaBytes,  // null = 無制限（有料ユーザー）
      daily_bytes_used:  dailyBytesUsed,
      is_suspended:      isSuspended,
      servers,
    }
  })

  const totalServers = result.reduce((s, d) => s + d.servers.length, 0)
  console.log(`[mobile/configs] user=${user.id} devices=${result.length} servers=${totalServers} paid=${isPaidUser}`)
  return NextResponse.json({ devices: result })
}
