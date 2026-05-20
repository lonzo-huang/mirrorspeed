// WireGuard 客户端配置生成
// AllowedIPs = 全量公网，LAN（RFC1918）直连，单独放行 VPN 子网
export const WG_ALLOWED_IPS =
  '0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, 12.0.0.0/6, 16.0.0.0/4, ' +
  '32.0.0.0/3, 64.0.0.0/2, 128.0.0.0/3, 160.0.0.0/5, 168.0.0.0/6, ' +
  '172.0.0.0/12, 172.32.0.0/11, 172.64.0.0/10, 172.128.0.0/9, ' +
  '173.0.0.0/8, 174.0.0.0/7, 176.0.0.0/4, 192.0.0.0/9, ' +
  '192.128.0.0/11, 192.160.0.0/13, 192.169.0.0/16, 192.170.0.0/15, ' +
  '192.172.0.0/14, 192.176.0.0/12, 192.192.0.0/10, 193.0.0.0/8, ' +
  '194.0.0.0/7, 196.0.0.0/6, 200.0.0.0/5, 208.0.0.0/4, ' +
  '10.200.0.0/24, 2000::/3'

export interface WgPeerConfig {
  clientPrivateKey: string
  clientIp:         string   // e.g. '10.200.0.5/32'
  serverPublicKey:  string
  presharedKey:     string
  serverEndpoint:   string
  serverPort:       number
}

export function generateWgConf({ clientPrivateKey, clientIp, serverPublicKey, presharedKey, serverEndpoint, serverPort }: WgPeerConfig): string {
  return (
    `[Interface]\n` +
    `PrivateKey = ${clientPrivateKey}\n` +
    `Address    = ${clientIp}\n` +
    `DNS        = 8.8.8.8, 1.1.1.1\n` +
    `\n` +
    `[Peer]\n` +
    `PublicKey    = ${serverPublicKey}\n` +
    `PresharedKey = ${presharedKey}\n` +
    `Endpoint     = ${serverEndpoint}:${serverPort}\n` +
    `AllowedIPs   = ${WG_ALLOWED_IPS}\n` +
    `PersistentKeepalive = 25\n`
  )
}
