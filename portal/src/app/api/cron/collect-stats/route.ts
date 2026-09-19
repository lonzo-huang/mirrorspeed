/**
 * GET|POST /api/cron/collect-stats[?window=15]
 * 定时采集：记录每个节点在采集窗口内活跃的用户数（按套餐分类）+ 资源指标，
 * 写入 usage_snapshots，供 admin 分时洞察使用。
 *
 * 在线口径：最近 window 分钟内有握手（WireGuard 连接中约每 2 分钟握手一次），
 * window 取采集间隔（默认 15），这样两次采集之间短暂上线的用户也不会漏掉。
 *
 * 鉴权：Authorization: Bearer <STATS_CRON_SECRET 或 CRON_SECRET>
 * 触发：cron-job.org 每 15 分钟调用。bucket_* 按北京时间(UTC+8)写入。
 */
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'
export const maxDuration = 60

function authorized(req: NextRequest) {
  const auth = req.headers.get('authorization') ?? ''
  const secrets = [process.env.STATS_CRON_SECRET, process.env.CRON_SECRET].filter(Boolean)
  return secrets.length > 0 && secrets.some(s => auth === `Bearer ${s}`)
}

async function collect(req: NextRequest) {
  if (!authorized(req)) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const windowMin = Math.min(Math.max(parseInt(new URL(req.url).searchParams.get('window') ?? '15') || 15, 3), 60)
  const windowMs = windowMin * 60_000

  const admin = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false } },
  ) as any

  const [{ data: devs }, { data: subs }, { data: cfg }, { data: servers }] = await Promise.all([
    admin.from('vpn_devices').select('public_key, user_id').not('public_key', 'is', null),
    admin.from('subscriptions').select('user_id').eq('status', 'active'),
    admin.from('app_config').select('value').eq('key', 'super_user_ids').maybeSingle(),
    admin.from('vpn_servers').select('id, api_url, api_secret').eq('is_active', true),
  ])

  const paidSet = new Set<string>((subs ?? []).map((s: any) => s.user_id))
  let superSet = new Set<string>()
  try { superSet = new Set(JSON.parse(cfg?.value ?? '[]')) } catch { /* ignore */ }
  const tierByKey = new Map<string, 'super' | 'paid' | 'free'>()
  for (const d of devs ?? []) {
    tierByKey.set(d.public_key, superSet.has(d.user_id) ? 'super' : paidSet.has(d.user_id) ? 'paid' : 'free')
  }

  // 北京时间分桶
  const now = new Date()
  const bj = new Date(now.getTime() + 8 * 3600_000)
  const bucket = {
    bucket_date: bj.toISOString().slice(0, 10),
    bucket_hour: bj.getUTCHours(),
    bucket_min: Math.floor(bj.getUTCMinutes() / 15) * 15,
  }
  const captured_at = now.toISOString()

  const rows = await Promise.all((servers ?? []).map(async (srv: any) => {
    const base = { server_id: srv.id, captured_at, ...bucket }
    const down = { ...base, online_total: 0, online_paid: 0, online_free: 0, online_super: 0, reachable: false }
    if (!srv.api_url || !srv.api_secret) return down
    try {
      const headers = { 'X-API-Secret': srv.api_secret }
      const [statsR, peersR] = await Promise.all([
        fetch(`${srv.api_url}/stats`, { headers, signal: AbortSignal.timeout(8000) }),
        fetch(`${srv.api_url}/peers`, { headers, signal: AbortSignal.timeout(8000) }),
      ])
      if (!peersR.ok) return down
      const stats = statsR.ok ? await statsR.json() : null
      const peers: any[] = await peersR.json()
      const t = Date.now()

      let total = 0, paid = 0, free = 0, sup = 0
      for (const p of peers) {
        const hs = p.last_handshake ? Date.parse(p.last_handshake) : NaN
        const age = t - hs
        if (Number.isNaN(hs) || age < -60_000 || age >= windowMs) continue
        total++
        const tier = tierByKey.get(p.public_key) ?? 'free'
        if (tier === 'super') sup++; else if (tier === 'paid') paid++; else free++
      }
      return {
        ...base,
        online_total: total, online_paid: paid, online_free: free, online_super: sup,
        cpu_percent: stats?.cpu_percent ?? null,
        mem_percent: stats?.mem_percent ?? null,
        load_1m: stats?.load_1m ?? null,
        bw_rx_mbps: stats?.bw_rx_mbps ?? null,
        bw_tx_mbps: stats?.bw_tx_mbps ?? null,
        active_peers: stats?.active_peers ?? null,
        reachable: true,
      }
    } catch {
      return down
    }
  }))

  const { error } = await admin.from('usage_snapshots').insert(rows)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // 只保留 90 天
  await admin.from('usage_snapshots').delete().lt('captured_at', new Date(now.getTime() - 90 * 86400_000).toISOString())

  return NextResponse.json({
    ok: true, captured_at, bucket, window_min: windowMin,
    nodes: rows.length, reachable: rows.filter(r => r.reachable).length,
    online_total: rows.reduce((s, r) => s + r.online_total, 0),
  })
}

export const GET = collect
export const POST = collect
