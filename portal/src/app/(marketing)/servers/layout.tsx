import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Global Edge Network — MirrorSpeed VPN Servers',
  description: '20+ MirrorSpeed VPN edge nodes across Asia, the Americas, and Europe. Live latency, load, and capacity. Pick the fastest server automatically or manually.',
  alternates: { canonical: `${SITE_URL}/servers` },
  openGraph: {
    title: 'Global Edge Network — MirrorSpeed VPN Servers',
    description: 'Live latency · 20+ nodes · Asia, Americas, Europe',
    url: `${SITE_URL}/servers`,
  },
}

export default function ServersLayout({ children }: { children: React.ReactNode }) {
  return children
}
