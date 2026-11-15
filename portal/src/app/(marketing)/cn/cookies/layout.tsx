import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: 'Cookie 政策 — 镜速VPN' },
  description:
    '镜速VPN仅使用登录所必需的 Cookie，以及用于记住语言与主题偏好的浏览器本地存储，不使用广告或追踪类 Cookie。',
  alternates: {
    canonical: `${SITE_URL}/cn/cookies`,
    languages: { en: `${SITE_URL}/cookies`, 'zh-CN': `${SITE_URL}/cn/cookies` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/cookies`,
    title: 'Cookie 政策 — 镜速VPN',
    description: '镜速VPN仅使用登录所必需的 Cookie，以及用于记住语言与主题偏好的浏览器本地存储，不使用广告或追踪类 Cookie。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: 'Cookie 政策 — 镜速VPN' }],
  },
}

export default function CnCookiesLayout({ children }: { children: React.ReactNode }) {
  return children
}
