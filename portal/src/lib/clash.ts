import yaml from 'js-yaml'

export interface ServerPeerConfig {
  serverName:       string   // '🇭🇰 香港 01'
  serverEndpoint:   string   // 'hk01.vpn.example.com'
  serverPort:       number
  serverPublicKey:  string
  clientPrivateKey: string
  clientIp:         string   // '10.200.0.5/32'
  presharedKey:     string
}

// 生成完整多服务器 Clash Meta 配置
export function generateClashConfig(
  deviceLabel: string,
  peers: ServerPeerConfig[]
): string {
  if (peers.length === 0) return '# No active servers'

  // 每个服务器对应一个 WireGuard proxy
  const proxies = peers.map(p => ({
    name:            p.serverName,
    type:            'wireguard',
    server:          p.serverEndpoint,
    port:            p.serverPort,
    ip:              p.clientIp,
    'private-key':   p.clientPrivateKey,
    'public-key':    p.serverPublicKey,
    'preshared-key': p.presharedKey,
    mtu:             1420,
    udp:             true,
    'dns-hijack':    ['8.8.8.8:53', '1.1.1.1:53'],
  }))

  const proxyNames = peers.map(p => p.serverName)

  const config = {
    'mixed-port':  7890,
    'allow-lan':   false,
    mode:          'rule',
    'log-level':   'warning',
    'external-controller': '127.0.0.1:9090',

    dns: {
      enable:          true,
      ipv6:            false,
      'enhanced-mode': 'fake-ip',
      'fake-ip-filter': ['*.lan', 'localhost.ptlogin2.qq.com'],
      nameserver: [
        'https://1.1.1.1/dns-query',
        'https://8.8.8.8/dns-query',
      ],
      fallback:         ['https://1.0.0.1/dns-query'],
      'fallback-filter': { geoip: true, 'geoip-code': 'CN' },
    },

    proxies,

    'proxy-groups': [
      {
        // 自动选择：每 300 秒测速，选延迟最低的服务器
        name:      '🚀 自动选择',
        type:      'url-test',
        proxies:   proxyNames,
        url:       'http://www.gstatic.com/generate_204',
        interval:  300,
        tolerance: 50,
        lazy:      false,
      },
      {
        // 手动选择：用户可在 Clash 界面中切换服务器
        name:    '🔒 企业VPN',
        type:    'select',
        proxies: ['🚀 自动选择', ...proxyNames, 'DIRECT'],
      },
      {
        // 国际流量组（可单独配置规则）
        name:    '🌍 国际',
        type:    'select',
        proxies: ['🔒 企业VPN', '🚀 自动选择', ...proxyNames, 'DIRECT'],
      },
    ],

    rules: [
      // 本地直连
      'DOMAIN,localhost,DIRECT',
      'IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
      'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
      'IP-CIDR,172.16.0.0/12,DIRECT,no-resolve',
      'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
      // 中国大陆直连
      'GEOIP,CN,DIRECT',
      // 其余走 VPN
      'MATCH,🔒 企业VPN',
    ],
  }

  return [
    '# Enterprise VPN - Clash Meta 订阅配置',
    `# 设备: ${deviceLabel}`,
    `# 服务器数量: ${peers.length}`,
    `# 生成时间: ${new Date().toISOString()}`,
    '# 此文件由系统自动生成，请勿手动编辑，重启 Clash 可拉取最新配置',
    '',
    yaml.dump(config, { lineWidth: -1, noRefs: true }),
  ].join('\n')
}

// ── 密钥加解密（XOR + base64，生产建议换 libsodium）──────────────────────
export function encryptKey(plainKey: string): string {
  const secret = process.env.APP_ENCRYPTION_SECRET!
  const buf    = Buffer.from(plainKey, 'utf8')
  const key    = Buffer.from(
    secret.repeat(Math.ceil(buf.length / secret.length))
  ).slice(0, buf.length)
  return Buffer.from(buf.map((b, i) => b ^ key[i])).toString('base64')
}

export function decryptKey(encryptedKey: string): string {
  const secret = process.env.APP_ENCRYPTION_SECRET!
  const buf    = Buffer.from(encryptedKey, 'base64')
  const key    = Buffer.from(
    secret.repeat(Math.ceil(buf.length / secret.length))
  ).slice(0, buf.length)
  return Buffer.from(buf.map((b, i) => b ^ key[i])).toString('utf8')
}
