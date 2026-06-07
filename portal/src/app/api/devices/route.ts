import { createServerSupabaseClient, createAdminClient } from '@/lib/supabase/server'
import { encryptKey } from '@/lib/clash'
import { buildPeerName } from '@/lib/wireguard'
import { NextRequest, NextResponse } from 'next/server'

// 调用指定服务器的 FastAPI 创建 Peer（使用该服务器自己的 api_secret）
async function createPeerOnServer(
  apiUrl: string,
  secret: string,
  peerName: string
): Promise<{ public_key: string; private_key: string; preshared_key: string; vpn_ip: string }> {
  const res = await fetch(`${apiUrl}/peers`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-API-Secret': secret },
    body: JSON.stringify({ peer_name: peerName }),
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(`Server ${apiUrl} returned ${res.status}: ${err.detail ?? res.statusText}`)
  }
  return res.json()
}

// 调用指定服务器的 FastAPI 删除 Peer
async function deletePeerOnServer(apiUrl: string, secret: string, peerName: string): Promise<void> {
  await fetch(`${apiUrl}/peers/${encodeURIComponent(peerName)}`, {
    method: 'DELETE',
    headers: { 'X-API-Secret': secret },
  })
}

// POST /api/devices — 添加设备（在所有活跃服务器上同时创建 Peer）
export async function POST(req: NextRequest) {
  const supabase = await createServerSupabaseClient()
  const admin    = createAdminClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  // 验证订阅
  const { data: sub } = await supabase
    .from('subscriptions').select('id')
    .eq('user_id', user.id).eq('status', 'active').maybeSingle()
  if (!sub) return NextResponse.json({ error: '请先订阅 VPN 服务' }, { status: 403 })

  // 检查设备数量上限
  const { count } = await supabase
    .from('vpn_devices').select('id', { count: 'exact', head: true })
    .eq('user_id', user.id).eq('is_active', true)
  if ((count ?? 0) >= 2) {
    return NextResponse.json({ error: '已达设备上限（最多 2 台）' }, { status: 400 })
  }

  const { label, os } = await req.json()
  if (!label?.trim()) return NextResponse.json({ error: '设备名称不能为空' }, { status: 400 })

  // 拉取所有活跃服务器
  const { data: servers } = await admin
    .from('vpn_servers')
    .select('id, name, api_url, api_secret')
    .eq('is_active', true)

  if (!servers || servers.length === 0) {
    return NextResponse.json({ error: '当前无可用服务器' }, { status: 503 })
  }

  // 1. 创建 vpn_devices 记录
  const { data: device, error: deviceErr } = await admin
    .from('vpn_devices').insert({
      user_id:         user.id,
      subscription_id: sub.id,
      device_label:    label.trim(),
      os_hint:         os ?? 'windows',
    }).select('id').single()

  if (deviceErr || !device) {
    return NextResponse.json({ error: '设备记录创建失败' }, { status: 500 })
  }

  // 2. 在所有服务器上并发创建 Peer（确定性命名 + per-server secret，与移动端一致）
  const peerResults = await Promise.allSettled(
    servers.map(async (server) => {
      if (!server.api_secret) throw new Error(`VPN server ${server.name} 未配置 api_secret`)
      const peerName = buildPeerName(device.id, server.id)

      const peerInfo = await createPeerOnServer(server.api_url, server.api_secret, peerName)

      const { error } = await admin.from('vpn_device_peers').insert({
        device_id:         device.id,
        server_id:         server.id,
        user_id:           user.id,
        peer_name:         peerName,
        public_key:        peerInfo.public_key,
        private_key_enc:   encryptKey(peerInfo.private_key),
        preshared_key_enc: encryptKey(peerInfo.preshared_key),
        vpn_ip:            peerInfo.vpn_ip,
      })
      // 23505 = 唯一索引冲突：并发已建好同一 (device, server) peer，视为成功
      if (error && (error as { code?: string }).code !== '23505') {
        throw new Error(`DB insert failed for ${server.name}: ${error.message}`)
      }

      return { serverId: server.id, serverName: server.name, peerName }
    })
  )

  const succeeded = peerResults.filter(r => r.status === 'fulfilled')
  const failed    = peerResults.filter(r => r.status === 'rejected')

  // 如果所有服务器都失败，回滚设备记录
  if (succeeded.length === 0) {
    await admin.from('vpn_devices').delete().eq('id', device.id)
    const reasons = failed.map(r => (r as PromiseRejectedResult).reason?.message).join('; ')
    return NextResponse.json({ error: `VPN 服务器通信失败: ${reasons}` }, { status: 502 })
  }

  // 部分失败：记录日志但不回滚（用户仍可用成功的服务器）
  if (failed.length > 0) {
    console.warn(`[devices POST] ${failed.length}/${servers.length} servers failed for device ${device.id}`)
  }

  await admin.from('audit_log').insert({
    user_id: user.id,
    action: 'device_added',
    detail: {
      device_id:    device.id,
      device_label: label,
      os,
      servers_ok:   succeeded.length,
      servers_fail: failed.length,
    },
  })

  return NextResponse.json({ success: true, deviceId: device.id }, { status: 201 })
}

// DELETE /api/devices — 删除设备（从所有服务器删除对应 Peer）
export async function DELETE(req: NextRequest) {
  const supabase = await createServerSupabaseClient()
  const admin    = createAdminClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { deviceId } = await req.json()

  // 确认设备属于当前用户
  const { data: device } = await supabase
    .from('vpn_devices').select('id').eq('id', deviceId).eq('user_id', user.id).single()
  if (!device) return NextResponse.json({ error: '设备不存在或无权限' }, { status: 404 })

  // 拉取该设备的所有 server peers
  const { data: peers } = await admin
    .from('vpn_device_peers')
    .select('peer_name, server:vpn_servers(api_url, api_secret)')
    .eq('device_id', deviceId)
    .eq('is_active', true)

  // 并发从所有服务器删除
  await Promise.allSettled(
    (peers ?? []).map(async (peer) => {
      const apiUrl = (peer.server as any)?.api_url
      const secret = (peer.server as any)?.api_secret
      if (apiUrl && secret) {
        await deletePeerOnServer(apiUrl, secret, peer.peer_name).catch(e =>
          console.error(`[devices DELETE] Failed to delete peer ${peer.peer_name}:`, e)
        )
      }
    })
  )

  // 软删除设备（级联更新 device_peers）
  await admin.from('vpn_device_peers').update({ is_active: false }).eq('device_id', deviceId)
  await admin.from('vpn_devices').update({ is_active: false }).eq('id', deviceId)

  await admin.from('audit_log').insert({
    user_id: user.id,
    action: 'device_removed',
    detail: { device_id: deviceId, peers_removed: peers?.length ?? 0 },
  })

  return NextResponse.json({ success: true })
}
