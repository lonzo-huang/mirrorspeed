import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Terms of Service',
  description:
    'MirrorSpeed terms of service: subscription and billing terms, acceptable use, refund policy, account termination, and limitation of liability.',
  alternates: {
    canonical: '/terms',
    languages: { en: 'https://www.mirrorspeed.com/terms', 'zh-CN': 'https://www.mirrorspeed.com/cn/terms' },
  },
  openGraph: { url: '/terms', title: 'Terms of Service | MirrorSpeed' },
}

export default function TermsLayout({ children }: { children: React.ReactNode }) {
  return children
}
