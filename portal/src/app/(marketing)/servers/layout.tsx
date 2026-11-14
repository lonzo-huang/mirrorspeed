import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'VPN Server Network — Live Latency and Load',
  description: '20+ MirrorSpeed VPN edge nodes across Asia, the Americas, and Europe. Live latency, load, and capacity. Pick the fastest server automatically or manually.',
  alternates: { canonical: `${SITE_URL}/servers` },
  openGraph: {
    title: 'VPN Server Network — Live Latency and Load',
    description: 'Live latency · 20+ nodes · Asia, Americas, Europe',
    url: `${SITE_URL}/servers`,
  },
}

export default function ServersLayout({ children }: { children: React.ReactNode }) {
  return children
}
