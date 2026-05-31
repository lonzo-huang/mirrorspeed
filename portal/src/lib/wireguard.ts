// WireGuard / AmneziaWG client configuration generation
// AllowedIPs = full public internet, LAN (RFC1918) bypassed, VPN subnet included
export const WG_ALLOWED_IPS =
  '0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, 12.0.0.0/6, 16.0.0.0/4, ' +
  '32.0.0.0/3, 64.0.0.0/2, 128.0.0.0/3, 160.0.0.0/5, 168.0.0.0/6, ' +
  '172.0.0.0/12, 172.32.0.0/11, 172.64.0.0/10, 172.128.0.0/9, ' +
  '173.0.0.0/8, 174.0.0.0/7, 176.0.0.0/4, 192.0.0.0/9, ' +
  '192.128.0.0/11, 192.160.0.0/13, 192.169.0.0/16, 192.170.0.0/15, ' +
  '192.172.0.0/14, 192.176.0.0/12, 192.192.0.0/10, 193.0.0.0/8, ' +
  '194.0.0.0/7, 196.0.0.0/6, 200.0.0.0/5, 208.0.0.0/4, ' +
  '10.200.0.0/24, 2000::/3'

// AmneziaWG obfuscation parameters (must match server awg0.conf exactly).
// Jc = 0 means obfuscation disabled (standard WireGuard behaviour).
export interface AwgParams {
  jc:   number   // Junk packet count (0 = disabled)
  jmin: number   // Min junk packet size (bytes)
  jmax: number   // Max junk packet size (bytes)
  s1:   number   // Init packet extra junk size
  s2:   number   // Response packet extra junk size
  h1:   number   // Magic header 1
  h2:   number   // Magic header 2
  h3:   number   // Magic header 3
  h4:   number   // Magic header 4
}

export interface WgPeerConfig {
  clientPrivateKey: string
  clientIp:         string   // e.g. '10.200.0.5/32'
  serverPublicKey:  string
  presharedKey:     string
  serverEndpoint:   string
  serverPort:       number
  awgParams?:       AwgParams  // Omit or set jc=0 for standard WireGuard
}

export function generateWgConf({
  clientPrivateKey,
  clientIp,
  serverPublicKey,
  presharedKey,
  serverEndpoint,
  serverPort,
  awgParams,
}: WgPeerConfig): string {
  // Include AWG obfuscation section only when Jc > 0
  const awgSection = (awgParams && awgParams.jc > 0)
    ? [
        `Jc         = ${awgParams.jc}`,
        `Jmin       = ${awgParams.jmin}`,
        `Jmax       = ${awgParams.jmax}`,
        `S1         = ${awgParams.s1}`,
        `S2         = ${awgParams.s2}`,
        `H1         = ${awgParams.h1}`,
        `H2         = ${awgParams.h2}`,
        `H3         = ${awgParams.h3}`,
        `H4         = ${awgParams.h4}`,
      ].join('\n') + '\n'
    : ''

  return (
    `[Interface]\n` +
    `PrivateKey = ${clientPrivateKey}\n` +
    `Address    = ${clientIp}\n` +
    `DNS        = 8.8.8.8, 1.1.1.1\n` +
    awgSection +
    `\n` +
    `[Peer]\n` +
    `PublicKey    = ${serverPublicKey}\n` +
    `PresharedKey = ${presharedKey}\n` +
    `Endpoint     = ${serverEndpoint}:${serverPort}\n` +
    `AllowedIPs   = ${WG_ALLOWED_IPS}\n` +
    `PersistentKeepalive = 25\n`
  )
}
