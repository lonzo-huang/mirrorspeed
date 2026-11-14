import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  // 标题不再自带品牌名：根布局的 '%s | MirrorSpeed' 模板会统一追加一次，
  // 否则输出 "Download MirrorSpeed … | MirrorSpeed"，品牌重复两次。
  title: 'Download for Android, HarmonyOS and Windows',
  description: 'Download MirrorSpeed VPN for Android, HarmonyOS, and Windows. Zero configuration, one-tap connect, free forever tier.',
  alternates: {
    canonical: `${SITE_URL}/download`,
    languages: { en: `${SITE_URL}/download`, 'zh-CN': `${SITE_URL}/cn/download` },
  },
  openGraph: {
    title: 'Download MirrorSpeed — Android · HarmonyOS · Windows',
    description: 'One-tap connect · Free forever tier · 1000 Mbps · 20+ global edges',
    url: `${SITE_URL}/download`,
  },
}

export default function DownloadLayout({ children }: { children: React.ReactNode }) {
  return children
}
