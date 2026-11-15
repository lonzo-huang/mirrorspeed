import type { Metadata, Viewport } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
// 全站引入落地页主题（.ms-landing / .bg-app / .glass-panel / [data-theme] 变量）。
// 登录/注册/dashboard 等页用到这些类但自身不引入 LandingPage.jsx，必须在此全局加载，
// 否则这些类无样式 → 深色主题失效（表现为浅色/看不清）。
import '@/components/landing/landing.css'
import { availablePlatforms, platformList, sameAs, BRAND, PROFILES, PRICING, DEVICES, MAX_MBPS, NOT_LOGGED } from '@/lib/product'

const inter = Inter({ subsets: ['latin'] })

const SITE_URL = 'https://www.mirrorspeed.com'

/* ────────────────────────────────────────────────────────────────────
 * SEO — best-practice, growth-optimized metadata.
 * ──────────────────────────────────────────────────────────────────── */
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  // 根布局只服务英文首页 `/`。中英混排会让两种语言的搜索都拿不到好位置，
  // 中文版在 /cn 有独立的纯中文 metadata。
  // template 只给「标题里没有品牌名」的子页用；自带品牌的页面用 title.absolute，
  // 否则会出现 "MirrorSpeed — … | MirrorSpeed" 这种品牌重复。
  title: {
    default:  'MirrorSpeed — Free VPN with Unlimited Speed',
    template: '%s | MirrorSpeed',
  },
  // 控制在 160 字符内，否则搜索结果里会被截断。
  description:
    `MirrorSpeed is a VPN for ${platformList('en')}. Free-forever plan, ` +
    `or from $${PRICING.lowestUsd}/month for unlimited time and up to ${MAX_MBPS} Mbps.`,
  applicationName: 'MirrorSpeed',
  authors: [{ name: 'MirrorSpeed', url: SITE_URL }],
  creator: 'MirrorSpeed',
  publisher: 'MirrorSpeed',
  category: 'technology',
  // 不再输出 meta keywords：Google 早已忽略它，只是把关键词策略白送给竞争对手。
  alternates: {
    canonical: '/',
    languages: {
      'en':    SITE_URL,          // 英文内容的唯一规范网址就是 `/`（/en 指向它）
      'zh-CN': `${SITE_URL}/cn`,
      'x-default': SITE_URL,
    },
  },
  icons: {
    icon: [
      { url: '/favicon.ico', sizes: 'any' },
      { url: '/icon-32.png',  type: 'image/png', sizes: '32x32' },
      { url: '/icon-192.png', type: 'image/png', sizes: '192x192' },
      { url: '/icon-512.png', type: 'image/png', sizes: '512x512' },
    ],
    apple: '/apple-touch-icon.png',
  },
  manifest: '/manifest.webmanifest',
  openGraph: {
    siteName: 'MirrorSpeed',
    type:     'website',
    url:      SITE_URL,
    locale:   'en_US',
    alternateLocale: ['zh_CN', 'fr_FR', 'es_ES', 'de_DE', 'it_IT', 'ja_JP', 'ko_KR', 'ru_RU', 'tr_TR', 'ar'],
    title:    'MirrorSpeed — Free VPN · Unlimited Speed · Free Forever',
    description:
      `Free-forever plan · Up to ${MAX_MBPS} Mbps per user · No activity logs · ` +
      `Paid plans from $${PRICING.lowestUsd}/month · ${platformList('en')}.`,
    images: [
      { url: '/og-en.png', width: 1200, height: 630, alt: 'MirrorSpeed — Unstoppable. Globally Fast.' },
      { url: '/og-cn.png', width: 1200, height: 630, alt: 'MirrorSpeed — 无惧干扰，极速连接全球' },
    ],
  },
  twitter: {
    card:    'summary_large_image',
    site:    '@mirrorspeed',
    creator: '@mirrorspeed',
    title:   'MirrorSpeed — Free VPN · Unlimited Speed',
    description:
      `Free-forever plan · Up to ${MAX_MBPS} Mbps · No activity logs · From $${PRICING.lowestUsd}/month.`,
    images:  ['/og-en.png'],
  },
  robots: {
    index:  true,
    follow: true,
    googleBot: {
      index:  true,
      follow: true,
      'max-image-preview': 'large',
      'max-snippet':       -1,
      'max-video-preview': -1,
    },
  },
  formatDetection: { email: false, telephone: false, address: false },
  // Slot for Search Console / Bing / Yandex verification — fill in once issued.
  verification: {
    // google: 'xxxxxxxxxx',
    // other: { 'msvalidate.01': 'xxx', 'yandex-verification': 'xxx' },
  },
  referrer: 'origin-when-cross-origin',
}

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f4f6fb' },
    { media: '(prefers-color-scheme: dark)',  color: '#06090E' },
  ],
  width: 'device-width',
  initialScale: 1,
  maximumScale: 5,
  colorScheme: 'dark light',
}

/* JSON-LD: Organization + SoftwareApplication + WebSite + FAQPage.
 * Triggers Google rich-result eligibility (knowledge panel + sitelinks search box). */
const JSON_LD = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'Organization',
      '@id': `${SITE_URL}/#org`,
      name: BRAND.name,
      alternateName: BRAND.nameZh,
      url:  SITE_URL,
      logo: `${SITE_URL}/icon-512.png`,
      description:
        `MirrorSpeed builds a consumer VPN and network accelerator for ${platformList('en')}.`,
      email: BRAND.email,
      // sameAs：能在第三方平台上唯一指向本主体的网址（知识面板、AI 推荐都看这个）。
      // 只列已验证返回 200 的页面——指向 404 的 sameAs 会损害可信度。
      // App Store 上架后在 lib/product.ts 的 PROFILES.appStore 填入即可。
      sameAs: sameAs(),
      contactPoint: [{
        '@type': 'ContactPoint',
        contactType: 'customer support',
        url: `${SITE_URL}/support`,
        availableLanguage: ['English', 'Chinese'],
      }],
    },
    {
      '@type': 'WebSite',
      '@id': `${SITE_URL}/#website`,
      url: SITE_URL,
      name: 'MirrorSpeed',
      publisher: { '@id': `${SITE_URL}/#org` },
      inLanguage: ['en', 'zh-CN'],
      // 原来的 SearchAction 指向 /blog?q=，而 /blog 已 301 到 blog.mirrorspeed.com，
      // 站内也没有搜索功能 —— 声明一个不存在的搜索接口只会损害可信度，故移除。
    },
    {
      '@type': 'SoftwareApplication',
      '@id': `${SITE_URL}/#app`,
      name: 'MirrorSpeed',
      alternateName: '镜速VPN',
      // 一句话定义：AI 回答「MirrorSpeed 是什么」时直接可引用。
      description:
        `MirrorSpeed is a VPN and network accelerator for ${platformList('en')}. ` +
        `It has a free-forever plan with a daily time allowance, and paid plans from $${PRICING.lowestUsd} per month ` +
        `with unlimited time, no ads, up to ${MAX_MBPS} Mbps per user and up to ${DEVICES.paid} devices.`,
      // 只列已上架可下载的平台。iOS/macOS 过审后改 lib/product.ts 的 status 即可。
      operatingSystem: availablePlatforms('en').join(', '),
      applicationCategory: 'SecurityApplication',
      applicationSubCategory: 'VPN',
      url: `${SITE_URL}/download`,
      downloadUrl: `${SITE_URL}/download`,
      installUrl: PROFILES.googlePlayApp,
      inLanguage: ['en', 'zh-CN'],
      publisher: { '@id': `${SITE_URL}/#org` },
      // 真实价格区间：免费档 $0 起，付费最低（两年付）到最高（月付）。
      offers: {
        '@type': 'AggregateOffer',
        priceCurrency: 'USD',
        lowPrice: '0',
        highPrice: String(PRICING.highestUsd.toFixed(2)),
        offerCount: PRICING.planCount,
        description:
          `Free-forever plan with a daily time allowance; paid plans from $${PRICING.lowestUsd}/month billed every 2 years.`,
      },
      // 已移除 aggregateRating：页面上没有可核实的评价来源，
      // 自报评分属于 Google 结构化数据垃圾标记，且 AI 无法验证。
      // 接入 Google Play / App Store 真实评分后再加回，并附评分页链接。
      featureList: [
        'Free-forever plan',
        `Up to ${MAX_MBPS} Mbps per user`,
        `No ${NOT_LOGGED.en.slice(0, 3).join(', ')} or connection IP kept`,
        `Up to ${DEVICES.paid} devices on paid plans`,
        'Split tunnelling (per-app and China-direct routing)',
        'One-tap connect with automatic node selection',
      ],
    },
  ],
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        {/* Landing fonts: Manrope (body) / Unbounded (headings) / JetBrains Mono (data) */}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Unbounded:wght@600;700;800;900&family=JetBrains+Mono:wght@400;500&display=swap"
          rel="stylesheet"
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(JSON_LD) }}
        />
        {/* 防闪烁：水合前就设好 html[data-theme]。
            登录/注册/dashboard/admin 为纯深色页，强制 dark，无视全局偏好；
            其余页按已保存偏好(ms_theme)，保证主页与内容页首屏主题一致。 */}
        <script
          dangerouslySetInnerHTML={{
            __html: `(function(){try{document.documentElement.setAttribute('data-theme','dark');localStorage.setItem('ms_theme','dark');}catch(e){document.documentElement.setAttribute('data-theme','dark');}})();`,
          }}
        />
        {/* iOS(WebKit)性能降级：iPhone/iPad 上 backdrop-filter 毛玻璃、SVG 噪点、
            大量持续动画开销极大，滚动卡顿。水合前给 <html> 打 .ios 类，
            CSS 据此关闭这些特效；桌面/安卓(Blink)完全不受影响。
            注意 iPadOS 13+ 会伪装成桌面 Safari，需用 maxTouchPoints 补判。 */}
        <script
          dangerouslySetInnerHTML={{
            __html: `(function(){try{var u=navigator.userAgent||'';if(/iP(hone|ad|od)/.test(u)||(navigator.maxTouchPoints>1&&/Mac/.test(navigator.platform))){document.documentElement.classList.add('ios');}}catch(e){}})();`,
          }}
        />
      </head>
      <body className={`${inter.className} antialiased`}>
        {children}
      </body>
    </html>
  )
}
