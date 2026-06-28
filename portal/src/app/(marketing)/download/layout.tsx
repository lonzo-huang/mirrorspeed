import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Download MirrorSpeed — Android, HarmonyOS, Windows',
  description: 'Download MirrorSpeed VPN for Android, HarmonyOS, and Windows. Zero configuration, one-tap connect, free forever tier.',
  alternates: { canonical: `${SITE_URL}/download` },
  openGraph: {
    title: 'Download MirrorSpeed — Android · HarmonyOS · Windows',
    description: 'One-tap connect · Free forever tier · 1000 Mbps · 20+ global edges',
    url: `${SITE_URL}/download`,
  },
}

export default function DownloadLayout({ children }: { children: React.ReactNode }) {
  return children
}
