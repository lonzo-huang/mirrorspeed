import { createAdminClient } from '@/lib/supabase/server'
import { NextRequest, NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

// GET /api/cron/gc-peers
// 闲置 / 残留 peer 回收（P5）。鉴权：Authorization: Bearer <CRON_SECRET>。
//
// 对每台 active 服务器：
//   1) GET {api_url}/peers 列出服务器实际的 peer（public_key + last_handshake）
//   2) 合法集合 = 所有设备的全局公钥（vpn_devices.public_key）
//   3) 删除：
//        - 孤儿 peer：公钥不在合法集合（旧 cross-product 残留 / 手动 employee1）→ 立即删
//        - 闲置 peer：在册但 last_handshake 超过 peer_gc_days 天没握手 → 删（设备回来会自动重新 ensure）
//   4) 删除后把对应 vpn_device_peers 标记 provisioned=false
const CRON_SECRET = process.env.CRON_SECRET

export async function GET(req: NextRequest) {
  const auth = req.headers.get('authorization')
  if (CRON_SECRET && auth !== `Bearer ${CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const admin = createAdminClient()

  // gc 天数
  const { data: cfg } = await admin.from('app_config' as any).select('value').eq('key', 'peer_gc_days').maybeSingle()
  const gcDays = cfg ? parseInt((cfg as any).value, 10) : 30
  const staleBeforeMs = Date.now() - gcDays * 86400_000

  // 合法公钥集合（所有设备全局公钥）
  const { data: devs } = await (admin.from('vpn_devices') as any).select('public_key').not('public_key', 'is', null)
  const validKeys = new Set<string>((devs ?? []).map((d: any) => d.public_key))

  const { data: servers } = await admin
    .from('vpn_servers').select('id, name, api_url, api_secret').eq('is_active', true)

  const out: Array<{ server: string; removed: number; orphans: number; stale: number; error?: string }> = []

  await Promise.allSettled((servers ?? []).map(async (srv: any) => {
    if (!srv.api_secret || !srv.api_url) { out.push({ server: srv.name, removed: 0, orphans: 0, stale: 0, error: 'no api' }); return }
    try {
      // 1) 服务器实际 peer
      const resp = await fetch(`${srv.api_url}/peers`, {
        headers: { 'X-API-Secret': srv.api_secret }, signal: AbortSignal.timeout(8000),
      })
      if (!resp.ok) { out.push({ server: srv.name, removed: 0, orphans: 0, stale: 0, error: `peers ${resp.status}` }); return }
      const peers = await resp.json() as Array<{ public_key: string; last_handshake: string | null }>

      let orphans = 0, stale = 0
      const toRemove: string[] = []
      for (const p of peers) {
        if (!validKeys.has(p.public_key)) {            // 孤儿：不是任何设备的全局公钥
          toRemove.push(p.public_key); orphans++
        } else {                                       // 在册：仅当握手过且超期才回收
          const hs = p.last_handshake ? Date.parse(p.last_handshake) : NaN
          if (!Number.isNaN(hs) && hs < staleBeforeMs) { toRemove.push(p.public_key); stale++ }
        }
      }

      // 3) 逐个移除
      for (const pk of toRemove) {
        try {
          await fetch(`${srv.api_url}/peers/remove`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-API-Secret': srv.api_secret },
            body: JSON.stringify({ public_key: pk }),
            signal: AbortSignal.timeout(6000),
          })
          // 标记 DB（仅在册的；孤儿可能没有 DB 行）
          await (admin.from('vpn_device_peers') as any)
            .update({ provisioned: false }).eq('server_id', srv.id).eq('public_key', pk)
        } catch { /* 单个失败忽略 */ }
      }

      out.push({ server: srv.name, removed: toRemove.length, orphans, stale })
    } catch (e: any) {
      out.push({ server: srv.name, removed: 0, orphans: 0, stale: 0, error: String(e?.message ?? e) })
    }
  }))

  return NextResponse.json({ gc_days: gcDays, servers: out, timestamp: new Date().toISOString() })
}
