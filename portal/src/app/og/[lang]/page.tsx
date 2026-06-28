import OGCard from '@/components/landing/OGCard'

// /og/cn  → Chinese 1200×630 social card
// /og/en  → English 1200×630 social card
// 仅用于通过 Playwright 截图重新生成 /public/og-cn.png 与 /public/og-en.png 时访问。
// Twitter / X 等社交平台读取 /cn.html 与 /en.html 里的 <meta og:image>，不会跑这两个路由。

export default function Page({ params }: { params: { lang: string } }) {
  const lang = params.lang === 'cn' ? 'zh' : 'en'
  return <OGCard lang={lang} />
}

export function generateStaticParams() {
  return [{ lang: 'cn' }, { lang: 'en' }]
}
