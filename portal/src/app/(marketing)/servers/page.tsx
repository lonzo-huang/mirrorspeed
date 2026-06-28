'use client'

import { useEffect, useState } from 'react'
import { LandingChrome } from '@/components/landing/LandingPage'
import { ServerCard, SERVERS } from '@/components/site/ServerCard'
import { useI18n } from '@/lib/i18n'

export default function ServersPage() {
  const { t, lang } = useI18n()
  const [now, setNow] = useState('--:--:--')

  useEffect(() => {
    const tick = () => setNow(new Date().toLocaleTimeString())
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [])

  const avgLatency = Math.round(SERVERS.reduce((s, n) => s + n.latency, 0) / SERVERS.length)

  return (
    <LandingChrome forcedLang={lang === 'zh' ? 'zh' : 'en'}>
      <main className="px-6 pb-24">
        <div className="max-w-6xl mx-auto">
          <div className="flex justify-between items-end mb-12 flex-wrap gap-4">
            <div>
              <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">// Network</span>
              <h1 className="font-heading text-5xl sm:text-6xl font-black tracking-tighter mb-2">
                <span className="text-gradient-cyan">{t.servers.title}</span>
              </h1>
              <p className="text-app-secondary text-lg">{t.servers.sub}</p>
            </div>
            <div className="text-right font-mono text-[10px] uppercase text-app-muted tracking-widest">
              <div>Last refresh: {now}</div>
              <div className="mt-1">{SERVERS.length} locations · avg {avgLatency}ms</div>
            </div>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {SERVERS.map((s) => <ServerCard key={s.region} node={s} />)}
          </div>
        </div>
      </main>
    </LandingChrome>
  )
}
