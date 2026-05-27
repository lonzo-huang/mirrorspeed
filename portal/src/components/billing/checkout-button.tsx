'use client'

import { useState } from 'react'
import { CreditCard, RefreshCw } from 'lucide-react'
import { useI18n } from '@/lib/i18n'

export function CheckoutButton({ planKey }: { planKey: string }) {
  const { t } = useI18n()
  const [loading, setLoading] = useState(false)

  const [errMsg, setErrMsg] = useState<string | null>(null)

  async function startCheckout() {
    setLoading(true)
    setErrMsg(null)
    try {
      const res = await fetch('/api/billing/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan: planKey }),
      })
      const data = await res.json()
      if (data.url) {
        window.location.href = data.url
      } else {
        setErrMsg(data.error ?? 'Unknown error')
        setLoading(false)
      }
    } catch (e: any) {
      setErrMsg(e?.message ?? 'Network error')
      setLoading(false)
    }
  }

  return (
    <div className="space-y-2">
      <button
        onClick={startCheckout}
        disabled={loading}
        className="btn-primary w-full flex items-center justify-center gap-2"
      >
        {loading
          ? <><RefreshCw className="h-4 w-4 animate-spin" /> Redirecting...</>
          : <><CreditCard className="h-4 w-4" /> {t.pricing.featured}</>
        }
      </button>
      {errMsg && (
        <p className="text-xs text-red-400 text-center">{errMsg}</p>
      )}
    </div>
  )
}
