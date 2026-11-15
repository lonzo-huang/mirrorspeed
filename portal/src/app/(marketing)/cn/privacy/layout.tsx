import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '隐私政策 — 我们记录什么、不记录什么' },
  description:
    '镜速加速器隐私政策：我们不记录浏览历史、访问目标、DNS 查询与连接 IP；说明保留哪些必要信息、保留多久，以及如何注销账号。',
  alternates: {
    canonical: `${SITE_URL}/cn/privacy`,
    languages: { en: `${SITE_URL}/privacy`, 'zh-CN': `${SITE_URL}/cn/privacy` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/privacy`,
    title: '隐私政策 — 我们记录什么、不记录什么',
    description: '镜速加速器隐私政策：我们不记录浏览历史、访问目标、DNS 查询与连接 IP；说明保留哪些必要信息、保留多久，以及如何注销账号。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '隐私政策 — 我们记录什么、不记录什么' }],
  },
}

export default function CnPrivacyLayout({ children }: { children: React.ReactNode }) {
  return children
}
