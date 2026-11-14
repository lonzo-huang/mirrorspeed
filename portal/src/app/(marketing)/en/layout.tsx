import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  // title.absolute：标题里已有品牌名，不能再套 '%s | MirrorSpeed' 模板，否则品牌重复两次。
  title: { absolute: 'MirrorSpeed — Free VPN with Unlimited Speed' },
  description:
    'MirrorSpeed is a VPN for Android, Windows and HarmonyOS with a free-forever plan and ' +
    'paid plans from $0.88/month. Up to 1000 Mbps per user, zero-logs nodes, one-tap connect.',
  // `/` 与 `/en` 内容完全相同 → 重复内容。统一把英文版的规范网址定为 `/`，
  // 权重集中到一个网址上；`/en` 仍可正常访问，只是不单独参与排名。
  alternates: {
    canonical: SITE_URL,
    languages: {
      en:          SITE_URL,
      'zh-CN':     `${SITE_URL}/cn`,
      'x-default': SITE_URL,
    },
  },
  openGraph: {
    title: 'MirrorSpeed — Free VPN with Unlimited Speed',
    description: 'Free-forever plan · Up to 1000 Mbps per user · No logs · Paid plans from $0.88/month',
    url: SITE_URL,
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
