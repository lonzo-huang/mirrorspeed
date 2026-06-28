import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Support — Contact MirrorSpeed',
  description: 'Talk to real engineers. We typically reply within 1 business day. Email mirrorspeed@mirrorquant.com or send a message from this page.',
  alternates: { canonical: `${SITE_URL}/support` },
}

export default function SupportLayout({ children }: { children: React.ReactNode }) {
  return children
}
