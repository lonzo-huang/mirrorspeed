'use client'

import { LandingChrome } from '@/components/landing/LandingPage'
import { useI18n } from '@/lib/i18n'

export default function DisclaimerPage() {
  const { t, lang } = useI18n()
  return (
    <LandingChrome forcedLang={lang === 'zh' ? 'zh' : 'en'}>
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {lang === 'zh' ? '免责声明' : 'Disclaimer'}
            </span>
            <p className="text-[11px] font-mono uppercase tracking-widest text-app-muted mb-3">{t.disclaimer.updated}</p>
            <h1 className="font-heading text-4xl md:text-6xl font-black tracking-tighter mb-6">
              <span className="text-gradient-cyan">{t.disclaimer.title}</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto">{t.disclaimer.intro}</p>
          </div>

          <div className="space-y-4">
            {t.disclaimer.sections.map((s, i) => (
              <section key={i} className="glass-panel rounded-2xl p-6">
                <h2 className="text-lg font-bold mb-3 text-app-primary">{s.h}</h2>
                <p className="text-sm text-app-secondary leading-relaxed">{s.p}</p>
              </section>
            ))}
          </div>
        </article>
      </main>
    </LandingChrome>
  )
}
