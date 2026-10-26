import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'MirrorSpeed — Free VPN · Unlimited Speed · 20+ Countries',
  description: 'Free VPN with unlimited speed up to 1000 Mbps per user and zero-logs nodes in 20+ countries — free forever. Instant, unblocked access to ChatGPT, X, Google, YouTube, TikTok, Instagram. Powered by MirrorSpeed\'s proprietary high-speed engine.',
  alternates: {
    canonical: `${SITE_URL}/en`,
    languages: {
      en:        `${SITE_URL}/en`,
      'zh-CN':   `${SITE_URL}/cn`,
      'x-default': SITE_URL,
    },
  },
  openGraph: {
    title: 'MirrorSpeed — Free VPN · Unlimited Speed',
    description: 'Free forever · Unlimited speed up to 1000 Mbps per user · No logs · 20+ global edges · Hyperspeed engine',
    url: `${SITE_URL}/en`,
    locale: 'en_US',
    images: [{ url: '/og-en.png', width: 1200, height: 630, alt: 'MirrorSpeed — Free VPN · Unlimited Speed' }],
  },
  twitter: {
    title: 'MirrorSpeed — Free VPN · Unlimited Speed',
    description: 'Free forever · Unlimited speed up to 1000 Mbps · No logs · 20+ global edges',
    images: ['/og-en.png'],
  },
}

export default function EnLayout({ children }: { children: React.ReactNode }) {
  return children
}
