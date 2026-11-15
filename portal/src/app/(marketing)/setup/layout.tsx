import type { Metadata } from 'next'
import { SETUP_PLATFORMS, TROUBLESHOOTING } from '@/lib/setupGuide'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'Install and Connect — Windows, Android and HarmonyOS',
  description:
    'Step-by-step setup for MirrorSpeed on Windows, Android and HarmonyOS, plus what to do when the app connects but nothing loads.',
  alternates: {
    canonical: `${SITE_URL}/setup`,
    // 中文用户有自己的 9 篇图文教程，内容不是一一对应的翻译，
    // 所以这里把中文版指向教程索引页，而不是硬凑一个同名页面。
    languages: { en: `${SITE_URL}/setup`, 'zh-CN': `${SITE_URL}/cn/tutorials` },
  },
  openGraph: {
    url: `${SITE_URL}/setup`,
    title: 'Install and Connect | MirrorSpeed',
    description: 'Setup for Windows, Android and HarmonyOS, plus troubleshooting.',
  },
}

export default function SetupLayout({ children }: { children: React.ReactNode }) {
  // 每个平台一份 HowTo，外加一份排障流程 —— 步骤文本与页面显示的完全一致。
  const howTos = SETUP_PLATFORMS.filter(p => p.available).map(p => ({
    '@context': 'https://schema.org',
    '@type': 'HowTo',
    name: `Install MirrorSpeed on ${p.name}`,
    description: p.intro,
    inLanguage: 'en',
    totalTime: 'PT5M',
    estimatedCost: { '@type': 'MonetaryAmount', currency: 'USD', value: '0' },
    publisher: { '@id': `${SITE_URL}/#org` },
    step: p.steps.map((s, i) => ({
      '@type': 'HowToStep',
      position: i + 1,
      name: s.t,
      text: s.d,
      url: `${SITE_URL}/setup#${p.key}-step-${i + 1}`,
    })),
  }))

  const fix = {
    '@context': 'https://schema.org',
    '@type': 'HowTo',
    name: 'Fix a MirrorSpeed connection that shows connected but loads nothing',
    inLanguage: 'en',
    publisher: { '@id': `${SITE_URL}/#org` },
    step: TROUBLESHOOTING.map((s, i) => ({
      '@type': 'HowToStep',
      position: i + 1,
      name: s.t,
      text: s.d,
      url: `${SITE_URL}/setup#troubleshooting`,
    })),
  }

  return (
    <>
      {[...howTos, fix].map((j, i) => (
        <script
          key={i}
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(j) }}
        />
      ))}
      {children}
    </>
  )
}
