// VPN 服务器管理 API 客户端
// 对接部署在 VPN 服务器上的 FastAPI（vpn-server/main.py）

const BASE_URL = process.env.VPN_API_BASE_URL!
const SECRET   = process.env.VPN_API_SECRET!

interface PeerInfo {
  peer_name: string
  public_key: string
  private_key: string
  preshared_key: string
  vpn_ip: string
}

interface VpnApiError {
  detail: string
}

async function vpnFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'X-API-Secret': SECRET,
      ...options.headers,
    },
  })

  if (!res.ok) {
    const err: VpnApiError = await res.json().catch(() => ({ detail: res.statusText }))
    throw new Error(`VPN API error ${res.status}: ${err.detail}`)
  }

  return res.json()
}

// 在 VPN 服务器上创建新 Peer，返回完整密钥信息
export async function createVpnPeer(peerName: string): Promise<PeerInfo> {
  return vpnFetch<PeerInfo>('/peers', {
    method: 'POST',
    body: JSON.stringify({ peer_name: peerName }),
  })
}

// 删除 VPN 服务器上的 Peer（用户删除设备或订阅过期时调用）
export async function deleteVpnPeer(peerName: string): Promise<void> {
  await vpnFetch<void>(`/peers/${encodeURIComponent(peerName)}`, { method: 'DELETE' })
}

// 获取所有 Peer 状态（包括最后握手时间，用于监控）
export async function listVpnPeers(): Promise<Array<{
  peer_name: string
  public_key: string
  vpn_ip: string
  last_handshake: string | null
  tx_bytes: number
  rx_bytes: number
}>> {
  return vpnFetch('/peers')
}

// 激活/停用 Peer（不删除，只是 wg set ... disabled）
export async function setVpnPeerActive(peerName: string, active: boolean): Promise<void> {
  await vpnFetch(`/peers/${encodeURIComponent(peerName)}/status`, {
    method: 'PATCH',
    body: JSON.stringify({ active }),
  })
}
