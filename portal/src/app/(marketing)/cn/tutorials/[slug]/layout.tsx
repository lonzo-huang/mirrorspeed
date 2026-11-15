import type { Metadata } from 'next'
import { getTutorial, TUTORIALS } from '@/lib/tutorials'

// 每篇教程生成自己的 title/description/canonical（此前全部继承首页，无法收录）。
// 同时预生成静态参数，让这 9 篇随构建产出静态 HTML，爬虫无需执行 JS 即可读到正文。
export async function generateStaticParams() {
  return TUTORIALS.map(t => ({ slug: t.slug }))
}

export async function generateMetadata(
  { params }: { params: { slug: string } }
): Promise<Metadata> {
  const tutorial = getTutorial(params.slug)
  if (!tutorial) {
    return { title: '教程未找到', robots: { index: false, follow: true } }
  }
  const url = `/cn/tutorials/${tutorial.slug}`
  return {
    title: { absolute: `${tutorial.title} — 镜速加速器教程` },
    description: `${tutorial.summary} 共 ${tutorial.steps.length} 个步骤，含常见问题处理。`,
    alternates: { canonical: url, languages: { 'zh-CN': url } },
    openGraph: {
      url,
      title: `${tutorial.title} — 镜速加速器教程`,
      description: tutorial.summary,
      locale: 'zh_CN',
      type: 'article',
      images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: tutorial.title }],
    },
  }
}

const SITE_URL = 'https://www.mirrorspeed.com'

export default function TutorialLayout(
  { children, params }: { children: React.ReactNode; params: { slug: string } }
) {
  const tutorial = getTutorial(params.slug)
  if (!tutorial) return children

  // HowTo 结构化数据：步骤教程的标准类型，有机会拿到富摘要，
  // 也让 AI 能直接引用「第几步做什么」。
  const howTo = {
    '@context': 'https://schema.org',
    '@type': 'HowTo',
    name: tutorial.title,
    description: tutorial.summary,
    inLanguage: 'zh-CN',
    totalTime: 'PT5M',
    estimatedCost: { '@type': 'MonetaryAmount', currency: 'CNY', value: '0' },
    publisher: { '@id': `${SITE_URL}/#org` },
    step: tutorial.steps.map((s, i) => ({
      '@type': 'HowToStep',
      position: i + 1,
      name: s.t,
      text: s.d,
      url: `${SITE_URL}/cn/tutorials/${tutorial.slug}#step-${i + 1}`,
    })),
  }

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(howTo) }}
      />
      {children}
    </>
  )
}
