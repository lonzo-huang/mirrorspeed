// 产品事实的唯一来源。
//
// 背景：之前价格、设备数、平台支持在 JSON-LD、落地页文案、llms.txt、关于页里
// 各写各的，互相矛盾（$1.00 vs $0.88、8 台 vs 3 台、支持 iOS vs Apple 开发中）。
// 搜索引擎和 AI 都会比对多处信息，矛盾会让它们不敢引用。
//
// ⚠️ 改动规则：这些数字改了，全站跟着变。改之前先确认它和代码/后台一致：
//   · 设备上限 → src/app/api/mobile/device/route.ts 的 MAX_DEVICES
//   · 价格     → Stripe 价格 + src/components/landing/LandingPage.jsx 的 plans
//   · 平台可用性 → 必须真的能下载到，才能标 available

export const BRAND = {
  name: 'MirrorSpeed',
  /**
   * 中文品牌名。用于搜索结果标题/描述与结构化数据。
   * 注意：AGENTS.md 规定**客户端中文壳**出于合规不出现「VPN」字样，用「加速器」。
   * 那条规则针对 App 内文案，官网中文内容本就在用 VPN 一词，两者各自独立。
   */
  nameZh: '镜速VPN',
  email: 'mirrorspeed@mirrorquant.com',
  siteUrl: 'https://www.mirrorspeed.com',
} as const

export type PlatformStatus = 'available' | 'coming-soon'

export interface Platform {
  key: string
  en: string
  zh: string
  status: PlatformStatus
  /** coming-soon 时说明在等什么，避免含糊其辞 */
  noteEn?: string
  noteZh?: string
}

// 只有「用户现在就能装上」才算 available。
// iOS / macOS 代码已完成并在 App Store 审核中，但审核通过前写成「已支持」
// 会让用户点进下载页扑空 —— 上架后把 status 改成 'available' 即可全站同步。
export const PLATFORMS: Platform[] = [
  { key: 'android',   en: 'Android',   zh: '安卓',    status: 'available' },
  { key: 'windows',   en: 'Windows',   zh: 'Windows', status: 'available' },
  { key: 'harmonyos', en: 'HarmonyOS', zh: '鸿蒙',    status: 'available' },
  {
    key: 'ios', en: 'iOS', zh: 'iOS', status: 'coming-soon',
    noteEn: 'in App Store review', noteZh: 'App Store 审核中',
  },
  {
    key: 'macos', en: 'macOS', zh: 'macOS', status: 'coming-soon',
    noteEn: 'in App Store review', noteZh: 'App Store 审核中',
  },
]

export const availablePlatforms = (lang: 'en' | 'zh' = 'en') =>
  PLATFORMS.filter(p => p.status === 'available').map(p => (lang === 'zh' ? p.zh : p.en))

export const comingSoonPlatforms = (lang: 'en' | 'zh' = 'en') =>
  PLATFORMS.filter(p => p.status === 'coming-soon').map(p => (lang === 'zh' ? p.zh : p.en))

/** "Android, Windows and HarmonyOS" / "安卓、Windows 和鸿蒙" */
export const platformList = (lang: 'en' | 'zh' = 'en') => {
  const list = availablePlatforms(lang)
  if (lang === 'zh') return list.join('、')
  return list.length > 1 ? `${list.slice(0, -1).join(', ')} and ${list[list.length - 1]}` : list[0]
}

// ── 价格（每月显示价，与 Stripe 实际扣款一致）────────────────────────────────
export const PRICING = {
  /** 最低价 = 两年付摊到每月 */
  lowestUsd: 0.88,
  lowestCny: 8,
  /** 最高价 = 月付 */
  highestUsd: 3.0,
  highestCny: 24,
  planCount: 6,          // 免费 + 5 个付费档
  refundDays: 7,
} as const

// ── 设备数（与 api/mobile/device 的 MAX_DEVICES 一致）──────────────────────
export const DEVICES = { free: 4, paid: 8 } as const

/** 每用户带宽上限（Mbps） */
export const MAX_MBPS = 1000

// ── 隐私：逐条写明不记录什么，比一句「零日志」可验证得多 ────────────────────
export const NOT_LOGGED = {
  en: ['browsing history', 'traffic destinations', 'DNS queries', 'the IP address you connect from'],
  zh: ['浏览历史', '流量访问的目标地址', 'DNS 查询', '你连接时使用的 IP 地址'],
} as const

/**
 * 是否声称做过第三方审计。没有报告就必须是 false —— 无证据的审计声明
 * 在 VPN 评测和 AI 评估里是减分项，而且会和 llms.txt 自相矛盾。
 */
export const HAS_THIRD_PARTY_AUDIT = false

// ── 节点 ────────────────────────────────────────────────────────────────────
// 自营优质节点当前覆盖的国家/地区（与 /api/servers 返回一致）。
// 这里不写总数：数量会变，写死就会和服务器页的实时数字对不上。
export const NODE_COUNTRIES = {
  en: ['the United States', 'Germany', 'Spain', 'Japan', 'Singapore', 'Hong Kong'],
  zh: ['美国', '德国', '西班牙', '日本', '新加坡', '香港'],
} as const

// ── 外部主体资料（sameAs）：只放已验证返回 200 的网址 ──────────────────────
export const PROFILES = {
  // 应用页按**包名**定位，开发者改名也不会失效。
  googlePlayApp: 'https://play.google.com/store/apps/details?id=com.mirrorspeed.vpn',
  // 不放 Google Play 开发者页：它的网址按**开发者名称**拼接
  // （developer?id=Mirrorr+Studio），改名后旧链接会失效，sameAs 指向 404
  // 比留空更伤可信度。要放的话，等改名生效后用新网址，并先确认返回 200。
  blog: 'https://blog.mirrorspeed.com',
  /** App Store 上架后填入并加进 sameAs */
  appStore: null as string | null,
}

export const sameAs = () =>
  [PROFILES.googlePlayApp, PROFILES.blog, PROFILES.appStore]
    .filter((u): u is string => !!u)
