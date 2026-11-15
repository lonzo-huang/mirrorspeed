import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'VPN Use Cases — AI Tools, Streaming, Gaming',
  description:
    'Practical guides for the problems people actually hit: AI chat connections dropping, 4K video buffering, high ping in online games, and how to choose a VPN.',
  alternates: {
    canonical: `${SITE_URL}/use-cases`,
    languages: { en: `${SITE_URL}/use-cases`, 'zh-CN': `${SITE_URL}/cn/use-cases` },
  },
  openGraph: { url: `${SITE_URL}/use-cases`, title: 'VPN Use Cases | MirrorSpeed' },
}

export default function UseCasesLayout({ children }: { children: React.ReactNode }) {
  return children
}
