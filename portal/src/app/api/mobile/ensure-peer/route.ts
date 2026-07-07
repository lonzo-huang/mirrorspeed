import { createAdminClient } from '@/lib/supabase/server'
import { createClient } from '@supabase/supabase-js'
import { ensureDeviceCrypto } from '@/lib/device-crypto'
import { NextRequest, NextResponse } from 'next/server'
import type { Database } from '@/types/database.types'

// POST /api/mobile/ensure-peer
// Body: { device_id?: string, server_ids?: string[] }
//
// 按需在目标服务器上添加该设备的 peer（不预建、不生成密钥）。
// 客户端连接某节点前调用（单台）；打开节点列表时批量预热（全部）。幂等。

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

export async function POST(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  let body: { device_id?: string; server_ids?: string[] } = {}
  try { body = await req.json() } catch { /* empty body ok */ }

  const admin = createAdminClient()

  // ── 设备（指定或该用户全部活跃设备）─────────────────────────
  const devQuery = admin.from('vpn_devices').select('id').eq('user_id', user.id).eq('is_active', true)
  if (body.device_id) devQuery.eq('id', body.device_id)
  const { data: devicesRaw } = await devQuery
  let devices = (devicesRaw ?? []) as Array<{ id: string }>
  if (!devices.length) return NextResponse.json({ error: 'No device' }, { status: 404 })

  // 配额挂起的设备不重建 peer：否则 vpn-api 的自愈会把 0.0.0.0 改回真实 IP，绕过封禁。
  // 付费用户永不挂起，无需过滤；恢复由 sync-servers 配额任务负责。
  const { data: sub } = await admin
    .from('subscriptions').select('id').eq('user_id', user.id).eq('status', 'active').maybeSingle()
  if (!sub) {
    const { data: suspRows } = await (admin.from('vpn_device_peers') as any)
      .select('device_id').eq('is_suspended', true).in('device_id', devices.map(d => d.id))
    const suspended = new Set<string>(((suspRows ?? []) as any[]).map(r => r.device_id))
    if (suspended.size) devices = devices.filter(d => !suspended.has(d.id))
    if (!devices.length) {
      return NextResponse.json({ ensured: 0, total: 0, suspended: true })
    }
  }

  // ── 目标服务器（指定或全部活跃）─────────────────────────────
  let srvQuery = (admin.from('vpn_servers') as any)
    .select('id, api_url, api_secret').eq('is_active', true)
  if (body.server_ids?.length) srvQuery = srvQuery.in('id', body.server_ids)
  const { data: serversRaw } = await srvQuery
  const servers = (serversRaw ?? []) as Array<{ id: string; api_url: string; api_secret: string | null }>

  const results: Array<{ device_id: string; server_id: string; ok: boolean; detail?: string }> = []

  for (const dev of devices) {
    const crypto = await ensureDeviceCrypto(admin, dev.id)
    if (!crypto) { results.push({ device_id: dev.id, server_id: '*', ok: false, detail: 'crypto failed' }); continue }
    const ipNoMask = crypto.vpnIp.split('/')[0]

    await Promise.all(servers.map(async srv => {
      if (!srv.api_url || !srv.api_secret) {
        results.push({ device_id: dev.id, server_id: srv.id, ok: false, detail: 'no api' }); return
      }
      // 1) 远程 ensure（awg set 该公钥）
      try {
        const resp = await fetch(`${srv.api_url}/peers/ensure`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-API-Secret': srv.api_secret },
          body: JSON.stringify({
            public_key: crypto.publicKey,
            vpn_ip:     ipNoMask,
            peer_name:  `ms-${dev.id}`,
          }),
          signal: AbortSignal.timeout(8000),
        })
        if (!resp.ok) {
          const t = await resp.text()
          results.push({ device_id: dev.id, server_id: srv.id, ok: false, detail: `vpn-api ${resp.status}: ${t.slice(0,120)}` })
          return
        }
      } catch (e: any) {
        results.push({ device_id: dev.id, server_id: srv.id, ok: false, detail: String(e?.message ?? e) })
        return
      }

      // 2) 台账（ratelimit / GC 用）：幂等 upsert（不受并发插入竞态影响）
      await (admin.from('vpn_device_peers') as any).upsert({
        device_id:         dev.id,
        server_id:         srv.id,
        user_id:           user.id,
        peer_name:         `ms-${dev.id}`,
        public_key:        crypto.publicKey,
        private_key_enc:   crypto.privateKeyEnc,
        preshared_key_enc: '',
        vpn_ip:            crypto.vpnIp,
        is_active:         true,
        provisioned:       true,
        last_seen_at:      new Date().toISOString(),
      }, {
        onConflict: 'device_id,server_id',
      })
      results.push({ device_id: dev.id, server_id: srv.id, ok: true })
    }))
  }

  const okCount = results.filter(r => r.ok).length
  return NextResponse.json({ ensured: okCount, total: results.length, results })
}
