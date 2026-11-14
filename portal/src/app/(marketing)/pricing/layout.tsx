import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'VPN Pricing — Free Plan, or From $0.88/month',
  description: 'MirrorSpeed pricing: a free-forever plan, or paid plans from $0.88/month (billed every 2 years) with unlimited time, up to 1000 Mbps and 8 devices. 7-day money-back guarantee.',
  // hreflang 必须双向声明，只有一边指过去 Google 会直接忽略这组关系。
  alternates: {
    canonical: `${SITE_URL}/pricing`,
    languages: { en: `${SITE_URL}/pricing`, 'zh-CN': `${SITE_URL}/cn/pricing` },
  },
  openGraph: {
    title: 'VPN Pricing — Free Plan, or From $0.88/month',
    description: 'Free-forever plan · From $0.88/mo on the 2-year plan · 1000 Mbps · 8 devices',
    url: `${SITE_URL}/pricing`,
  },
}

export default function PricingLayout({ children }: { children: React.ReactNode }) {
  return children
}
