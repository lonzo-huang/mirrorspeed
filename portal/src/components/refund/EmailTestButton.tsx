'use client'

import { useState } from 'react'

// 管理员邮件自检按钮：从已刷新会话的 /admin 页面发起 fetch，
// 直接展示 /api/admin/email-test 返回的 Brevo 真实结果。
export function EmailTestButton() {
  const [loading, setLoading] = useState(false)
  const [result, setResult]   = useState<string>('')

  async function run() {
    setLoading(true)
    setResult('')
    try {
      const res  = await fetch('/api/admin/email-test')
      const data = await res.json()
      setResult(JSON.stringify(data, null, 2))
    } catch (e: any) {
      setResult('请求失败：' + (e?.message ?? e))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="mb-6">
      <button
        onClick={run}
        disabled={loading}
        className="rounded-xl px-4 py-2 text-sm font-semibold glass hover:bg-white/5 transition-colors disabled:opacity-50"
      >
        {loading ? '发送中…' : '邮件自检'}
      </button>
      {result && (
        <pre className="mt-3 overflow-x-auto rounded-lg border border-app-subtle bg-black/40 p-4 text-xs text-app-secondary whitespace-pre-wrap">
{result}
        </pre>
      )}
    </div>
  )
}
