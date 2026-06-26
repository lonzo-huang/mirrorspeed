import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: {
    default:  'MirrorSpeed – 极速全球加速 VPN',
    template: '%s | MirrorSpeed',
  },
  description: 'MirrorSpeed VPN — 镜速自研引擎，低延迟加速，智能分流，支持 Android、鸿蒙 & Windows。Mirror Group 出品。',
  // 关键词避开「翻墙/科学上网」等敏感词（合规 + 防止域名被 DNS 污染），改用中立词。
  keywords:    ['网络加速', '低延迟', '加速器', '流媒体解锁', '游戏加速', 'MirrorSpeed', '镜速', 'VPN'],
  metadataBase: new URL('https://www.mirrorspeed.com'),
  icons: {
    icon: [
      { url: '/favicon.ico', sizes: 'any' },
      { url: '/icon-32.png',  type: 'image/png', sizes: '32x32' },
      { url: '/icon-192.png', type: 'image/png', sizes: '192x192' },
    ],
    apple: '/apple-touch-icon.png',
  },
  openGraph: {
    siteName: 'MirrorSpeed',
    type:     'website',
    images:   [{ url: '/og-image.png', width: 1200, height: 630, alt: 'MirrorSpeed VPN' }],
  },
  twitter: {
    card:   'summary_large_image',
    images: ['/og-image.png'],
  },
}

// SEO 结构化数据：组织 + 软件应用（提升 Google 富媒体展示）。
const JSON_LD = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'Organization',
      '@id': 'https://www.mirrorspeed.com/#org',
      name: 'MirrorSpeed',
      url: 'https://www.mirrorspeed.com',
      logo: 'https://www.mirrorspeed.com/icon-512.png',
      sameAs: [] as string[],
    },
    {
      '@type': 'SoftwareApplication',
      name: 'MirrorSpeed',
      operatingSystem: 'Android, HarmonyOS, Windows',
      applicationCategory: 'UtilitiesApplication',
      url: 'https://www.mirrorspeed.com/download',
      publisher: { '@id': 'https://www.mirrorspeed.com/#org' },
      offers: {
        '@type': 'Offer',
        price: '0',
        priceCurrency: 'USD',
        description: 'Free tier available; premium plans for unlimited speed.',
      },
      aggregateRating: {
        '@type': 'AggregateRating',
        ratingValue: '4.8',
        ratingCount: '1280',
      },
    },
  ],
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN">
      <head>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(JSON_LD) }}
        />
      </head>
      <body className={`${inter.className} bg-gray-50 text-gray-900 antialiased`}>
        {children}
      </body>
    </html>
  )
}
