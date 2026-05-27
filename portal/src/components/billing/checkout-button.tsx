'use client'

import { useState } from 'react'
import { CreditCard, RefreshCw } from 'lucide-react'
import { useI18n } from '@/lib/i18n'

export function CheckoutButton({ planKey }: { planKey: string }) {
  const { t } = useI18n()
  const [loading, setLoading] = useState(false)

  async function startCheckout() {
    setLoading(true)
    try {
      const res = await fetch('/api/billing/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan: planKey }),
      })
      const { url, error } = await res.json()
      if (url) {
        window.location.href = url
      } else {
        alert(error ?? t.dash.manage)
        setLoading(false)
      }
    } catch {
      setLoading(false)
    }
  }

  return (
    <button
      onClick={startCheckout}
      disabled={loading}
      className="btn-primary w-full flex items-center justify-center gap-2"
    >
      {loading
        ? <><RefreshCw className="h-4 w-4 animate-spin" /> {t.dash.manage}</>
        : <><CreditCard className="h-4 w-4" /> {t.pricing.featured}</>
      }
    </button>
  )
}
