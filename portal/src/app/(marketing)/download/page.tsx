'use client'

import { SiteNav } from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n } from '@/lib/i18n'

const CLIENTS = [
  { os: 'macOS',   client: 'ClashX Pro',            arch: 'Apple Silicon / Intel',  url: '#', recommended: true  },
  { os: 'Windows', client: 'Clash Verge',            arch: 'x64 / ARM64',            url: '#', recommended: true  },
  { os: 'iOS',     client: 'Shadowrocket',           arch: 'App Store',              url: '#', recommended: true  },
  { os: 'Android', client: 'ClashMetaForAndroid',    arch: 'APK · arm64',            url: '#', recommended: true  },
  { os: 'Linux',   client: 'Clash Verge',            arch: '.deb / .rpm / AppImage', url: '#', recommended: false },
  { os: 'OpenWrt', client: 'OpenClash',              arch: 'Router firmware',        url: '#', recommended: false },
]

export default function DownloadPage() {
  const { t } = useI18n()
  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-14">
            <h1 className="text-5xl font-bold tracking-tighter mb-3">{t.download.title}</h1>
            <p className="text-muted-foreground max-w-2xl mx-auto">{t.download.sub}</p>
          </div>

          {/* Quick start */}
          <div className="glass-panel rounded-2xl p-6 mb-10">
            <h2 className="text-xs font-bold uppercase tracking-widest text-mirror mb-4">{t.download.step}</h2>
            <ol className="space-y-3">
              {t.download.steps.map((s, i) => (
                <li key={i} className="flex gap-3 text-sm">
                  <span className="w-6 h-6 shrink-0 rounded-full bg-mirror/10 border border-mirror/30 text-mirror font-mono text-xs grid place-items-center">{i + 1}</span>
                  <span className="text-foreground/90">{s}</span>
                </li>
              ))}
            </ol>
          </div>

          {/* Clients grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {CLIENTS.map((c) => (
              <div key={c.os} className="glass-panel rounded-2xl p-6 flex items-center justify-between gap-4 hover:border-mirror/40 transition-colors">
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <h3 className="font-bold">{c.os}</h3>
                    {c.recommended && (
                      <span className="text-[9px] font-bold uppercase tracking-widest text-mirror bg-mirror/10 border border-mirror/20 px-2 py-0.5 rounded-full">
                        {t.download.recommended}
                      </span>
                    )}
                  </div>
                  <p className="text-sm text-muted-foreground">{c.client}</p>
                  <p className="text-[10px] text-muted-foreground font-mono mt-1">{c.arch}</p>
                </div>
                <div className="flex flex-col gap-2 shrink-0">
                  <a href={c.url} className="text-xs font-bold bg-primary text-primary-foreground px-4 py-2 rounded-lg hover:bg-mirror transition-colors text-center">{t.download.install}</a>
                  <a href={c.url} className="text-[10px] text-muted-foreground hover:text-mirror text-center">{t.download.guide} →</a>
                </div>
              </div>
            ))}
          </div>
        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
