'use client'

import { useState } from 'react'
import { ExternalLink, RefreshCw } from 'lucide-react'

export function ManageButton({ label = '管理订阅 / 更换付款方式' }: { label?: string }) {
  const [loading, setLoading] = useState(false)

  async function openPortal() {
    setLoading(true)
    const res = await fetch('/api/billing/portal', { method: 'POST' })
    const { url, error } = await res.json()
    if (url) {
      window.location.href = url
    } else {
      alert(error ?? '跳转失败')
      setLoading(false)
    }
  }

  return (
    <button onClick={openPortal} disabled={loading} className="btn-secondary w-full">
      {loading
        ? <RefreshCw className="h-4 w-4 animate-spin" />
        : <ExternalLink className="h-4 w-4" />
      }
      {loading ? '跳转中...' : label}
    </button>
  )
}
