import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: {
    default:  'MirrorSpeed – 极速全球加速 VPN',
    template: '%s | MirrorSpeed',
  },
  description: 'MirrorSpeed VPN — 低延迟 WireGuard 加速，智能分流，支持 Android & Windows。Mirror Group 出品。',
  keywords:    ['VPN', 'WireGuard', '科学上网', '加速器', 'MirrorSpeed', '镜速', '翻墙'],
  openGraph: {
    siteName: 'MirrorSpeed',
    type:     'website',
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
