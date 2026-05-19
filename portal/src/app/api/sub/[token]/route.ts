import { createAdminClient } from '@/lib/supabase/server'
import { generateClashConfig, decryptKey, type ServerPeerConfig } from '@/lib/clash'
import { NextRequest, NextResponse } from 'next/server'

// GET /api/sub/:token — Clash 订阅接口（多服务器版）
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ token: string }> }
) {
  const { token } = await params
  const admin = createAdminClient()

  // 查找 token 对应的设备（含订阅状态）
  const { data: device } = await admin
    .from('vpn_devices')
    .select(`
      id, device_label, sub_token, is_active,
      subscription:subscriptions(status, expires_at)
    `)
    .eq('sub_token', token)
    .eq('is_active', true)
    .single()

  if (!device) {
    return new NextResponse('# 订阅链接无效或已停用\n', {
      status: 404,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    })
  }

  const sub = (device as any).subscription
  if (!sub || sub.status !== 'active') {
    return new NextResponse(
      '# 订阅已过期，请前往 Portal 续费\n# Subscription expired. Please renew at the portal.\n',
      { status: 403, headers: { 'Content-Type': 'text/plain; charset=utf-8' } }
    )
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
    .eq('device_id', device.id)
    .eq('is_active', true)
    .order('server(sort_order)', { ascending: true })

  if (!devicePeers || devicePeers.length === 0) {
    return new NextResponse('# 未找到可用服务器配置\n', {
      status: 503,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    })
  }

  // 构建每个服务器的 Peer 配置（仅包含 online/degraded 的服务器）
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

  // 异步更新最后访问时间
  admin.from('vpn_devices')
    .update({ last_handshake_at: new Date().toISOString() })
    .eq('id', device.id)
    .then()

  const expiresUnix = sub.expires_at
    ? Math.floor(new Date(sub.expires_at).getTime() / 1000)
    : 0

  return new NextResponse(yamlContent, {
    headers: {
      'Content-Type':        'text/yaml; charset=utf-8',
      'Content-Disposition': `attachment; filename="enterprise-vpn.yaml"`,
      // Clash 读取此 header 显示流量和到期信息
      'Subscription-Userinfo': `upload=0; download=0; total=0; expire=${expiresUnix}`,
      'Profile-Update-Interval': '24',  // 建议 Clash 每 24 小时自动更新
      'Cache-Control': 'no-cache, no-store',
      'Pragma':        'no-cache',
    },
  })
}
