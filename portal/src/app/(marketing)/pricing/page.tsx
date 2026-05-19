'use client'

import { useState } from 'react'
import { Loader2, Shield } from 'lucide-react'
import { SiteNav } from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n } from '@/lib/i18n'

const PLAN_KEYS = ['monthly', 'yearly', 'biennial'] as const
type PlanKey = typeof PLAN_KEYS[number]

// Map plan → currency for checkout (USD by default, can be extended)
const PLAN_CURRENCY: Record<PlanKey, string> = {
  monthly:  'usd',
  yearly:   'usd',
  biennial: 'usd',
}

export default function PricingPage() {
  const { t } = useI18n()
  const [loading, setLoading] = useState<PlanKey | null>(null)
  const [error, setError]     = useState<string | null>(null)

  const handleCheckout = async (plan: PlanKey) => {
    setError(null)
    setLoading(plan)
    try {
      const res = await fetch('/api/billing/checkout', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ currency: PLAN_CURRENCY[plan] }),
      })
      const { url, error: apiErr } = await res.json()
      if (url) {
        window.location.href = url
      } else {
        // Not logged in → redirect to login
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

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {t.pricing.plans.map((p, i) => {
              const popular  = i === 1
              const planKey  = PLAN_KEYS[i]
              const isLoading = loading === planKey

              return (
                <div
                  key={i}
                  className={`glass-panel p-8 rounded-3xl flex flex-col relative ${
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
                  <div className="flex items-baseline gap-1 mb-1">
                    <span className={`text-5xl font-bold ${popular ? 'text-mirror' : ''}`}>{p.price}</span>
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
                      ? <><Loader2 className="w-4 h-4 animate-spin" />Redirecting…</>
                      : popular ? t.pricing.featured : t.pricing.select
                    }
                  </button>
                </div>
              )
            })}
          </div>

          <p className="text-center mt-8 text-sm text-muted-foreground flex items-center justify-center gap-2">
            <Shield className="w-4 h-4 text-mirror" />
            7-day money-back guarantee · Secure payment via Stripe · Cancel anytime
          </p>
        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
