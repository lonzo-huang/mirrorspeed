import { randomUUID, randomBytes } from 'node:crypto'
import { createAdminClient } from '@/lib/supabase/server'
import { encryptKey, decryptKey } from '@/lib/clash'
import { generateWgKeypair } from '@/lib/wireguard'

type Admin = ReturnType<typeof createAdminClient>

export interface DeviceCrypto {
  publicKey:     string
  privateKey:    string   // 明文（用于生成配置）
  privateKeyEnc: string   // 加密（用于写台账）
  vpnIp:         string   // 10.200.x.y/32（带掩码）
  // sing-box 设备级凭证（全局，所有 sing-box 节点共用；见 docs/singbox-migration.md）
  sbUuid:        string   // VLESS UUID(reality/ws 共用)
  hy2Password:   string   // Hysteria2 密码(明文，用于下发)
}

/**
 * 确保设备拥有「一次性密钥对 + 全局唯一内网 IP」（按需建 peer 的基础）。幂等。
 * - 密钥对：缺则用 x25519 生成、加密存 vpn_devices。
 * - IP：缺则调 allocate_device_ip(ip_pool) 分配、写回 vpn_devices.vpn_ip。
 */
export async function ensureDeviceCrypto(admin: Admin, deviceId: string): Promise<DeviceCrypto | null> {
  const { data: dev } = await (admin.from('vpn_devices') as any)
    .select('id, public_key, private_key_enc, vpn_ip, sb_uuid, hy2_password_enc')
    .eq('id', deviceId)
    .maybeSingle()
  if (!dev) return null

  let publicKey: string | null = dev.public_key
  let privEnc:   string | null = dev.private_key_enc
  let vpnIp:     string | null = dev.vpn_ip   // inet（无掩码），如 10.200.5.21
  let sbUuid:    string | null = dev.sb_uuid
  let hy2Enc:    string | null = dev.hy2_password_enc

  const patch: Record<string, any> = {}

  if (!publicKey || !privEnc) {
    const kp = generateWgKeypair()
    publicKey = kp.publicKey
    privEnc   = encryptKey(kp.privateKey)
    patch.public_key      = publicKey
    patch.private_key_enc = privEnc
  }

  // sing-box 设备级凭证：缺则生成(uuid + 24字节hex密码，加密存)。幂等。
  if (!sbUuid) { sbUuid = randomUUID(); patch.sb_uuid = sbUuid }
  if (!hy2Enc) { hy2Enc = encryptKey(randomBytes(24).toString('hex')); patch.hy2_password_enc = hy2Enc }

  // 0.0.0.0 是无效占位（历史脏数据/半途失败留下），按未分配处理重新分配，
  // 避免在服务器上建出 AllowedIPs=0.0.0.0/32 的孤儿 peer。
  if (vpnIp === '0.0.0.0' || vpnIp === '0.0.0.0/32') vpnIp = null

  if (!vpnIp) {
    const { data: ip, error } = await (admin as any).rpc('allocate_device_ip', { p_device_id: deviceId })
    if (error || !ip) {
      console.error('[device-crypto] allocate_device_ip failed', error)
      return null
    }
    vpnIp = ip as string
    patch.vpn_ip = vpnIp
  }

  if (Object.keys(patch).length > 0) {
    await (admin.from('vpn_devices') as any).update(patch).eq('id', deviceId)
  }

  if (!publicKey || !privEnc || !vpnIp || !sbUuid || !hy2Enc) return null

  return {
    publicKey,
    privateKey:    decryptKey(privEnc),
    privateKeyEnc: privEnc,
    vpnIp:         vpnIp.includes('/') ? vpnIp : `${vpnIp}/32`,
    sbUuid,
    hy2Password:   decryptKey(hy2Enc),
  }
}
