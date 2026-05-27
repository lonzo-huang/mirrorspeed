'use client'

import { useState } from 'react'
import { ExternalLink, RefreshCw } from 'lucide-react'
import { useI18n } from '@/lib/i18n'

export function ManageButton() {
  const { t } = useI18n()
  const [loading, setLoading] = useState(false)

  async function openPortal() {
    setLoading(true)
    const res = await fetch('/api/billing/portal', { method: 'POST' })
    const { url, error } = await res.json()
    if (url) {
      window.location.href = url
    } else {
      alert(error ?? t.dash.manage)
      setLoading(false)
    }
  }

  return (
    <button onClick={openPortal} disabled={loading} className="btn-secondary w-full flex items-center justify-center gap-2">
      {loading
        ? <RefreshCw className="h-4 w-4 animate-spin" />
        : <ExternalLink className="h-4 w-4" />
      }
      {loading ? '...' : t.dash.renew}
    </button>
  )
}
