import { createServerSupabaseClient, createAdminClient } from '@/lib/supabase/server'
import { decryptKey } from '@/lib/clash'
import { generateWgConf } from '@/lib/wireguard'
import { NextRequest, NextResponse } from 'next/server'
import QRCode from 'qrcode'

// GET /api/devices/:id/qr?server=<serverId>
// 返回 WireGuard 配置的二维码 PNG（供手机 WireGuard App 扫码导入）
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

  const { data: device } = await supabase
    .from('vpn_devices')
    .select('id, subscription:subscriptions(status)')
    .eq('id', deviceId).eq('user_id', user.id).eq('is_active', true)
    .single()

  if (!device) return new NextResponse('设备不存在', { status: 404 })
  if ((device as any).subscription?.status !== 'active') {
    return new NextResponse('订阅已过期', { status: 403 })
  }

  const { data: peer } = await admin
    .from('vpn_device_peers')
    .select('private_key_enc, preshared_key_enc, vpn_ip, server:vpn_servers(public_key, endpoint, port)')
    .eq('device_id', deviceId)
    .eq('server_id', serverId)
    .eq('is_active', true)
    .single()

  if (!peer) return new NextResponse('配置不存在', { status: 404 })

  const srv = (peer as any).server
  const conf = generateWgConf({
    clientPrivateKey: decryptKey(peer.private_key_enc),
    clientIp:         peer.vpn_ip.includes('/') ? peer.vpn_ip : `${peer.vpn_ip}/32`,
    serverPublicKey:  srv.public_key,
    presharedKey:     decryptKey(peer.preshared_key_enc),
    serverEndpoint:   srv.endpoint,
    serverPort:       srv.port,
  })

  // WireGuard App 扫码格式：直接包含 .conf 文本内容
  const png = await QRCode.toBuffer(conf, {
    errorCorrectionLevel: 'L',  // L 级纠错 = 最大数据容量（conf 内容较长）
    width: 480,
    margin: 2,
    color: { dark: '#000000', light: '#ffffff' },
  })

  return new NextResponse(png, {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'no-store',
    },
  })
}
