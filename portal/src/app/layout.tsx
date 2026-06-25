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
  keywords:    ['VPN', '科学上网', '加速器', 'MirrorSpeed', '镜速', '翻墙'],
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

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN">
      <body className={`${inter.className} bg-gray-50 text-gray-900 antialiased`}>
        {children}
      </body>
    </html>
  )
}
