import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '镜速加速器下载 — 安卓、鸿蒙、Windows 客户端' },
  description:
    '下载镜速加速器客户端：支持安卓、鸿蒙与 Windows，免配置、一键连接，永久免费套餐无需信用卡。' +
    '安装遇到问题可查看对应机型的图文教程。',
  alternates: {
    canonical: `${SITE_URL}/cn/download`,
    languages: { en: `${SITE_URL}/download`, 'zh-CN': `${SITE_URL}/cn/download` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/download`,
    title: '镜速加速器下载 — 安卓 · 鸿蒙 · Windows',
    description: '免配置，一键连接，永久免费套餐无需信用卡。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '镜速加速器下载' }],
  },
}

export default function CnDownloadLayout({ children }: { children: React.ReactNode }) {
  return children
}
