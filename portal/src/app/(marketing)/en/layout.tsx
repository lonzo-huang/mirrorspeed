import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'MirrorSpeed — Unstoppable. Globally Fast. · Free Forever Tier',
  description: 'MirrorSpeed — proprietary high-speed VPN engine with UDP encapsulation. Unlimited speed up to 1000 Mbps per user. Zero-logs nodes in 20+ countries. Free forever tier. Instant access to ChatGPT, X, Google, YouTube, TikTok, Instagram.',
  alternates: {
    canonical: `${SITE_URL}/en`,
    languages: {
      en:        `${SITE_URL}/en`,
      'zh-CN':   `${SITE_URL}/cn`,
      'x-default': SITE_URL,
    },
  },
  openGraph: {
    title: 'MirrorSpeed — Unstoppable. Globally Fast.',
    description: 'Hyperspeed Engine · UDP Encapsulation · Free Forever Tier · 20+ Global Edges · No Logs · Up to 1000 Mbps per user',
    url: `${SITE_URL}/en`,
    locale: 'en_US',
    images: [{ url: '/og-en.png', width: 1200, height: 630, alt: 'MirrorSpeed — Unstoppable. Globally Fast.' }],
  },
  twitter: {
    title: 'MirrorSpeed — Unstoppable. Globally Fast.',
    description: 'Hyperspeed Engine · UDP Encapsulation · Free Forever Tier · No Logs',
    images: ['/og-en.png'],
  },
}

export default function EnLayout({ children }: { children: React.ReactNode }) {
  return children
}
