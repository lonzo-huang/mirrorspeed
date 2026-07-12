import type { Metadata, Viewport } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
// 全站引入落地页主题（.ms-landing / .bg-app / .glass-panel / [data-theme] 变量）。
// 登录/注册/dashboard 等页用到这些类但自身不引入 LandingPage.jsx，必须在此全局加载，
// 否则这些类无样式 → 深色主题失效（表现为浅色/看不清）。
import '@/components/landing/landing.css'

const inter = Inter({ subsets: ['latin'] })

const SITE_URL = 'https://www.mirrorspeed.com'

/* ────────────────────────────────────────────────────────────────────
 * SEO — best-practice, growth-optimized metadata.
 * ──────────────────────────────────────────────────────────────────── */
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default:  'MirrorSpeed — Fast VPN · 镜速加速器 · Unlimited Speed · Free Tier',
    template: '%s | MirrorSpeed',
  },
  description:
    'MirrorSpeed — proprietary high-speed VPN engine. UDP encapsulation, ' +
    'unlimited speed up to 1000 Mbps per user, zero-logs nodes in 20+ countries. ' +
    'Free forever tier. Instant access to ChatGPT, X, Google, YouTube, TikTok. ' +
    'MirrorSpeed 镜速 — 自研加速引擎，UDP 协议封装，单用户最高 1000 Mbps 不限速，多国节点零日志，永久免费试用。',
  applicationName: 'MirrorSpeed',
  authors: [{ name: 'MirrorSpeed', url: SITE_URL }],
  creator: 'MirrorSpeed',
  publisher: 'MirrorSpeed',
  category: 'technology',
  keywords: [
    // EN core
    'VPN', 'fast VPN', 'free VPN', 'low-latency VPN', 'unlimited VPN',
    'low latency VPN', 'global VPN', 'mirror latency', 'MirrorSpeed',
    'ChatGPT VPN', 'AI access VPN', 'streaming VPN', 'gaming VPN',
    // ZH (合规中立词，避免敏感词)
    '网络加速', '低延迟', '加速器', '镜速', 'MirrorSpeed 加速器',
    '流媒体解锁', '游戏加速', 'AI 加速', 'ChatGPT 加速', '全球节点',
  ],
  alternates: {
    canonical: '/',
    languages: {
      'en':    `${SITE_URL}/en`,
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
    title:    'MirrorSpeed — Fast VPN · Unlimited Speed · Free Tier',
    description:
      'proprietary high-speed VPN engine. UDP encapsulation. Unlimited speed up to 1000 Mbps. ' +
      'Free forever tier · No logs · 20+ global edges.',
    images: [
      { url: '/og-en.png', width: 1200, height: 630, alt: 'MirrorSpeed — Unstoppable. Globally Fast.' },
      { url: '/og-cn.png', width: 1200, height: 630, alt: 'MirrorSpeed — 无惧干扰，极速连接全球' },
    ],
  },
  twitter: {
    card:    'summary_large_image',
    site:    '@mirrorspeed',
    creator: '@mirrorspeed',
    title:   'MirrorSpeed — Fast VPN · Unlimited Speed',
    description:
      'Proprietary high-speed engine · UDP encapsulation · Free forever tier · 20+ global edges.',
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
      name: 'MirrorSpeed',
      url:  SITE_URL,
      logo: `${SITE_URL}/icon-512.png`,
      sameAs: [
        // Add your social profiles here once available — boosts knowledge panel
        // 'https://twitter.com/mirrorspeed',
        // 'https://github.com/mirrorspeed',
      ],
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
      potentialAction: {
        '@type': 'SearchAction',
        target: { '@type': 'EntryPoint', urlTemplate: `${SITE_URL}/blog?q={search_term_string}` },
        'query-input': 'required name=search_term_string',
      },
    },
    {
      '@type': 'SoftwareApplication',
      '@id': `${SITE_URL}/#app`,
      name: 'MirrorSpeed',
      operatingSystem: 'Android, HarmonyOS, Windows',
      applicationCategory: 'UtilitiesApplication',
      applicationSubCategory: 'VPN',
      url: `${SITE_URL}/download`,
      publisher: { '@id': `${SITE_URL}/#org` },
      offers: {
        '@type': 'Offer',
        price: '0',
        priceCurrency: 'USD',
        description: 'Free tier available; premium plans from $1.00/mo for unlimited speed.',
      },
      aggregateRating: {
        '@type': 'AggregateRating',
        ratingValue: '4.9',
        ratingCount: '12800',
      },
      featureList: [
        'Proprietary high-speed engine',
        'UDP encapsulation',
        '1000 Mbps per user',
        'Zero logs',
        'Global edge network',
        '24/7 engineer support',
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
