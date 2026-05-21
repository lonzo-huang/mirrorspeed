import { createAdminClient } from '@/lib/supabase/server'
import { createClient } from '@supabase/supabase-js'
import { decryptKey } from '@/lib/clash'
import { generateWgConf } from '@/lib/wireguard'
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

// GET /api/mobile/configs?device_id=<optional>
// 返回用户所有（或指定）设备的全部节点 WireGuard 配置
// Response: { devices: [{ id, label, servers: [{ id, display_name, flag_emoji, location, latency_ms?, wg_conf }] }] }
export async function GET(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const admin    = createAdminClient()
  const deviceId = req.nextUrl.searchParams.get('device_id')

  // 验证订阅
  const { data: sub } = await admin
    .from('subscriptions')
    .select('status')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()

  if (!sub) return NextResponse.json({ error: '订阅已过期' }, { status: 403 })

  // 拉取设备列表
  const devQuery = admin
    .from('vpn_devices')
    .select('id, device_label')
    .eq('user_id', user.id)
    .eq('is_active', true)

  if (deviceId) devQuery.eq('id', deviceId)
  const { data: devices } = await devQuery

  if (!devices?.length) return NextResponse.json({ devices: [] })

  // 拉取所有相关 peer（含服务器信息）
  const deviceIds = devices.map(d => d.id)
  const { data: peers } = await admin
    .from('vpn_device_peers')
    .select(`
      device_id, private_key_enc, preshared_key_enc, vpn_ip,
      server:vpn_servers(id, display_name, flag_emoji, location, endpoint, port, public_key)
    `)
    .in('device_id', deviceIds)
    .eq('is_active', true)

  // 组装响应
  const result = devices.map(dev => {
    const devPeers = (peers ?? []).filter(p => p.device_id === dev.id)
    const servers  = devPeers.map(p => {
      const srv = (p as any).server
      if (!srv) return null
      const wgConf = generateWgConf({
        clientPrivateKey: decryptKey(p.private_key_enc),
        clientIp:         p.vpn_ip.includes('/') ? p.vpn_ip : `${p.vpn_ip}/32`,
        serverPublicKey:  srv.public_key,
        presharedKey:     decryptKey(p.preshared_key_enc),
        serverEndpoint:   srv.endpoint,
        serverPort:       srv.port,
      })
      return {
        id:           srv.id,
        display_name: srv.display_name,
        flag_emoji:   srv.flag_emoji ?? '',
        location:     srv.location   ?? '',
        endpoint:     srv.endpoint,
        port:         srv.port,
        wg_conf:      wgConf,
      }
    }).filter(Boolean)

    return { id: dev.id, label: dev.device_label, servers }
  })

  return NextResponse.json({ devices: result })
}
