'use client'

import Link from 'next/link'
import { LandingChrome } from '@/components/landing/LandingPage'
import { SETUP_PLATFORMS, TROUBLESHOOTING } from '@/lib/setupGuide'
import { comingSoonPlatforms } from '@/lib/product'

// 英文上手指南（中文用户走 /cn/tutorials 的 9 篇图文教程）。
export default function SetupView() {
  const soon = comingSoonPlatforms('en')

  return (
    <LandingChrome forcedLang="en">
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // Setup
            </span>
            <h1 className="font-heading text-3xl md:text-5xl font-black tracking-tighter mb-5 leading-tight">
              <span className="text-gradient-cyan">Install and connect</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto leading-relaxed">
              Installing takes a couple of minutes and needs no manual configuration. Pick your
              platform below. If you are connected but nothing loads, jump to troubleshooting.
            </p>
          </div>

          {SETUP_PLATFORMS.filter(p => p.available).map(p => (
            <section key={p.key} className="mb-10" id={p.key}>
              <h2 className="font-heading text-2xl font-bold mb-2 text-app-primary">{p.name}</h2>
              <p className="text-sm text-app-secondary leading-relaxed mb-5">{p.intro}</p>

              <ol className="space-y-3">
                {p.steps.map((s, i) => (
                  <li key={i} className="glass-panel rounded-2xl p-6" id={`${p.key}-step-${i + 1}`}>
                    <h3 className="font-semibold mb-2 text-app-primary">
                      <span className="font-mono text-accent-cyan mr-2">{i + 1}.</span>
                      {s.t}
                    </h3>
                    <p className="text-sm text-app-secondary leading-relaxed">{s.d}</p>
                  </li>
                ))}
              </ol>

              {p.tips && p.tips.length > 0 && (
                <ul className="mt-4 space-y-2">
                  {p.tips.map((tip, i) => (
                    <li key={i} className="text-xs text-app-muted leading-relaxed">— {tip}</li>
                  ))}
                </ul>
              )}
            </section>
          ))}

          {soon.length > 0 && (
            <section className="mb-10 glass-panel rounded-2xl p-6">
              <h2 className="text-lg font-bold mb-2 text-app-primary">
                {soon.join(' and ')}
              </h2>
              <p className="text-sm text-app-secondary leading-relaxed">
                The {soon.join(' and ')} apps are built and currently in App Store review. They are
                not downloadable yet — this page will list the steps the day they go live.
              </p>
            </section>
          )}

          <section className="mb-10" id="troubleshooting">
            <h2 className="font-heading text-2xl font-bold mb-2 text-app-primary">
              Connected, but nothing loads
            </h2>
            <p className="text-sm text-app-secondary leading-relaxed mb-5">
              This means the tunnel came up but traffic is not getting through. Work down this list
              in order — the first two steps resolve most cases.
            </p>
            <ol className="space-y-3">
              {TROUBLESHOOTING.map((s, i) => (
                <li key={i} className="glass-panel rounded-2xl p-6">
                  <h3 className="font-semibold mb-2 text-app-primary">
                    <span className="font-mono text-accent-cyan mr-2">{i + 1}.</span>
                    {s.t}
                  </h3>
                  <p className="text-sm text-app-secondary leading-relaxed">{s.d}</p>
                </li>
              ))}
            </ol>
            <p className="mt-4 text-sm text-app-secondary">
              Still stuck?{' '}
              <Link href="/support" className="text-accent-cyan hover:underline">
                Message our engineers
              </Link>
              {' '}— tell us your platform and which steps you already tried.
            </p>
          </section>

          <div className="flex flex-wrap gap-3">
            <Link
              href="/download"
              className="rounded-full px-5 py-2.5 text-sm font-semibold"
              style={{ background: 'linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)', color: '#000' }}
            >
              Download
            </Link>
            <Link
              href="/help"
              className="glass rounded-full px-5 py-2.5 text-sm font-semibold text-app-primary hover:bg-app-tertiary"
            >
              Help &amp; FAQ
            </Link>
          </div>
        </article>
      </main>
    </LandingChrome>
  )
}
