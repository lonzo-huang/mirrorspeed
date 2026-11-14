import type { Metadata } from 'next'

export const metadata: Metadata = {
  // 标题自带品牌名 → 用 absolute，避免模板再追加一次。
  title: { absolute: 'About MirrorSpeed — Who Builds It and How It Works' },
  description:
    'MirrorSpeed is a VPN and network accelerator for Android, Windows and HarmonyOS, with a free-forever plan and paid plans from $0.88/month. What we build, how the tunnel works, and what we do not log.',
  alternates: { canonical: '/about' },
  openGraph: {
    url: '/about',
    title: 'About MirrorSpeed',
    description: 'What MirrorSpeed is, how the tunnel works, and what we do not log.',
  },
}

export default function AboutLayout({ children }: { children: React.ReactNode }) {
  return children
}
