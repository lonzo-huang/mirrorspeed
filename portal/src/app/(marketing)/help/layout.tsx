import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Help Center — MirrorSpeed VPN',
  description: 'How to connect, choose nodes, free trial time, ads-for-time, smart vs global routing, and subscription management — all answered by real engineers.',
  alternates: { canonical: `${SITE_URL}/help` },
}

export default function HelpLayout({ children }: { children: React.ReactNode }) {
  return children
}
