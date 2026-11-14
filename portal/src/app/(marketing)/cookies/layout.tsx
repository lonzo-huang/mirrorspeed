import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Cookie Policy',
  description:
    'MirrorSpeed uses only essential cookies for sign-in, plus browser localStorage for your language and theme preference. No advertising or tracking cookies.',
  alternates: { canonical: '/cookies' },
  openGraph: { url: '/cookies', title: 'Cookie Policy | MirrorSpeed' },
}

export default function CookiesLayout({ children }: { children: React.ReactNode }) {
  return children
}
