import type { Metadata } from 'next'
import { getUseCase, USE_CASES } from '@/lib/useCases'

const SITE_URL = 'https://www.mirrorspeed.com'

export async function generateStaticParams() {
  return USE_CASES.map(u => ({ slug: u.slug }))
}

export async function generateMetadata(
  { params }: { params: { slug: string } }
): Promise<Metadata> {
  const u = getUseCase(params.slug)
  if (!u) return { title: 'Not found', robots: { index: false, follow: true } }
  const url = `${SITE_URL}/use-cases/${u.slug}`
  return {
    title: { absolute: `${u.en.title} | MirrorSpeed` },
    description: u.en.summary,
    alternates: {
      canonical: url,
      languages: { en: url, 'zh-CN': `${SITE_URL}/cn/use-cases/${u.slug}` },
    },
    openGraph: {
      url, type: 'article', locale: 'en_US',
      title: u.en.title, description: u.en.summary,
      images: [{ url: '/og-en.png', width: 1200, height: 630, alt: u.en.h1 }],
    },
  }
}

export default function UseCaseLayout(
  { children, params }: { children: React.ReactNode; params: { slug: string } }
) {
  const u = getUseCase(params.slug)
  if (!u) return children

  // FAQPage 结构化数据，问答文本与页面可见内容取自同一份数据，不会出现
  // 「标记里写一套、页面上显示另一套」被判违规的情况。
  const faq = {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    inLanguage: 'en',
    mainEntity: u.en.faq.map(f => ({
      '@type': 'Question',
      name: f.q,
      acceptedAnswer: { '@type': 'Answer', text: f.a },
    })),
  }

  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(faq) }} />
      {children}
    </>
  )
}
