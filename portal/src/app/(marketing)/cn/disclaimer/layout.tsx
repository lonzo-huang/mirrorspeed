import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '免责声明与使用规范 — 镜速VPN' },
  description:
    '镜速VPN免责声明：服务用途、遵守当地法律的责任、禁止的行为，以及责任限制。',
  alternates: {
    canonical: `${SITE_URL}/cn/disclaimer`,
    languages: { en: `${SITE_URL}/disclaimer`, 'zh-CN': `${SITE_URL}/cn/disclaimer` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/disclaimer`,
    title: '免责声明与使用规范 — 镜速VPN',
    description: '镜速VPN免责声明：服务用途、遵守当地法律的责任、禁止的行为，以及责任限制。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '免责声明与使用规范 — 镜速VPN' }],
  },
}

export default function CnDisclaimerLayout({ children }: { children: React.ReactNode }) {
  return children
}
