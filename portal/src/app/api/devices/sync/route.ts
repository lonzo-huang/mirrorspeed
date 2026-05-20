import { createAdminClient } from '@/lib/supabase/server'
import { createServerSupabaseClient } from '@/lib/supabase/server'
import { encryptKey } from '@/lib/clash'
import { NextRequest, NextResponse } from 'next/server'

const VPN_API_SECRET = process.env.VPN_API_SECRET!

// POST /api/devices/sync
// 将所有活跃设备同步到所有活跃服务器（新增节点后调用）
// 只创建缺失的 peer，不删除现有的
// 需要 admin 权限
export async function POST(req: NextRequest) {
  const supabase = await createServerSupabaseClient()
  const admin    = createAdminClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if (profile?.role !== 'admin') {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  // 可选：只同步指定 serverId（添加新节点时使用）
  const body = await req.json().catch(() => ({}))
  const targetServerId: string | null = body.server_id ?? null

  // 拉取所有活跃服务器
  const serversQuery = admin.from('vpn_servers').select('id, name, api_url').eq('is_active', true)
  if (targetServerId) serversQuery.eq('id', targetServerId)
  const { data: servers } = await serversQuery

  if (!servers || servers.length === 0) {
    return NextResponse.json({ error: '无活跃服务器' }, { status: 404 })
  }

  // 拉取所有活跃设备（含有效订阅）
  const { data: devices } = await admin
    .from('vpn_devices')
    .select('id, user_id, subscription:subscriptions(status)')
    .eq('is_active', true)

  const activeDevices = (devices ?? []).filter(d => (d as any).subscription?.status === 'active')

  // 拉取已存在的 device_peer 组合（避免重复创建）
  const { data: existingPeers } = await admin
    .from('vpn_device_peers')
    .select('device_id, server_id')
    .eq('is_active', true)

  const existingSet = new Set(
    (existingPeers ?? []).map(p => `${p.device_id}:${p.server_id}`)
  )

  let created = 0
  let failed  = 0
  const errors: string[] = []

  for (const server of servers) {
    for (const device of activeDevices) {
      const key = `${device.id}:${server.id}`
      if (existingSet.has(key)) continue  // 已存在，跳过

      const uid8       = device.user_id.replace(/-/g, '').slice(0, 8)
      const deviceShort = crypto.randomUUID().replace(/-/g, '').slice(0, 4)
      const peerName   = `u${uid8}_${deviceShort}_${server.name.toLowerCase()}`

      try {
        const res = await fetch(`${server.api_url}/peers`, {
          method:  'POST',
          headers: { 'Content-Type': 'application/json', 'X-API-Secret': VPN_API_SECRET },
          body:    JSON.stringify({ peer_name: peerName }),
        })

        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const peerInfo = await res.json()

        await admin.from('vpn_device_peers').insert({
          device_id:         device.id,
          server_id:         server.id,
          user_id:           device.user_id,
          peer_name:         peerName,
          public_key:        peerInfo.public_key,
          private_key_enc:   encryptKey(peerInfo.private_key),
          preshared_key_enc: encryptKey(peerInfo.preshared_key),
          vpn_ip:            peerInfo.vpn_ip,
        })

        existingSet.add(key)
        created++
      } catch (e: any) {
        failed++
        errors.push(`device=${device.id} server=${server.name}: ${e.message}`)
      }
    }
  }

  await admin.from('audit_log').insert({
    user_id: user.id,
    action:  'devices_synced',
    detail:  { created, failed, target_server: targetServerId, errors: errors.slice(0, 20) },
  })

  return NextResponse.json({ ok: true, created, failed, errors: errors.slice(0, 20) })
}
