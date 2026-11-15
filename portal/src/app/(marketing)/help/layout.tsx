import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Help Center — Connecting, Nodes and Billing',
  description: 'How to connect, choose nodes, free trial time, ads-for-time, smart vs global routing, and subscription management — all answered by real engineers.',
  alternates: {
    canonical: `${SITE_URL}/help`,
    languages: { en: `${SITE_URL}/help`, 'zh-CN': `${SITE_URL}/cn/help` },
  },
  // 不覆盖 openGraph 的话，分享卡片会沿用根布局的首页文案。
  openGraph: {
    url: `${SITE_URL}/help`,
    title: 'Help Center — Connecting, Nodes and Billing',
    description: 'Connecting, choosing a node, free time, split tunnelling and managing your subscription.',
  },
}

export default function HelpLayout({ children }: { children: React.ReactNode }) {
  return children
}
