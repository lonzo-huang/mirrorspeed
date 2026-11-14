import type { Metadata } from 'next'

// 法律页此前无 metadata → 继承根布局的首页 title + canonical='/'，
// 等于告诉 Google「本页是首页副本」，永远不会被收录。此处给出自身 canonical。
export const metadata: Metadata = {
  title: 'Privacy Policy — What We Do and Do Not Log',
  description:
    'MirrorSpeed privacy policy: what we collect, what we never log (browsing history, traffic destinations, DNS queries, connection IPs), how long data is kept, and how to delete your account.',
  alternates: { canonical: '/privacy' },
  openGraph: { url: '/privacy', title: 'Privacy Policy | MirrorSpeed' },
}

export default function PrivacyLayout({ children }: { children: React.ReactNode }) {
  return children
}
