import { createAdminClient } from '@/lib/supabase/server'
import { createClient } from '@supabase/supabase-js'
import { NextRequest, NextResponse } from 'next/server'
import type { Database } from '@/types/database.types'

// 从 Bearer Token 创建 Supabase 客户端并验证用户
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

// POST /api/mobile/device
// 移动客户端调用：用设备指纹注册/获取设备，返回 device_id
// Body: { platform: 'ios'|'android'|'windows', device_name: string, device_fingerprint: string }
export async function POST(req: NextRequest) {
  const user = await getUserFromBearer(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const admin = createAdminClient()

  // 检查活跃订阅
  const { data: sub } = await admin
    .from('subscriptions')
    .select('id, status')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()

  if (!sub) return NextResponse.json({ error: '无活跃订阅' }, { status: 403 })

  const body = await req.json().catch(() => ({}))
  const { platform, device_name, device_fingerprint } = body as {
    platform: string; device_name: string; device_fingerprint: string
  }

  if (!platform || !device_name || !device_fingerprint) {
    return NextResponse.json({ error: '缺少必填字段' }, { status: 400 })
  }

  // 检查同一用户是否已有相同指纹的设备
  const { data: existing } = await admin
    .from('vpn_devices')
    .select('id, device_label, sub_token')
    .eq('user_id', user.id)
    .eq('device_fingerprint', device_fingerprint)
    .eq('is_active', true)
    .maybeSingle()

  if (existing) {
    return NextResponse.json({ device_id: existing.id, device_label: existing.device_label, sub_token: existing.sub_token })
  }

  // 检查设备数量上限（2 台）
  const { count } = await admin
    .from('vpn_devices')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .eq('is_active', true)

  if ((count ?? 0) >= 2) {
    return NextResponse.json({ error: '设备数量已达上限（2台），请在网页端删除旧设备后再试' }, { status: 409 })
  }

  // 通过内部 API 创建设备（复用 devices route 的逻辑）
  const createRes = await fetch(`${process.env.NEXT_PUBLIC_APP_URL}/api/devices`, {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': req.headers.get('authorization') ?? '',
      // 传递 cookie 给内部 API — 移动端没有 cookie，用内部 header 绕过
      'x-mobile-user-id': user.id,
    },
    body: JSON.stringify({ label: device_name, os: platform, device_fingerprint }),
  })

  // 如果内部 API 因 cookie 验证失败，直接在这里创建
  if (!createRes.ok) {
    const subToken = crypto.randomUUID().replace(/-/g, '')
    const { data: dev, error } = await admin.from('vpn_devices').insert({
      user_id:            user.id,
      subscription_id:    sub.id,
      device_label:       device_name,
      os_hint:            platform,
      device_fingerprint,
      sub_token:          subToken,
      is_active:          true,
    }).select('id, device_label, sub_token').single()

    if (error || !dev) return NextResponse.json({ error: '创建设备失败' }, { status: 500 })

    // 在所有活跃服务器上创建 peer
    const { data: servers } = await admin
      .from('vpn_servers').select('id, name, api_url').eq('is_active', true)

    const VPN_API_SECRET = process.env.VPN_API_SECRET!
    const { encryptKey } = await import('@/lib/clash')

    await Promise.allSettled((servers ?? []).map(async server => {
      const uid8       = user.id.replace(/-/g, '').slice(0, 8)
      const deviceShort = crypto.randomUUID().replace(/-/g, '').slice(0, 4)
      const peerName   = `u${uid8}_${deviceShort}_${server.name.toLowerCase()}`

      const res = await fetch(`${server.api_url}/peers`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', 'X-API-Secret': VPN_API_SECRET },
        body:    JSON.stringify({ peer_name: peerName }),
      })
      if (!res.ok) return

      const peerInfo = await res.json()
      await admin.from('vpn_device_peers').insert({
        device_id:         dev.id,
        server_id:         server.id,
        user_id:           user.id,
        peer_name:         peerName,
        public_key:        peerInfo.public_key,
        private_key_enc:   encryptKey(peerInfo.private_key),
        preshared_key_enc: encryptKey(peerInfo.preshared_key),
        vpn_ip:            peerInfo.vpn_ip,
      })
    }))

    return NextResponse.json({ device_id: dev.id, device_label: dev.device_label, sub_token: dev.sub_token })
  }

  const dev = await createRes.json()
  return NextResponse.json({ device_id: dev.id, device_label: dev.device_label, sub_token: dev.sub_token })
}
