'use client'

import { useState } from 'react'
import { CreditCard, RefreshCw } from 'lucide-react'

const CURRENCY_OPTIONS = [
  { value: 'usd', label: 'USD 美元' },
  { value: 'eur', label: 'EUR 欧元' },
  { value: 'cny', label: 'CNY 人民币' },
]

export function CheckoutButton({ planId, currency: defaultCurrency }: {
  planId: string
  currency: string
}) {
  const [currency, setCurrency] = useState(defaultCurrency)
  const [loading, setLoading]   = useState(false)

  async function startCheckout() {
    setLoading(true)
    const res = await fetch('/api/billing/checkout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ planId, currency }),
    })
    const { url, error } = await res.json()
    if (url) {
      window.location.href = url
    } else {
      alert(error ?? '跳转失败，请重试')
      setLoading(false)
    }
  }

  return (
    <div className="space-y-3">
      {/* 货币选择 */}
      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">结算货币</label>
        <select
          value={currency}
          onChange={e => setCurrency(e.target.value)}
          className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm bg-white
                     focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
        >
          {CURRENCY_OPTIONS.map(o => (
            <option key={o.value} value={o.value}>{o.label}</option>
          ))}
        </select>
      </div>

      <button
        onClick={startCheckout}
        disabled={loading}
        className="btn-primary w-full"
      >
        {loading
          ? <><RefreshCw className="h-4 w-4 animate-spin" /> 跳转至支付页面...</>
          : <><CreditCard className="h-4 w-4" /> 立即订阅</>
        }
      </button>

      <p className="text-xs text-gray-400 text-center">
        通过 Stripe 安全支付 · 随时可取消订阅
      </p>
    </div>
  )
}
