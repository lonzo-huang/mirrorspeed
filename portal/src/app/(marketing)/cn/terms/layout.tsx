import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '服务条款 — 镜速VPN' },
  description:
    '镜速VPN服务条款：订阅与计费、可接受使用范围、退款政策、账号终止与责任限制。',
  alternates: {
    canonical: `${SITE_URL}/cn/terms`,
    languages: { en: `${SITE_URL}/terms`, 'zh-CN': `${SITE_URL}/cn/terms` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/terms`,
    title: '服务条款 — 镜速VPN',
    description: '镜速VPN服务条款：订阅与计费、可接受使用范围、退款政策、账号终止与责任限制。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '服务条款 — 镜速VPN' }],
  },
}

export default function CnTermsLayout({ children }: { children: React.ReactNode }) {
  return children
}
