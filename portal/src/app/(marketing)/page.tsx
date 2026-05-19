'use client'

import Link from 'next/link'
import {
  Shield, EyeOff, Monitor, Zap, Globe, Headphones,
  UserPlus, Copy, Wifi, Star, ChevronRight, ArrowRight,
} from 'lucide-react'
import { SiteNav } from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { ServerCard, SERVERS } from '@/components/site/ServerCard'
import { useI18n } from '@/lib/i18n'

const FEATURE_ICONS = [Shield, EyeOff, Monitor, Zap, Globe, Headphones]
const HOW_ICONS     = [UserPlus, Copy, Wifi]

export default function HomePage() {
  const { t } = useI18n()
  const featured = SERVERS.slice(0, 4)

  return (
    <div className="min-h-screen bg-background text-foreground selection:bg-mirror selection:text-background">
      <SiteNav />

      {/* ── Hero ── */}
      <header className="relative pt-24 pb-20 px-6 overflow-hidden">
        {/* dot-grid background */}
        <div
          className="absolute inset-0 -z-20 opacity-20"
          style={{
            backgroundImage: 'radial-gradient(circle, rgba(255,255,255,0.15) 1px, transparent 1px)',
            backgroundSize: '32px 32px',
          }}
        />
        {/* radial glow */}
        <div
          className="absolute inset-0 -z-10 opacity-40"
          style={{
            background: 'radial-gradient(ellipse at top, color-mix(in oklab, var(--color-mirror) 30%, transparent), transparent 65%)',
          }}
        />

        <div className="max-w-6xl mx-auto text-center">
          {/* badge */}
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-mirror/10 border border-mirror/20 text-mirror text-[11px] font-bold tracking-widest uppercase mb-8">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-mirror opacity-75" />
              <span className="relative inline-flex rounded-full h-2 w-2 bg-mirror" />
            </span>
            {t.hero.badge}
          </div>

          {/* headline */}
          <h1 className="text-6xl md:text-8xl font-extrabold tracking-tighter mb-6 leading-none">
            {t.hero.title1}{' '}
            <span className="text-shimmer">{t.hero.title2}</span>
          </h1>
          <p className="text-xl text-muted-foreground max-w-2xl mx-auto mb-10">
            {t.hero.sub}
          </p>

          {/* CTAs */}
          <div className="flex flex-col md:flex-row gap-4 justify-center items-center mb-6">
            <Link
              href="/login"
              className="group w-full md:w-auto flex items-center justify-center gap-2 px-8 py-4 bg-primary text-primary-foreground font-bold rounded-xl hover:shadow-[0_0_40px_color-mix(in_oklab,var(--color-mirror)_50%,transparent)] transition-all"
            >
              {t.hero.cta1}
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </Link>
            <Link
              href="/servers"
              className="w-full md:w-auto px-8 py-4 glass-panel font-bold rounded-xl hover:bg-white/10 transition-all"
            >
              {t.hero.cta2}
            </Link>
          </div>

          {/* social proof */}
          <p className="text-xs text-muted-foreground mb-14 flex items-center justify-center gap-1.5">
            <span className="flex">
              {[1, 2, 3, 4, 5].map((s) => (
                <Star key={s} className="w-3 h-3 fill-mirror text-mirror" />
              ))}
            </span>
            {t.hero.trusted}
          </p>

          {/* latency proof */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 max-w-4xl mx-auto">
            {featured.map((s) => (
              <div key={s.code} className="glass-panel p-4 rounded-2xl text-left">
                <span className="text-[10px] font-mono text-muted-foreground uppercase tracking-wider">
                  {s.flag} {s.code}
                </span>
                <div className="flex items-baseline gap-2 mt-1">
                  <span className="text-2xl font-bold font-mono">{s.latency}</span>
                  <span className="text-xs text-mirror">ms</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </header>

      {/* ── Stats Bar ── */}
      <section className="py-12 px-6 border-y border-border bg-white/[0.02]">
        <div className="max-w-5xl mx-auto grid grid-cols-2 md:grid-cols-4 gap-8">
          {t.stats.map((s, i) => (
            <div key={i} className="text-center">
              <div className="text-3xl md:text-4xl font-extrabold text-mirror tracking-tight mb-1">{s.value}</div>
              <div className="text-xs text-muted-foreground uppercase tracking-widest font-mono">{s.label}</div>
            </div>
          ))}
        </div>
      </section>

      {/* ── How It Works ── */}
      <section className="py-24 px-6">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl font-bold tracking-tight mb-3">{t.howItWorks.title}</h2>
            <p className="text-muted-foreground">{t.howItWorks.sub}</p>
          </div>
          <div className="grid md:grid-cols-3 gap-6 relative">
            <div className="hidden md:block absolute top-10 left-[calc(16.67%+1.5rem)] right-[calc(16.67%+1.5rem)] h-px border-t border-dashed border-mirror/30" />
            {t.howItWorks.steps.map((step, i) => {
              const Icon = HOW_ICONS[i]
              return (
                <div key={i} className="glass-panel p-8 rounded-2xl text-center relative">
                  <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-mirror/10 border border-mirror/20 mb-5 mx-auto relative">
                    <Icon className="w-6 h-6 text-mirror" />
                    <span className="absolute -top-2 -right-2 w-5 h-5 rounded-full bg-mirror text-background text-[10px] font-black grid place-items-center">
                      {i + 1}
                    </span>
                  </div>
                  <h3 className="font-bold text-lg mb-2">{step.title}</h3>
                  <p className="text-sm text-muted-foreground">{step.desc}</p>
                </div>
              )
            })}
          </div>
        </div>
      </section>

      {/* ── Features ── */}
      <section className="py-24 px-6 bg-white/[0.01]">
        <div className="max-w-6xl mx-auto">
          <div className="mb-14 text-center">
            <h2 className="text-4xl font-bold tracking-tight mb-3">{t.features.title}</h2>
            <p className="text-muted-foreground">{t.features.sub}</p>
          </div>
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
            {t.features.items.map((f, i) => {
              const Icon = FEATURE_ICONS[i]
              return (
                <div key={i} className="glass-panel p-6 rounded-2xl group hover:border-mirror/30 transition-colors">
                  <div className="w-11 h-11 rounded-xl bg-mirror/10 border border-mirror/20 mb-4 grid place-items-center text-mirror group-hover:bg-mirror/15 transition-colors">
                    <Icon className="w-5 h-5" />
                  </div>
                  <h3 className="font-bold mb-2">{f.t}</h3>
                  <p className="text-sm text-muted-foreground">{f.d}</p>
                </div>
              )
            })}
          </div>
        </div>
      </section>

      {/* ── Server Preview ── */}
      <section className="py-24 px-6">
        <div className="max-w-6xl mx-auto">
          <div className="flex justify-between items-end mb-12">
            <div>
              <h2 className="text-3xl font-bold tracking-tight mb-2">{t.servers.title}</h2>
              <p className="text-muted-foreground">{t.servers.sub}</p>
            </div>
            <Link href="/servers" className="hidden md:flex items-center gap-1 text-sm text-mirror hover:underline">
              View all <ChevronRight className="w-4 h-4" />
            </Link>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {featured.map((s) => (
              <ServerCard key={s.code} node={s} />
            ))}
          </div>
          <div className="mt-6 md:hidden text-center">
            <Link href="/servers" className="text-sm text-mirror hover:underline inline-flex items-center gap-1">
              View all servers <ChevronRight className="w-4 h-4" />
            </Link>
          </div>
        </div>
      </section>

      {/* ── Testimonials ── */}
      <section className="py-24 px-6 bg-white/[0.01]">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-14">
            <h2 className="text-4xl font-bold tracking-tight mb-3">{t.testimonials.title}</h2>
            <p className="text-muted-foreground">{t.testimonials.sub}</p>
          </div>
          <div className="grid md:grid-cols-3 gap-6">
            {t.testimonials.items.map((item, i) => (
              <div key={i} className="glass-panel p-7 rounded-2xl flex flex-col">
                <div className="flex mb-4">
                  {[1, 2, 3, 4, 5].map((s) => (
                    <Star key={s} className="w-4 h-4 fill-mirror text-mirror" />
                  ))}
                </div>
                <blockquote className="text-sm text-foreground/80 leading-relaxed flex-grow mb-6">
                  &ldquo;{item.body}&rdquo;
                </blockquote>
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 rounded-full bg-mirror/20 border border-mirror/30 grid place-items-center text-mirror font-bold text-sm">
                    {item.name[0]}
                  </div>
                  <div>
                    <p className="text-sm font-semibold">{item.name}</p>
                    <p className="text-[11px] text-muted-foreground">{item.role}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Pricing ── */}
      <section id="pricing" className="py-24 px-6">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-14">
            <h2 className="text-4xl font-bold tracking-tight mb-3">{t.pricing.title}</h2>
            <p className="text-muted-foreground">{t.pricing.sub}</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-5xl mx-auto">
            {t.pricing.plans.map((p, i) => {
              const popular = i === 1
              return (
                <div
                  key={i}
                  className={`glass-panel p-8 rounded-3xl flex flex-col relative ${popular ? 'border-mirror shadow-[0_0_40px_color-mix(in_oklab,var(--color-mirror)_10%,transparent)]' : ''}`}
                >
                  {popular && (
                    <div className="absolute -top-3 left-1/2 -translate-x-1/2 bg-mirror text-background text-[10px] font-black uppercase tracking-tighter px-4 py-1 rounded-full whitespace-nowrap">
                      {t.pricing.popular}
                    </div>
                  )}
                  <span className="text-sm text-muted-foreground mb-2">{p.name}</span>
                  <div className="flex items-baseline gap-1 mb-1">
                    <span className={`text-4xl font-bold ${popular ? 'text-mirror' : ''}`}>{p.price}</span>
                    <span className="text-muted-foreground">{p.per}</span>
                  </div>
                  {popular && <p className="text-[11px] text-mirror/70 mb-5">Best value · Save 58%</p>}
                  {!popular && <div className="mb-6" />}
                  <ul className="space-y-3 text-sm text-foreground/80 mb-10 flex-grow">
                    {p.feats.map((f, j) => (
                      <li key={j} className="flex items-center gap-2.5">
                        <span className="w-4 h-4 rounded-full bg-mirror/10 border border-mirror/30 flex items-center justify-center flex-shrink-0">
                          <span className="w-1.5 h-1.5 bg-mirror rounded-full" />
                        </span>
                        {f}
                      </li>
                    ))}
                  </ul>
                  <Link
                    href="/login"
                    className={`w-full py-3 text-center font-bold rounded-xl transition-all block ${
                      popular
                        ? 'bg-primary text-primary-foreground hover:shadow-[0_0_20px_color-mix(in_oklab,var(--color-mirror)_40%,transparent)]'
                        : 'border border-white/20 hover:bg-white/5'
                    }`}
                  >
                    {popular ? t.pricing.featured : t.pricing.select}
                  </Link>
                </div>
              )
            })}
          </div>
          <p className="text-center mt-8 text-sm text-muted-foreground flex items-center justify-center gap-2">
            <Shield className="w-4 h-4 text-mirror" />
            7-day money-back guarantee on all plans
          </p>
        </div>
      </section>

      {/* ── CTA Banner ── */}
      <section
        className="py-20 px-6 mx-6 mb-6 rounded-3xl relative overflow-hidden"
        style={{
          background: 'radial-gradient(ellipse at center, color-mix(in oklab, var(--color-mirror) 15%, transparent), transparent 70%), color-mix(in oklab, var(--color-foreground) 4%, transparent)',
          border: '1px solid color-mix(in oklab, var(--color-mirror) 20%, transparent)',
        }}
      >
        <div
          className="absolute inset-0 -z-10 opacity-10"
          style={{
            backgroundImage: 'radial-gradient(circle, rgba(255,255,255,0.4) 1px, transparent 1px)',
            backgroundSize: '24px 24px',
          }}
        />
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="text-4xl md:text-5xl font-extrabold tracking-tight mb-4 text-shimmer">
            {t.cta.title}
          </h2>
          <p className="text-muted-foreground mb-8 text-lg">{t.cta.sub}</p>
          <Link
            href="/login"
            className="group inline-flex items-center gap-2 px-10 py-4 bg-primary text-primary-foreground font-bold rounded-xl hover:shadow-[0_0_40px_color-mix(in_oklab,var(--color-mirror)_50%,transparent)] transition-all text-lg"
          >
            {t.cta.btn}
            <ArrowRight className="w-5 h-5 group-hover:translate-x-1 transition-transform" />
          </Link>
        </div>
      </section>

      {/* ── FAQ ── */}
      <section id="faq" className="py-24 px-6">
        <div className="max-w-3xl mx-auto">
          <h2 className="text-4xl font-bold tracking-tight mb-12 text-center">{t.faq.title}</h2>
          <div className="space-y-3">
            {t.faq.items.map((item, i) => (
              <details key={i} className="glass-panel rounded-2xl p-6 group">
                <summary className="cursor-pointer font-semibold flex justify-between items-center list-none">
                  {item.q}
                  <span className="text-mirror text-xl group-open:rotate-45 transition-transform flex-shrink-0 ml-4">+</span>
                </summary>
                <p className="mt-4 text-sm text-muted-foreground leading-relaxed">{item.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      <SiteFooter />
    </div>
  )
}
