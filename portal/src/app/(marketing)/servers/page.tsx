'use client'

import { useEffect, useState } from 'react'
import { SiteNav } from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { ServerCard, SERVERS } from '@/components/site/ServerCard'
import { useI18n } from '@/lib/i18n'

export default function ServersPage() {
  const { t } = useI18n()
  const [now, setNow] = useState('--:--:--')

  useEffect(() => {
    const tick = () => setNow(new Date().toLocaleTimeString())
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [])

  const avgLatency = Math.round(SERVERS.reduce((s, n) => s + n.latency, 0) / SERVERS.length)

  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <div className="max-w-6xl mx-auto">
          <div className="flex justify-between items-end mb-12 flex-wrap gap-4">
            <div>
              <h1 className="text-4xl font-bold tracking-tight mb-2">{t.servers.title}</h1>
              <p className="text-muted-foreground">{t.servers.sub}</p>
            </div>
            <div className="text-right font-mono text-[10px] uppercase text-muted-foreground tracking-widest">
              <div>Last refresh: {now}</div>
              <div className="mt-1">{SERVERS.length} nodes · avg {avgLatency}ms</div>
            </div>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {SERVERS.map((s) => <ServerCard key={s.code} node={s} />)}
          </div>
        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
