import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Help Center — Connecting, Nodes and Billing',
  description: 'How to connect, choose nodes, free trial time, ads-for-time, smart vs global routing, and subscription management — all answered by real engineers.',
  alternates: {
    canonical: `${SITE_URL}/help`,
    languages: { en: `${SITE_URL}/help`, 'zh-CN': `${SITE_URL}/cn/help` },
  },
}

export default function HelpLayout({ children }: { children: React.ReactNode }) {
  return children
}
