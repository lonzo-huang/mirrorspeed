import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '联系技术支持 — 镜速VPN' },
  description:
    '使用遇到问题？在本页给我们留言，工程师会直接处理，通常一个工作日内回复。',
  alternates: {
    canonical: `${SITE_URL}/cn/support`,
    languages: { en: `${SITE_URL}/support`, 'zh-CN': `${SITE_URL}/cn/support` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/support`,
    title: '联系技术支持 — 镜速VPN',
    description: '使用遇到问题？在本页给我们留言，工程师会直接处理，通常一个工作日内回复。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '联系技术支持 — 镜速VPN' }],
  },
}

export default function CnSupportLayout({ children }: { children: React.ReactNode }) {
  return children
}
