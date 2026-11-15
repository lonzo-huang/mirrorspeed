import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '使用场景 — ChatGPT 加速、流媒体、游戏加速 | 镜速VPN' },
  description:
    '按问题查找实用指南：AI 对话连不稳、4K 视频缓冲、国际服游戏延迟高，以及加速器到底该怎么挑。',
  alternates: {
    canonical: `${SITE_URL}/cn/use-cases`,
    languages: { en: `${SITE_URL}/use-cases`, 'zh-CN': `${SITE_URL}/cn/use-cases` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/use-cases`,
    title: '使用场景 — 镜速VPN',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '镜速VPN使用场景' }],
  },
}

export default function CnUseCasesLayout({ children }: { children: React.ReactNode }) {
  return children
}
