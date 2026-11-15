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
  if (!u) return { title: '未找到', robots: { index: false, follow: true } }
  const url = `${SITE_URL}/cn/use-cases/${u.slug}`
  return {
    title: { absolute: `${u.zh.title} | 镜速VPN` },
    description: u.zh.summary,
    alternates: {
      canonical: url,
      languages: { en: `${SITE_URL}/use-cases/${u.slug}`, 'zh-CN': url },
    },
    openGraph: {
      url, type: 'article', locale: 'zh_CN',
      title: u.zh.title, description: u.zh.summary,
      images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: u.zh.h1 }],
    },
  }
}

export default function CnUseCaseLayout(
  { children, params }: { children: React.ReactNode; params: { slug: string } }
) {
  const u = getUseCase(params.slug)
  if (!u) return children

  const faq = {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    inLanguage: 'zh-CN',
    mainEntity: u.zh.faq.map(f => ({
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
