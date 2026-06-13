import { NextRequest, NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

// GET /api/vpn/ratelimit-sync
//
// 由各 VPN 服务器的 ms-ratelimit-sync 脚本（systemd timer，~60s）调用。
// 鉴权：请求头 X-API-Secret 必须等于某台 vpn_servers.api_secret —— Portal 据此
// 反查出是哪台服务器，无需服务器自报名字。
//
// 返回该服务器上：
//   - 三档限速值（Mbit，来自 app_config；0 = 不限速）
//   - 免费 / 付费 / 超级 用户的内网 IP 列表（用于服务器侧 ipset 打标）
//
// 分级：super_user_ids 命中 → 超级；否则有 active 订阅 / 邀请奖励期 → 付费；否则 → 免费。
function stripMask(ip: string): string {
  return ip.split('/')[0]
}

export async function GET(req: NextRequest) {
  const secret = req.headers.get('x-api-secret') ?? ''
  if (!secret) {
    return NextResponse.json({ error: 'Missing X-API-Secret' }, { status: 401 })
  }

  const admin = createAdminClient()

  // 1) 凭 api_secret 反查服务器
  const { data: server } = await (admin.from('vpn_servers') as any)
    .select('id, name')
    .eq('api_secret', secret)
    .eq('is_active', true)
    .maybeSingle()

  if (!server) {
    return NextResponse.json({ error: 'Unknown api_secret' }, { status: 401 })
  }

  // 2) 限速值（app_config）
  const { data: cfgRows } = await admin
    .from('app_config' as any)
    .select('key, value')
    .in('key', ['ratelimit_free_mbit', 'ratelimit_paid_mbit', 'ratelimit_super_mbit', 'super_user_ids'])
  const cfg = new Map((cfgRows ?? []).map((r: any) => [r.key, r.value]))
  const freeMbit  = parseInt(cfg.get('ratelimit_free_mbit')  ?? '4',  10)
  const paidMbit  = parseInt(cfg.get('ratelimit_paid_mbit')  ?? '10', 10)
  const superMbit = parseInt(cfg.get('ratelimit_super_mbit') ?? '0',  10)
  let superIds: string[] = []
  try { superIds = JSON.parse(cfg.get('super_user_ids') ?? '[]') } catch { /* ignore */ }
  const superSet = new Set(superIds)

  // 3) 本机所有活跃 peer（vpn_ip + user_id）
  const { data: peers } = await (admin.from('vpn_device_peers') as any)
    .select('vpn_ip, user_id')
    .eq('server_id', server.id)
    .eq('is_active', true)

  const peerList = (peers ?? []) as Array<{ vpn_ip: string; user_id: string }>
  const userIds  = Array.from(new Set(peerList.map(p => p.user_id)))

  // 4) 付费判定：active 订阅 OR 邀请奖励期内
  const paidUsers = new Set<string>()
  if (userIds.length > 0) {
    const [{ data: subs }, { data: profiles }] = await Promise.all([
      admin.from('subscriptions').select('user_id').in('user_id', userIds).eq('status', 'active'),
      admin.from('profiles').select('id, referral_bonus_expires_at').in('id', userIds),
    ])
    for (const s of (subs ?? []) as any[]) paidUsers.add(s.user_id)
    const now = Date.now()
    for (const p of (profiles ?? []) as any[]) {
      if (p.referral_bonus_expires_at && new Date(p.referral_bonus_expires_at).getTime() > now) {
        paidUsers.add(p.id)
      }
    }
  }

  // 5) 分桶
  const free_ips: string[] = []
  const paid_ips: string[] = []
  const super_ips: string[] = []
  for (const p of peerList) {
    const ip = stripMask(p.vpn_ip)
    if (!ip) continue
    if (superSet.has(p.user_id))      super_ips.push(ip)
    else if (paidUsers.has(p.user_id)) paid_ips.push(ip)
    else                               free_ips.push(ip)
  }

  return NextResponse.json(
    {
      server: server.name,
      free_mbit: freeMbit,
      paid_mbit: paidMbit,
      super_mbit: superMbit,
      free_ips,
      paid_ips,
      super_ips,
    },
    { headers: { 'Cache-Control': 'no-store' } },
  )
}
