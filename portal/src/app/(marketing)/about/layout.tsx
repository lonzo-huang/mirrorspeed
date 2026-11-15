import type { Metadata } from 'next'

export const metadata: Metadata = {
  // 标题自带品牌名 → 用 absolute，避免模板再追加一次。
  title: { absolute: 'About MirrorSpeed — Who Builds It and How It Works' },
  // 控制在 160 字符内，否则搜索结果里会被截断。
  description:
    'Who operates MirrorSpeed, how the tunnel works, what we do not log, and how to reach the engineers who build it.',
  alternates: {
    canonical: '/about',
    languages: { en: 'https://www.mirrorspeed.com/about', 'zh-CN': 'https://www.mirrorspeed.com/cn/about' },
  },
  openGraph: {
    url: '/about',
    title: 'About MirrorSpeed',
    description: 'What MirrorSpeed is, how the tunnel works, and what we do not log.',
  },
}

export default function AboutLayout({ children }: { children: React.ReactNode }) {
  return children
}
