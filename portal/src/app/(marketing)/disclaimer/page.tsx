'use client'

import { SiteNav } from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n } from '@/lib/i18n'

export default function DisclaimerPage() {
  const { t } = useI18n()
  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <article className="max-w-3xl mx-auto">
          <p className="text-[11px] font-mono uppercase tracking-widest text-muted-foreground mb-3">{t.disclaimer.updated}</p>
          <h1 className="text-4xl md:text-5xl font-bold tracking-tighter mb-6">{t.disclaimer.title}</h1>
          <p className="text-muted-foreground text-lg mb-12">{t.disclaimer.intro}</p>

          <div className="space-y-8">
            {t.disclaimer.sections.map((s, i) => (
              <section key={i} className="glass-panel rounded-2xl p-6">
                <h2 className="text-lg font-bold mb-3">{s.h}</h2>
                <p className="text-sm text-foreground/80 leading-relaxed">{s.p}</p>
              </section>
            ))}
          </div>
        </article>
      </main>
      <SiteFooter />
    </div>
  )
}
