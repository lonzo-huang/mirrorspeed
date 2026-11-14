import { t } from './i18n'

// 首页 FAQ 的结构化数据。问答文本直接取自 i18n，与页面显示的内容保持一致——
// 结构化数据与可见内容不一致会被 Google 判为违规，所以这里不另写一份文案。
//
// 覆盖的 7 条问答与 LandingPage.jsx 里 FAQ 组件的顺序一致。
const FAQ_KEYS = [
  ['faq_q7', 'faq_a7'],
  ['faq_q1', 'faq_a1'],
  ['faq_q2', 'faq_a2'],
  ['faq_q3', 'faq_a3'],
  ['faq_q4', 'faq_a4'],
  ['faq_q5', 'faq_a5'],
  ['faq_q6', 'faq_a6'],
] as const

export function FaqJsonLd({ lang = 'en' }: { lang?: string }) {
  const json = {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    inLanguage: lang === 'zh' ? 'zh-CN' : lang,
    mainEntity: FAQ_KEYS.map(([q, a]) => ({
      '@type': 'Question',
      name: t(q, lang),
      acceptedAnswer: { '@type': 'Answer', text: t(a, lang) },
    })),
  }
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(json) }}
    />
  )
}
