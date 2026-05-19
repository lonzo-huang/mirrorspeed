import { createServerSupabaseClient, createAdminClient } from '@/lib/supabase/server'
import { generateClashConfig, decryptKey, type ServerPeerConfig } from '@/lib/clash'
import { NextRequest, NextResponse } from 'next/server'

// GET /api/devices/:id/clash-config — 已登录用户直接下载 Clash 配置文件
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: deviceId } = await params
  const supabase = await createServerSupabaseClient()
  const admin    = createAdminClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.redirect(new URL('/login', _req.url))
  }

  // 验证设备归属当前用户
  const { data: device } = await supabase
    .from('vpn_devices')
    .select('id, device_label, sub_token, is_active, subscription:subscriptions(status, expires_at)')
    .eq('id', deviceId)
    .eq('user_id', user.id)
    .eq('is_active', true)
    .single()

  if (!device) {
    return new NextResponse('# 设备不存在或无权限\n', {
      status: 404,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    })
  }

  const sub = (device as any).subscription
  if (!sub || sub.status !== 'active') {
    return new NextResponse('# 订阅已过期，请前往 Portal 续费\n', {
      status: 403,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    })
  }

  // 拉取该设备在所有活跃服务器上的 Peer（含服务器元信息）
  const { data: devicePeers } = await admin
    .from('vpn_device_peers')
    .select(`
      private_key_enc, preshared_key_enc, vpn_ip,
      server:vpn_servers(
        display_name, flag_emoji, endpoint, port, public_key, status, sort_order
      )
    `)
    .eq('device_id', deviceId)
    .eq('is_active', true)
    .order('server(sort_order)', { ascending: true })

  if (!devicePeers || devicePeers.length === 0) {
    return new NextResponse('# 未找到可用服务器配置\n', {
      status: 503,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    })
  }

  const peerConfigs: ServerPeerConfig[] = devicePeers
    .filter(p => {
      const srv = p.server as any
      return srv && srv.status !== 'offline'
    })
    .map(p => {
      const srv = p.server as any
      return {
        serverName:       `${srv.flag_emoji} ${srv.display_name}`,
        serverEndpoint:   srv.endpoint,
        serverPort:       srv.port,
        serverPublicKey:  srv.public_key,
        clientPrivateKey: decryptKey(p.private_key_enc),
        clientIp:         p.vpn_ip,
        presharedKey:     decryptKey(p.preshared_key_enc),
      }
    })

  if (peerConfigs.length === 0) {
    return new NextResponse('# 所有服务器当前离线，请稍后再试\n', {
      status: 503,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    })
  }

  const yamlContent = generateClashConfig(device.device_label, peerConfigs)
  const filename    = `vpn-${device.device_label.replace(/[^a-zA-Z0-9一-龥]/g, '_')}.yaml`

  return new NextResponse(yamlContent, {
    headers: {
      'Content-Type':        'text/yaml; charset=utf-8',
      'Content-Disposition': `attachment; filename="${encodeURIComponent(filename)}"`,
      'Cache-Control':       'no-cache, no-store',
      'Pragma':              'no-cache',
    },
  })
}
