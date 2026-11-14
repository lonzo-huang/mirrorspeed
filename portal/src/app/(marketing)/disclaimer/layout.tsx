import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Disclaimer & Acceptable Use',
  description:
    'MirrorSpeed disclaimer: service purpose, your responsibility to comply with local law, prohibited activities, and limitation of liability.',
  alternates: { canonical: '/disclaimer' },
  openGraph: { url: '/disclaimer', title: 'Disclaimer | MirrorSpeed' },
}

export default function DisclaimerLayout({ children }: { children: React.ReactNode }) {
  return children
}
