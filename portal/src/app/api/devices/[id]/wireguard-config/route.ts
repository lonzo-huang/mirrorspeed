import { createServerSupabaseClient, createAdminClient } from '@/lib/supabase/server'
import { decryptKey } from '@/lib/clash'
import { generateWgConf } from '@/lib/wireguard'
import { NextRequest, NextResponse } from 'next/server'

// GET /api/devices/:id/wireguard-config?server=<serverId>
// 下载指定设备在指定服务器上的 WireGuard .conf 文件
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: deviceId } = await params
  const serverId = req.nextUrl.searchParams.get('server')
  if (!serverId) {
    return NextResponse.json({ error: '缺少 server 参数' }, { status: 400 })
  }

  const supabase = await createServerSupabaseClient()
  const admin    = createAdminClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return new NextResponse('Unauthorized', { status: 401 })

  // 验证设备归属
  const { data: device } = await supabase
    .from('vpn_devices')
    .select('id, device_label, subscription:subscriptions(status)')
    .eq('id', deviceId).eq('user_id', user.id).eq('is_active', true)
    .single()

  if (!device) return new NextResponse('设备不存在或无权限', { status: 404 })
  if ((device as any).subscription?.status !== 'active') {
    return new NextResponse('订阅已过期', { status: 403 })
  }

  // 拉取该设备在指定服务器上的 Peer
  const { data: peer } = await admin
    .from('vpn_device_peers')
    .select('private_key_enc, preshared_key_enc, vpn_ip, server:vpn_servers(public_key, endpoint, port, display_name)')
    .eq('device_id', deviceId)
    .eq('server_id', serverId)
    .eq('is_active', true)
    .single()

  if (!peer) return new NextResponse('未找到该服务器的配置', { status: 404 })

  const srv = (peer as any).server
  const conf = generateWgConf({
    clientPrivateKey: decryptKey(peer.private_key_enc),
    clientIp:         peer.vpn_ip.includes('/') ? peer.vpn_ip : `${peer.vpn_ip}/32`,
    serverPublicKey:  srv.public_key,
    presharedKey:     decryptKey(peer.preshared_key_enc),
    serverEndpoint:   srv.endpoint,
    serverPort:       srv.port,
  })

  const filename = `vpn-${device.device_label.replace(/[^a-zA-Z0-9]/g, '_')}-${srv.display_name.replace(/[^a-zA-Z0-9]/g, '_')}.conf`

  return new NextResponse(conf, {
    headers: {
      'Content-Type':        'text/plain; charset=utf-8',
      'Content-Disposition': `attachment; filename="${encodeURIComponent(filename)}"`,
      'Cache-Control':       'no-store',
    },
  })
}
