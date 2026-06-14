import { createAdminClient, getUser } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

// GET /api/admin/servers-overview
// 管理后台数据源：实时拉取每台 active 服务器的 /stats + /peers，并为每个 peer
// 标注归属（设备标签 + 用户邮箱）。仅 profiles.role='admin' 可访问。

async function requireAdmin() {
  const user = await getUser()
  if (!user) return { ok: false as const, status: 401 }
  const admin = createAdminClient()
  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if ((profile as any)?.role !== 'admin') return { ok: false as const, status: 403 }
  return { ok: true as const, admin }
}

export async function GET() {
  const gate = await requireAdmin()
  if (!gate.ok) return NextResponse.json({ error: 'Forbidden' }, { status: gate.status })
  const admin = gate.admin

  // 归属映射：public_key → {device_label, email}
  const [{ data: devs }, { data: profiles }, { data: servers }] = await Promise.all([
    (admin.from('vpn_devices') as any).select('public_key, device_label, user_id').not('public_key', 'is', null),
    admin.from('profiles').select('id, email'),
    admin.from('vpn_servers')
      .select('id, name, display_name, location, flag_emoji, endpoint, api_url, api_secret, status, last_checked_at, active_peers, load_percent, max_peers')
      .eq('is_active', true).order('sort_order'),
  ])
  const emailById = new Map<string, string>((profiles ?? []).map((p: any) => [p.id, p.email]))
  const ownerByKey = new Map<string, { device_label: string; email: string }>()
  for (const d of (devs ?? []) as any[]) {
    ownerByKey.set(d.public_key, { device_label: d.device_label ?? '', email: emailById.get(d.user_id) ?? '' })
  }

  const result = await Promise.all((servers ?? []).map(async (srv: any) => {
    const base: any = {
      id: srv.id, name: srv.name, display_name: srv.display_name, location: srv.location,
      flag_emoji: srv.flag_emoji, endpoint: srv.endpoint,
      db_status: srv.status, last_checked_at: srv.last_checked_at,
      max_peers: srv.max_peers,
    }
    if (!srv.api_url || !srv.api_secret) return { ...base, online: false, error: 'no api', peers: [] }
    try {
      const headers = { 'X-API-Secret': srv.api_secret }
      const [statsR, peersR] = await Promise.all([
        fetch(`${srv.api_url}/stats`, { headers, signal: AbortSignal.timeout(8000) }),
        fetch(`${srv.api_url}/peers`, { headers, signal: AbortSignal.timeout(8000) }),
      ])
      const stats = statsR.ok ? await statsR.json() : null
      const peersRaw = peersR.ok ? await peersR.json() : []
      const now = Date.now()
      let fast = 0, relay = 0
      const peers = (peersRaw as any[]).map(p => {
        const owner = ownerByKey.get(p.public_key)
        const hs = p.last_handshake ? Date.parse(p.last_handshake) : NaN
        const age = now - hs   // 距上次握手的毫秒数
        // 在线 = 最近 3 分钟内握手；并拒绝"未来时间"(age<0，时区错位的脏数据)避免误判在线
        const online = !Number.isNaN(hs) && age >= -60_000 && age < 180_000
        // 模式判定：中继(强力)= endpoint 为回环(wstunnel)；否则直连(快速)
        const ep = (p.endpoint ?? '') as string
        const isRelay = ep.startsWith('127.0.0.1') || ep.startsWith('::1') || ep.startsWith('[::1]')
        let mode: 'fast' | 'relay' | 'offline' = 'offline'
        if (online && ep) { mode = isRelay ? 'relay' : 'fast'; if (isRelay) relay++; else fast++ }
        return {
          public_key: (p.public_key ?? '').slice(0, 16),
          vpn_ip: p.vpn_ip, active: p.active,
          last_handshake: p.last_handshake,
          online, mode,
          rx_bytes: p.rx_bytes ?? 0, tx_bytes: p.tx_bytes ?? 0,
          device_label: owner?.device_label ?? '',
          email: owner?.email ?? '(未知/孤儿)',
        }
      })
      const onlineCount = fast + relay
      const summary = { online: onlineCount, fast, relay, fast_pct: onlineCount > 0 ? Math.round(fast / onlineCount * 100) : 0 }
      return { ...base, online: true, stats, peers, summary }
    } catch (e: any) {
      return { ...base, online: false, error: String(e?.message ?? e), peers: [] }
    }
  }))

  return NextResponse.json({ servers: result, fetched_at: new Date().toISOString() })
}
