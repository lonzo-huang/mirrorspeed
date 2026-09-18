/**
 * GET /api/admin/usage-insights?days=14
 * 分时洞察：读 usage_snapshots，按北京时间小时(0-23)聚合最近 N 天，
 * 每个节点输出每小时的平均在线（付费/免费）与峰值；全网 = 各节点平均之和。
 * 节点不可达时的采样不计入（否则会把平均值拉低）。仅 admin 可访问。
 */
import { createAdminClient, getUser } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

async function requireAdmin() {
  const user = await getUser()
  if (!user) return { ok: false as const, status: 401 }
  const admin = createAdminClient()
  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if ((profile as any)?.role !== 'admin') return { ok: false as const, status: 403 }
  return { ok: true as const, admin }
}

type Acc = { paid: number; free: number; peak: number; n: number }
const empty24 = (): Acc[] => Array.from({ length: 24 }, () => ({ paid: 0, free: 0, peak: 0, n: 0 }))
const r1 = (x: number) => Math.round(x * 10) / 10

export async function GET(req: Request) {
  const gate = await requireAdmin()
  if (!gate.ok) return NextResponse.json({ error: 'Forbidden' }, { status: gate.status })
  const admin = gate.admin as any

  const days = Math.min(Math.max(parseInt(new URL(req.url).searchParams.get('days') ?? '14') || 14, 1), 90)
  const since = new Date(Date.now() - days * 86400_000).toISOString()

  // 分页拉取（PostgREST 单次上限 1000 行）
  const rows: any[] = []
  for (let from = 0; ; from += 1000) {
    const { data, error } = await admin.from('usage_snapshots')
      .select('server_id, bucket_hour, online_paid, online_free, online_super, online_total, captured_at')
      .gte('captured_at', since).eq('reachable', true)
      .order('captured_at', { ascending: true })
      .range(from, from + 999)
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    rows.push(...(data ?? []))
    if (!data || data.length < 1000) break
  }

  const byServer = new Map<string, Acc[]>()
  for (const r of rows) {
    const h = r.bucket_hour
    if (h == null || h < 0 || h > 23) continue
    let arr = byServer.get(r.server_id)
    if (!arr) byServer.set(r.server_id, (arr = empty24()))
    const b = arr[h]
    b.paid += (r.online_paid ?? 0) + (r.online_super ?? 0)   // 超级并入付费
    b.free += r.online_free ?? 0
    b.peak = Math.max(b.peak, r.online_total ?? 0)
    b.n += 1
  }

  const servers = Array.from(byServer.entries()).map(([server_id, arr]) => ({
    server_id,
    hours: arr.map((b, hour) => ({
      hour,
      paid: b.n ? r1(b.paid / b.n) : 0,
      free: b.n ? r1(b.free / b.n) : 0,
      peak: b.peak,
      samples: b.n,
    })),
  }))

  // 全网 = 各节点该小时平均之和；峰值取各节点峰值之和（上界近似）
  const all = Array.from({ length: 24 }, (_, hour) => {
    let paid = 0, free = 0, peak = 0, samples = 0
    for (const s of servers) {
      const b = s.hours[hour]
      paid += b.paid; free += b.free; peak += b.peak; samples += b.samples
    }
    return { hour, paid: r1(paid), free: r1(free), peak, samples }
  })

  const first = rows[0]?.captured_at ?? null
  return NextResponse.json({
    days, total_samples: rows.length, first_sample_at: first,
    tz: 'Asia/Shanghai (UTC+8)', all, servers,
  })
}
