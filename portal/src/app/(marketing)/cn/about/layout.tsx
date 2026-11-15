import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '关于镜速加速器 — 谁在运营、技术实现与隐私承诺' },
  description:
    '镜速加速器由 MirrorSpeed 运营：支持安卓、Windows、鸿蒙，永久免费套餐，付费每月最低 ¥8。说明技术实现、不记录哪些数据，以及如何联系我们。',
  alternates: {
    canonical: `${SITE_URL}/cn/about`,
    languages: { en: `${SITE_URL}/about`, 'zh-CN': `${SITE_URL}/cn/about` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/about`,
    title: '关于镜速加速器 — 谁在运营、技术实现与隐私承诺',
    description: '镜速加速器由 MirrorSpeed 运营：支持安卓、Windows、鸿蒙，永久免费套餐，付费每月最低 ¥8。说明技术实现、不记录哪些数据，以及如何联系我们。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '关于镜速加速器 — 谁在运营、技术实现与隐私承诺' }],
  },
}

export default function CnAboutLayout({ children }: { children: React.ReactNode }) {
  return children
}
