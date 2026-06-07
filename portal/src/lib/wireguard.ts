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
  '10.200.0.0/21, 2000::/3'

const ipToInt = (ip: string) =>
  ip.split('.').reduce((a, o) => ((a << 8) + (Number(o) & 255)) >>> 0, 0) >>> 0
const intToIp = (n: number) =>
  [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255].join('.')

// Return WG_ALLOWED_IPS with `ip` carved out (the /32 removed by splitting the
// covering CIDR). The VPN server's own public IP must NOT be routed into the
// tunnel — otherwise the client's WireGuard packets to the endpoint get routed
// back through the tunnel, creating an endless encapsulation loop (no traffic
// flows). wg-quick / wireguard-windows only auto-exclude the endpoint for a
// literal default route (0.0.0.0/0); with our split AllowedIPs we carve it out
// explicitly so it works on Windows too (Android sidesteps this via socket
// protect()).
export function allowedIpsExcluding(ip: string | null | undefined): string {
  if (!ip || !/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) return WG_ALLOWED_IPS
  const target = ipToInt(ip)
  const out: string[] = []
  for (const raw of WG_ALLOWED_IPS.split(',').map(s => s.trim())) {
    if (raw.includes(':')) { out.push(raw); continue }        // IPv6 untouched
    const [base, bitsStr] = raw.split('/')
    const bits = Number(bitsStr)
    const mask = bits === 0 ? 0 : (0xFFFFFFFF << (32 - bits)) >>> 0
    if ((target & mask) !== (ipToInt(base) & mask)) { out.push(raw); continue }
    // CIDR contains target → split down to /32, keeping the sibling halves.
    let lo = ipToInt(base) & mask
    for (let p = bits; p < 32; p++) {
      const childBits = p + 1
      const half = (1 << (32 - childBits)) >>> 0
      const left = lo
      const right = (lo + half) >>> 0
      const childMask = (0xFFFFFFFF << (32 - childBits)) >>> 0
      if ((target & childMask) === (left & childMask)) {
        out.push(`${intToIp(right)}/${childBits}`); lo = left
      } else {
        out.push(`${intToIp(left)}/${childBits}`);  lo = right
      }
    }
    // lo === target/32 now → intentionally dropped
  }
  return out.join(', ')
}

// Deterministic peer name for a (device, server) pair. The SAME device+server
// always yields the SAME name, so provisioning is idempotent and concurrent
// requests collide on the unique (device_id, server_id) index instead of
// creating duplicate peers. Satisfies the server's [a-zA-Z0-9_-]{1,64} rule.
export function buildPeerName(deviceId: string, serverId: string): string {
  const dev = deviceId.replace(/-/g, '').slice(0, 8)
  const srv = serverId.replace(/-/g, '').slice(0, 8)
  return `ms-${dev}-${srv}`
}

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
  serverPublicIp?:  string     // resolved endpoint IP, carved out of AllowedIPs
}

export function generateWgConf({
  clientPrivateKey,
  clientIp,
  serverPublicKey,
  presharedKey,
  serverEndpoint,
  serverPort,
  awgParams,
  serverPublicIp,
}: WgPeerConfig): string {
  // Route everything per the split list EXCEPT the server's own public IP,
  // which must reach the endpoint outside the tunnel (avoids the WG-in-WG loop).
  const allowedIps = allowedIpsExcluding(serverPublicIp)
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
    // Conservative MTU so encrypted data packets fit within reduced path MTUs
    // (PPPoE / mobile / constrained networks). Without it, amneziawg-go on
    // Windows defaults to ~1420 → full-size data packets exceed the path MTU
    // and are silently dropped: the tiny handshake succeeds but no data flows,
    // so direct UDP appears to connect then falls back to relay. 1280 is the
    // IPv6 minimum and traverses essentially any path.
    `MTU        = 1280\n` +
    awgSection +
    `\n` +
    `[Peer]\n` +
    `PublicKey    = ${serverPublicKey}\n` +
    `PresharedKey = ${presharedKey}\n` +
    `Endpoint     = ${serverEndpoint}:${serverPort}\n` +
    `AllowedIPs   = ${allowedIps}\n` +
    `PersistentKeepalive = 25\n`
  )
}
