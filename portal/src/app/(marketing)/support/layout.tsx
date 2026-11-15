import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Support — Contact Our Engineers',
  description: 'Talk to real engineers. We typically reply within 1 business day. Send us a message from this page and we\'ll get back to you.',
  alternates: {
    canonical: `${SITE_URL}/support`,
    languages: { en: `${SITE_URL}/support`, 'zh-CN': `${SITE_URL}/cn/support` },
  },
  // 不覆盖 openGraph 的话，分享卡片会沿用根布局的首页文案。
  openGraph: {
    url: `${SITE_URL}/support`,
    title: 'Support — Contact Our Engineers',
    description: 'Message us from this page. We typically reply within one business day.',
  },
}

export default function SupportLayout({ children }: { children: React.ReactNode }) {
  return children
}
