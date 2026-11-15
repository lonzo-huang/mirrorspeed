'use client'

import Link from 'next/link'
import { LandingChrome } from '@/components/landing/LandingPage'
import { USE_CASES, type UseCase } from '@/lib/useCases'

// 场景落地页（中英共用一套渲染，内容按 lang 取）。
export function UseCaseView({ useCase, lang }: { useCase: UseCase; lang: 'en' | 'zh' }) {
  const zh = lang === 'zh'
  const c = zh ? useCase.zh : useCase.en
  const base = zh ? '/cn/use-cases' : '/use-cases'
  const others = USE_CASES.filter(u => u.slug !== useCase.slug)

  return (
    <LandingChrome forcedLang={lang}>
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <Link href={base} className="text-sm text-app-secondary hover:text-app-primary inline-block mb-8">
            ← {zh ? '返回使用场景' : 'All use cases'}
          </Link>

          <header className="mb-10">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {zh ? '使用场景' : 'Use case'}
            </span>
            <h1 className="font-heading text-3xl md:text-5xl font-black tracking-tighter mb-5 leading-tight break-words">
              <span className="text-gradient-cyan">{c.h1}</span>
            </h1>
            <p className="text-app-secondary text-lg leading-relaxed">{c.intro}</p>
          </header>

          <div className="space-y-4">
            {c.sections.map((s, i) => (
              <section key={i} className="glass-panel rounded-2xl p-6">
                <h2 className="text-lg font-bold mb-3 text-app-primary">{s.h}</h2>
                <p className="text-sm text-app-secondary leading-relaxed">{s.p}</p>
              </section>
            ))}
          </div>

          {/* 常见问题：与页面上的 FAQPage 结构化数据使用同一份文本 */}
          <section className="mt-10">
            <h2 className="font-heading text-2xl font-bold mb-4 text-app-primary">
              {zh ? '常见问题' : 'Common questions'}
            </h2>
            <div className="space-y-3">
              {c.faq.map((f, i) => (
                <div key={i} className="glass-panel rounded-2xl p-6">
                  <h3 className="font-semibold mb-2 text-app-primary">{f.q}</h3>
                  <p className="text-sm text-app-secondary leading-relaxed">{f.a}</p>
                </div>
              ))}
            </div>
          </section>

          <div className="mt-10 flex flex-wrap gap-3">
            <Link
              href={zh ? '/cn/download' : '/download'}
              className="rounded-full px-5 py-2.5 text-sm font-semibold"
              style={{ background: 'linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)', color: '#000' }}
            >
              {zh ? '免费下载试用' : 'Download free'}
            </Link>
            <Link
              href={zh ? '/cn/pricing' : '/pricing'}
              className="glass rounded-full px-5 py-2.5 text-sm font-semibold text-app-primary hover:bg-app-tertiary"
            >
              {zh ? '查看价格' : 'See pricing'}
            </Link>
          </div>

          {others.length > 0 && (
            <nav className="mt-12 pt-8 border-t border-app-subtle">
              <h2 className="font-mono text-[11px] uppercase tracking-widest text-app-muted mb-4">
                {zh ? '其他场景' : 'Other use cases'}
              </h2>
              <ul className="space-y-2">
                {others.map(u => (
                  <li key={u.slug}>
                    <Link href={`${base}/${u.slug}`} className="text-sm text-accent-cyan hover:underline">
                      {(zh ? u.zh : u.en).h1}
                    </Link>
                  </li>
                ))}
              </ul>
            </nav>
          )}
        </article>
      </main>
    </LandingChrome>
  )
}

// 场景索引页
export function UseCaseIndexView({ lang }: { lang: 'en' | 'zh' }) {
  const zh = lang === 'zh'
  const base = zh ? '/cn/use-cases' : '/use-cases'

  return (
    <LandingChrome forcedLang={lang}>
      <main className="px-6 pb-24">
        <article className="max-w-4xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {zh ? '使用场景' : 'Use cases'}
            </span>
            <h1 className="font-heading text-3xl md:text-5xl font-black tracking-tighter mb-5 leading-tight">
              <span className="text-gradient-cyan">
                {zh ? '常见使用场景' : 'What people use MirrorSpeed for'}
              </span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto leading-relaxed">
              {zh
                ? '按你要解决的问题选择：AI 工具连不稳、视频缓冲、游戏延迟高，以及加速器到底该怎么挑。'
                : 'Pick the problem you are trying to solve: unstable AI chat, buffering video, high game ping, or how to choose a provider at all.'}
            </p>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {USE_CASES.map(u => {
              const c = zh ? u.zh : u.en
              return (
                <Link
                  key={u.slug}
                  href={`${base}/${u.slug}`}
                  className="glass-panel rounded-2xl p-6 block hover:bg-app-tertiary transition-colors"
                >
                  <h2 className="text-lg font-bold mb-2 text-app-primary">{c.h1}</h2>
                  <p className="text-sm text-app-secondary leading-relaxed">{c.summary}</p>
                  <span className="inline-block mt-3 text-sm text-accent-cyan">
                    {zh ? '查看 →' : 'Read →'}
                  </span>
                </Link>
              )
            })}
          </div>
        </article>
      </main>
    </LandingChrome>
  )
}
