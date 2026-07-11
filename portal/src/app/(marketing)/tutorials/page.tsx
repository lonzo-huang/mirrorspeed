'use client'

import Link from 'next/link'
import { LandingChrome } from '@/components/landing/LandingPage'
import { TUTORIALS, TUTORIAL_CATEGORIES } from '@/lib/tutorials'

// 使用教程索引页（仅中文）。始终以中文渲染。
export default function TutorialsPage() {
  return (
    <LandingChrome forcedLang="zh">
      <main className="px-6 pb-24">
        <article className="max-w-4xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // 使用教程
            </span>
            <h1 className="font-heading text-4xl md:text-6xl font-black tracking-tighter mb-6">
              <span className="text-gradient-cyan">镜速加速器 使用教程</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto">
              从安装、连接到常见问题排查，按你的设备选择对应教程。遇到问题也可随时联系客服。
            </p>
          </div>

          {TUTORIAL_CATEGORIES.map(cat => {
            const items = TUTORIALS.filter(t => t.category === cat)
            if (!items.length) return null
            return (
              <section key={cat} className="mb-10">
                <h2 className="font-mono text-[11px] uppercase tracking-widest text-app-muted mb-4">{cat}</h2>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  {items.map(t => (
                    <Link
                      key={t.slug}
                      href={`/tutorials/${t.slug}`}
                      className="glass-panel rounded-2xl p-6 block hover:bg-app-tertiary transition-colors"
                    >
                      <h3 className="text-lg font-bold mb-2 text-app-primary">{t.title}</h3>
                      <p className="text-sm text-app-secondary leading-relaxed">{t.summary}</p>
                      <span className="inline-block mt-3 text-sm text-accent-cyan">查看教程 →</span>
                    </Link>
                  ))}
                </div>
              </section>
            )
          })}
        </article>
      </main>
    </LandingChrome>
  )
}
