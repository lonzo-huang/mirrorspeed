import { createAdminClient } from '@/lib/supabase/server'
import { NextRequest, NextResponse } from 'next/server'

// GET /api/cron/sync-servers
// 由 Vercel Cron Job 每分钟调用
// 职责：
//   1. 同步每台 VPN 服务器的运行状态（CPU/内存/带宽/延迟）
//   2. 同步每个 peer 的今日流量用量
//   3. 对超额免费用户执行暂停，次日自动恢复

const CRON_SECRET = process.env.CRON_SECRET

export async function GET(req: NextRequest) {
  const auth = req.headers.get('authorization')
  if (CRON_SECRET && auth !== `Bearer ${CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const admin = createAdminClient()

  const { data: servers } = await admin
    .from('vpn_servers')
    .select('id, name, api_url, api_secret')
    .eq('is_active', true)

  if (!servers || servers.length === 0) {
    return NextResponse.json({ synced: 0 })
  }

  const results: { server: string; success: boolean; error?: string }[] = []

  // ── 阶段 1：并发同步所有服务器状态 + peer 流量 ────────────────────────
  await Promise.allSettled(
    servers.map(async (server) => {
      const t0 = Date.now()
      try {
        // 每台服务器用自己的 api_secret（与 provisioning 路径一致）
        if (!server.api_secret) throw new Error('missing api_secret')
        const secret = server.api_secret
        const controller = new AbortController()
        const timer = setTimeout(() => controller.abort(), 8000)

        const [statsRes, healthRes, peersRes] = await Promise.all([
          fetch(`${server.api_url}/stats`, {
            headers: { 'X-API-Secret': secret },
            signal: controller.signal,
          }),
          fetch(`${server.api_url}/health`, { signal: controller.signal }),
          fetch(`${server.api_url}/peers`, {
            headers: { 'X-API-Secret': secret },
            signal: controller.signal,
          }),
        ])
        clearTimeout(timer)

        const latencyMs = Date.now() - t0
        if (!statsRes.ok) throw new Error(`stats HTTP ${statsRes.status}`)

        const stats = await statsRes.json()
        const peers: Array<{
          peer_name:      string
          public_key:     string
          rx_bytes:       number
          tx_bytes:       number
        }> = peersRes.ok ? await peersRes.json() : []

        // 更新服务器状态
        const { data: maxPeersRow } = await admin
          .from('vpn_servers').select('max_peers').eq('id', server.id).single()
        const maxPeers   = maxPeersRow?.max_peers ?? 200
        const loadPct    = Math.round((stats.active_peers / maxPeers) * 100)
        let portalStatus = stats.status
        // degraded 反映真实健康度，而非跨洲网络距离：
        // - 海外节点到 Vercel 的正常往返就有 500-800ms，旧的 500ms 阈值几乎全误报
        // - 真正的"降级"应看资源过载(CPU/内存)或极端延迟
        if (stats.cpu_percent > 90 || stats.mem_percent > 90) portalStatus = 'degraded'
        else if (latencyMs > 1500) portalStatus = 'degraded'

        await admin.from('vpn_servers').update({
          status:          portalStatus,
          latency_ms:      latencyMs,
          active_peers:    stats.active_peers,
          load_percent:    Math.min(100, loadPct),
          cpu_percent:     stats.cpu_percent,
          mem_percent:     stats.mem_percent,
          bandwidth_mbps:  stats.bw_tx_mbps + stats.bw_rx_mbps,
          last_checked_at: new Date().toISOString(),
        }).eq('id', server.id)

        // ── 同步 peer 流量 ────────────────────────────────────────────────
        if (peers.length > 0) {
          await syncPeerUsage(admin, server.id, peers)
        }

        results.push({ server: server.name, success: true })
      } catch (e: any) {
        await admin.from('vpn_servers').update({
          status:          'offline',
          latency_ms:      null,
          last_checked_at: new Date().toISOString(),
        }).eq('id', server.id)
        results.push({ server: server.name, success: false, error: e.message })
      }
    })
  )

  // ── 阶段 2：评估所有设备的流量额度，执行暂停 / 恢复 ─────────────────────
  await enforceQuotas(admin, servers)

  return NextResponse.json({
    synced:    results.filter(r => r.success).length,
    failed:    results.filter(r => !r.success).length,
    results,
    timestamp: new Date().toISOString(),
  })
}

// ── 同步单台服务器上的 peer 流量 ──────────────────────────────────────────────
async function syncPeerUsage(
  admin: ReturnType<typeof createAdminClient>,
  serverId: string,
  wgPeers: Array<{ peer_name: string; rx_bytes: number; tx_bytes: number }>,
) {
  const today = new Date().toISOString().slice(0, 10) // 'YYYY-MM-DD'

  // 拉取本服务器所有活跃 peer 记录
  const { data: dbPeers } = await admin
    .from('vpn_device_peers')
    .select('id, peer_name, last_total_bytes, daily_bytes, daily_reset_at')
    .eq('server_id', serverId)
    .eq('is_active', true)

  if (!dbPeers?.length) return

  // 按 peer_name 建索引，方便匹配
  const dbPeerMap = new Map(dbPeers.map(p => [p.peer_name, p]))

  for (const wgPeer of wgPeers) {
    const dbPeer = dbPeerMap.get(wgPeer.peer_name)
    if (!dbPeer) continue

    const currentTotal = wgPeer.rx_bytes + wgPeer.tx_bytes
    const lastTotal    = dbPeer.last_total_bytes ?? 0

    // 处理 WireGuard 重启后计数归零的情况
    const delta = currentTotal >= lastTotal
      ? currentTotal - lastTotal   // 正常增量
      : currentTotal               // WG 重启，归零后的累计

    const isNewDay = (dbPeer.daily_reset_at as string) < today

    let newDailyBytes: number
    let newResetAt: string

    if (isNewDay) {
      // 新的一天：重置计数器，只记录本次增量
      newDailyBytes = delta
      newResetAt    = today
    } else {
      newDailyBytes = (dbPeer.daily_bytes ?? 0) + delta
      newResetAt    = dbPeer.daily_reset_at as string
    }

    await admin
      .from('vpn_device_peers')
      .update({
        last_total_bytes: currentTotal,
        daily_bytes:      newDailyBytes,
        daily_reset_at:   newResetAt,
      })
      .eq('id', dbPeer.id)
  }
}

// ── 评估所有设备的额度，执行暂停 / 恢复 ──────────────────────────────────────
async function enforceQuotas(
  admin:         ReturnType<typeof createAdminClient>,
  activeServers: Array<{ id: string; name: string; api_url: string; api_secret: string | null }>,
) {
  const today = new Date().toISOString().slice(0, 10)

  // 读取免费额度配置
  const { data: cfg } = await admin
    .from('app_config' as any)
    .select('value')
    .eq('key', 'free_daily_bytes')
    .maybeSingle()
  const quotaBytes = cfg ? parseInt((cfg as any).value, 10) : 524288000

  // 拉取所有活跃设备，及其各 peer 的今日流量和暂停状态
  const { data: devicePeers } = await admin
    .from('vpn_device_peers')
    .select(`
      id, peer_name, server_id, daily_bytes, daily_reset_at, is_suspended,
      device:vpn_devices!inner(id, user_id, is_active)
    `)
    .eq('is_active', true)
    .eq('vpn_devices.is_active', true)

  if (!devicePeers?.length) return

  // 按 device_id 聚合
  const deviceMap = new Map<string, {
    userId:     string
    totalBytes: number
    peers:      Array<{ id: string; peer_name: string; server_id: string; is_suspended: boolean; daily_reset_at: string }>
  }>()

  for (const p of devicePeers) {
    const dev = (p as any).device
    if (!dev?.is_active) continue
    const deviceId = dev.id
    if (!deviceMap.has(deviceId)) {
      deviceMap.set(deviceId, { userId: dev.user_id, totalBytes: 0, peers: [] })
    }
    const entry = deviceMap.get(deviceId)!
    // 新的一天的流量不计入（已在 syncPeerUsage 中重置）
    const bytes = (p.daily_reset_at as string) < today ? 0 : (p.daily_bytes ?? 0)
    entry.totalBytes += bytes
    entry.peers.push({
      id:           p.id,
      peer_name:    p.peer_name,
      server_id:    p.server_id,
      is_suspended: p.is_suspended,
      daily_reset_at: p.daily_reset_at as string,
    })
  }

  // 批量查询付费用户
  const userIds = [...new Set([...deviceMap.values()].map(d => d.userId))]
  const { data: paidSubs } = await admin
    .from('subscriptions')
    .select('user_id')
    .in('user_id', userIds)
    .eq('status', 'active')
  const paidUserIds = new Set((paidSubs ?? []).map(s => s.user_id))

  // 服务器 id → { api_url, secret } 索引
  const serverApiMap = new Map(activeServers.map(s => [s.id, { url: s.api_url, secret: s.api_secret }]))

  for (const [, entry] of deviceMap) {
    const isPaid      = paidUserIds.has(entry.userId)
    const isOverQuota = !isPaid && entry.totalBytes > quotaBytes

    for (const peer of entry.peers) {
      const srv = serverApiMap.get(peer.server_id)
      if (!srv || !srv.secret) continue

      const isNewDay = (peer.daily_reset_at as string) < today

      if (isPaid && peer.is_suspended) {
        // 付费用户：如果被误暂停，立即恢复
        await setPeerActive(srv.url, peer.peer_name, true, srv.secret)
        await admin.from('vpn_device_peers').update({ is_suspended: false }).eq('id', peer.id)

      } else if (isNewDay && peer.is_suspended) {
        // 免费用户新的一天：恢复访问
        await setPeerActive(srv.url, peer.peer_name, true, srv.secret)
        await admin.from('vpn_device_peers').update({ is_suspended: false }).eq('id', peer.id)

      } else if (!isOverQuota && peer.is_suspended) {
        // 免费用户当天用量已回落到额度以下（或额度被上调）：立即恢复，
        // 不必等到午夜。避免调高 free_daily_bytes 后仍被封到第二天。
        await setPeerActive(srv.url, peer.peer_name, true, srv.secret)
        await admin.from('vpn_device_peers').update({ is_suspended: false }).eq('id', peer.id)

      } else if (isOverQuota && !peer.is_suspended) {
        // 超额免费用户：暂停
        await setPeerActive(srv.url, peer.peer_name, false, srv.secret)
        await admin.from('vpn_device_peers').update({ is_suspended: true }).eq('id', peer.id)
      }
    }
  }
}

async function setPeerActive(serverUrl: string, peerName: string, active: boolean, apiSecret: string) {
  try {
    await fetch(`${serverUrl}/peers/${peerName}/status`, {
      method:  'PATCH',
      headers: { 'Content-Type': 'application/json', 'X-API-Secret': apiSecret },
      body:    JSON.stringify({ active }),
      signal:  AbortSignal.timeout(5000),
    })
  } catch (e) {
    console.error(`[quota] setPeerActive(${peerName}, ${active}) failed:`, e)
  }
}
