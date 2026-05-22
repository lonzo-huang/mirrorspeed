'use client'

import { useState } from 'react'
import { Loader2, Shield } from 'lucide-react'
import { SiteNav } from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n } from '@/lib/i18n'

const PLAN_KEYS = ['yearly', 'biennial', 'monthly', 'quarterly'] as const
type PlanKey = typeof PLAN_KEYS[number]

export default function PricingPage() {
  const { t, lang } = useI18n()
  const [loading, setLoading] = useState<PlanKey | null>(null)
  const [error, setError]     = useState<string | null>(null)

  const handleCheckout = async (plan: PlanKey) => {
    setError(null)
    setLoading(plan)
    try {
      const res = await fetch('/api/billing/checkout', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ plan }),
      })
      const { url, error: apiErr } = await res.json()
      if (url) {
        window.location.href = url
      } else {
        if (res.status === 401) {
          window.location.href = '/login?next=/pricing'
        } else {
          setError(apiErr ?? 'Checkout failed. Please try again.')
          setLoading(null)
        }
      }
    } catch {
      setError('An error occurred. Please try again.')
      setLoading(null)
    }
  }

  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-14">
            <h1 className="text-5xl font-bold tracking-tighter mb-3">{t.pricing.title}</h1>
            <p className="text-muted-foreground">{t.pricing.sub}</p>
          </div>

          {error && (
            <div className="max-w-md mx-auto mb-8 px-4 py-3 rounded-xl bg-destructive/10 border border-destructive/30 text-sm text-center text-destructive-foreground">
              {error}
            </div>
          )}

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
            {t.pricing.plans.map((p, i) => {
              const popular   = i === 0   // 年付 = Most Popular
              const planKey   = PLAN_KEYS[i]
              const isLoading = loading === planKey

              return (
                <div
                  key={i}
                  className={`glass-panel p-7 rounded-3xl flex flex-col relative ${
                    popular
                      ? 'border-mirror shadow-[0_0_40px_color-mix(in_oklab,var(--color-mirror)_10%,transparent)]'
                      : ''
                  }`}
                >
                  {popular && (
                    <div className="absolute -top-3 left-1/2 -translate-x-1/2 bg-mirror text-background text-[10px] font-black uppercase tracking-tighter px-4 py-1 rounded-full whitespace-nowrap">
                      {t.pricing.popular}
                    </div>
                  )}

                  <span className="text-sm text-muted-foreground mb-2">{p.name}</span>
                  <div className="flex items-baseline gap-1 mb-0.5">
                    <span className={`text-4xl font-bold ${popular ? 'text-mirror' : ''}`}>{p.price}</span>
                    <span className="text-muted-foreground text-sm">{p.per}</span>
                  </div>
                  {'desc' in p && (
                    <p className="text-[11px] text-muted-foreground/70 mb-5">{(p as { desc: string }).desc}</p>
                  )}
                  {!('desc' in p) && <div className="mb-5" />}

                  <ul className="space-y-2.5 text-sm text-foreground/80 mb-8 flex-grow">
                    {p.feats.map((f, j) => (
                      <li key={j} className="flex items-center gap-2.5">
                        <span className="w-4 h-4 rounded-full bg-mirror/10 border border-mirror/30 flex items-center justify-center flex-shrink-0">
                          <span className="w-1.5 h-1.5 bg-mirror rounded-full" />
                        </span>
                        {f}
                      </li>
                    ))}
                  </ul>

                  <button
                    onClick={() => handleCheckout(planKey)}
                    disabled={!!loading}
                    className={`w-full py-3 text-center font-bold rounded-xl transition-all flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed ${
                      popular
                        ? 'bg-primary text-primary-foreground hover:shadow-[0_0_20px_color-mix(in_oklab,var(--color-mirror)_40%,transparent)]'
                        : 'border border-white/20 hover:bg-white/5'
                    }`}
                  >
                    {isLoading
                      ? <><Loader2 className="w-4 h-4 animate-spin" />…</>
                      : popular ? t.pricing.featured : t.pricing.select
                    }
                  </button>
                </div>
              )
            })}
          </div>

          <p className="text-center mt-8 text-sm text-muted-foreground flex items-center justify-center gap-2">
            <Shield className="w-4 h-4 text-mirror" />
            {lang === 'zh'
              ? '7天无理由退款 · Stripe 安全支付 · 随时取消'
              : '7-day money-back guarantee · Secure payment via Stripe · Cancel anytime'}
          </p>
        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
