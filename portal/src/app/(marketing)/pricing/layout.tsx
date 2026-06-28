import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Pricing — MirrorSpeed VPN · From $1.00/mo',
  description: 'Transparent VPN pricing. Free forever tier, paid plans from $1.00/month. 7-day money-back guarantee, unlimited speed up to 1000 Mbps, no logs, 20+ global edges.',
  alternates: { canonical: `${SITE_URL}/pricing` },
  openGraph: {
    title: 'Pricing — MirrorSpeed VPN · From $1.00/mo',
    description: 'Free forever tier · $1.00/mo (2-year plan) · 1000 Mbps · No logs · 20+ edges',
    url: `${SITE_URL}/pricing`,
  },
}

export default function PricingLayout({ children }: { children: React.ReactNode }) {
  return children
}
