import { createAdminClient } from '@/lib/supabase/server'
import { NextRequest, NextResponse } from 'next/server'

// GET /api/cron/sync-servers
// 由 Vercel Cron Job 每分钟调用（见 vercel.json）
// 向每台 VPN 服务器的 FastAPI /stats 和 /health 发请求，
// 测量响应时间（portal→server 延迟），将结果写入 Supabase 缓存

// Vercel Cron 请求头鉴权
const CRON_SECRET = process.env.CRON_SECRET

export async function GET(req: NextRequest) {
  // 验证 Vercel Cron 请求（防止外部直接调用）
  const auth = req.headers.get('authorization')
  if (CRON_SECRET && auth !== `Bearer ${CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const admin = createAdminClient()

  // 拉取所有启用的服务器
  const { data: servers } = await admin
    .from('vpn_servers')
    .select('id, name, api_url')
    .eq('is_active', true)

  if (!servers || servers.length === 0) {
    return NextResponse.json({ synced: 0 })
  }

  const VPN_API_SECRET = process.env.VPN_API_SECRET!
  const results: { server: string; success: boolean; error?: string }[] = []

  // 并发拉取所有服务器状态（超时 8 秒）
  await Promise.allSettled(
    servers.map(async (server) => {
      const t0 = Date.now()
      try {
        const controller = new AbortController()
        const timer = setTimeout(() => controller.abort(), 8000)

        const [statsRes, healthRes] = await Promise.all([
          fetch(`${server.api_url}/stats`, {
            headers: { 'X-API-Secret': VPN_API_SECRET },
            signal: controller.signal,
          }),
          // /health 不需要 API Key，用于测量实际 TCP 延迟
          fetch(`${server.api_url}/health`, {
            signal: controller.signal,
          }),
        ])
        clearTimeout(timer)

        const latencyMs = Date.now() - t0

        if (!statsRes.ok) throw new Error(`stats HTTP ${statsRes.status}`)

        const stats = await statsRes.json()

        // 计算负载百分比（active_peers / max_peers，以 peer 数为主要指标）
        const { data: maxPeersRow } = await admin
          .from('vpn_servers').select('max_peers').eq('id', server.id).single()

        const maxPeers   = maxPeersRow?.max_peers ?? 200
        const loadPct    = Math.round((stats.active_peers / maxPeers) * 100)

        // 综合状态：服务器自报 degraded 或延迟 > 500ms 时降级
        let portalStatus: string = stats.status
        if (latencyMs > 500) portalStatus = 'degraded'

        await admin.from('vpn_servers').update({
          status:         portalStatus,
          latency_ms:     latencyMs,
          active_peers:   stats.active_peers,
          load_percent:   Math.min(100, loadPct),
          cpu_percent:    stats.cpu_percent,
          mem_percent:    stats.mem_percent,
          bandwidth_mbps: stats.bw_tx_mbps + stats.bw_rx_mbps,
          last_checked_at: new Date().toISOString(),
        }).eq('id', server.id)

        results.push({ server: server.name, success: true })
      } catch (e: any) {
        // 连接失败 → 标记 offline
        await admin.from('vpn_servers').update({
          status:         'offline',
          latency_ms:     null,
          last_checked_at: new Date().toISOString(),
        }).eq('id', server.id)

        results.push({ server: server.name, success: false, error: e.message })
      }
    })
  )

  return NextResponse.json({
    synced:    results.filter(r => r.success).length,
    failed:    results.filter(r => !r.success).length,
    results,
    timestamp: new Date().toISOString(),
  })
}
