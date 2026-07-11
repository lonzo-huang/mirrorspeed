'use client'

import Link from 'next/link'
import { useParams } from 'next/navigation'
import { LandingChrome } from '@/components/landing/LandingPage'
import { getTutorial } from '@/lib/tutorials'

// 使用教程详情页（仅中文）。
export default function TutorialDetailPage() {
  const params = useParams()
  const slug = typeof params.slug === 'string' ? params.slug : Array.isArray(params.slug) ? params.slug[0] : ''
  const tutorial = getTutorial(slug)

  return (
    <LandingChrome forcedLang="zh">
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <Link href="/tutorials" className="text-sm text-app-secondary hover:text-app-primary inline-block mb-8">
            ← 返回教程列表
          </Link>

          {!tutorial ? (
            <div className="glass-panel rounded-2xl p-8 text-center">
              <p className="text-app-secondary">未找到该教程。</p>
            </div>
          ) : (
            <>
              <div className="mb-10">
                <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
                  // {tutorial.category}
                </span>
                <h1 className="font-heading text-3xl md:text-4xl font-black tracking-tighter mb-4 text-app-primary">
                  {tutorial.title}
                </h1>
                <p className="text-app-secondary text-lg">{tutorial.summary}</p>
              </div>

              <ol className="space-y-4">
                {tutorial.steps.map((s, i) => (
                  <li key={i} className="glass-panel rounded-2xl p-6 flex gap-4">
                    <span className="shrink-0 flex h-8 w-8 items-center justify-center rounded-full bg-accent-cyan/15 text-accent-cyan font-bold text-sm">
                      {i + 1}
                    </span>
                    <div>
                      <h2 className="text-base font-bold mb-1.5 text-app-primary">{s.t}</h2>
                      <p className="text-sm text-app-secondary leading-relaxed">{s.d}</p>
                    </div>
                  </li>
                ))}
              </ol>

              {tutorial.tips && tutorial.tips.length > 0 && (
                <div className="glass-panel rounded-2xl p-6 mt-6 border-accent-cyan/20">
                  <h2 className="text-sm font-bold mb-3 text-app-primary">💡 小提示</h2>
                  <ul className="space-y-2">
                    {tutorial.tips.map((tip, i) => (
                      <li key={i} className="text-sm text-app-secondary leading-relaxed">· {tip}</li>
                    ))}
                  </ul>
                </div>
              )}

              <div className="text-center mt-10">
                <p className="text-sm text-app-secondary mb-3">按教程操作后仍有问题？</p>
                <Link href="/support" className="text-accent-cyan hover:underline text-sm">联系客服 →</Link>
              </div>
            </>
          )}
        </article>
      </main>
    </LandingChrome>
  )
}
