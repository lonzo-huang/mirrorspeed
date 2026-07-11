import { redirect } from 'next/navigation'
import Link from 'next/link'
import { getUser, createAdminClient } from '@/lib/supabase/server'
import { ForceDarkTheme } from '@/components/ForceDarkTheme'
import { EmailTestButton } from '@/components/refund/EmailTestButton'

export const dynamic = 'force-dynamic'

interface RefundRow {
  id: string
  email: string
  reason_label: string | null
  reason_code: string
  detail: string | null
  device_type: string | null
  screenshot_url: string | null
  plan: string | null
  status: string
  created_at: string
}

export default async function AdminRefundsPage() {
  const user = await getUser()
  if (!user) redirect('/login')
  const admin = createAdminClient()
  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if ((profile as any)?.role !== 'admin') redirect('/dashboard')

  const { data } = await (admin.from('refund_requests') as any)
    .select('id, email, reason_label, reason_code, detail, device_type, screenshot_url, plan, status, created_at')
    .order('created_at', { ascending: false })
    .limit(200)
  const rows = (data ?? []) as RefundRow[]

  return (
    <>
      <ForceDarkTheme />
      <div data-theme="dark" className="min-h-screen bg-app text-app-primary">
        <div className="mx-auto max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h1 className="text-2xl font-bold">退款申请</h1>
              <p className="text-sm text-app-secondary mt-1">共 {rows.length} 条 · 最新在前</p>
            </div>
            <Link href="/admin" className="text-sm text-mirror hover:underline">← 返回管理后台</Link>
          </div>

          <EmailTestButton />

          {rows.length === 0 ? (
            <div className="glass-panel rounded-2xl p-10 text-center text-app-secondary">暂无退款申请</div>
          ) : (
            <div className="space-y-3">
              {rows.map(r => (
                <div key={r.id} className="glass-panel rounded-2xl p-5">
                  <div className="flex flex-wrap items-center justify-between gap-2 mb-2">
                    <div className="flex items-center gap-3">
                      <span className="font-medium text-app-primary">{r.email}</span>
                      <span className="text-xs px-2 py-0.5 rounded-full bg-mirror/10 text-mirror border border-mirror/20">
                        {r.reason_label ?? r.reason_code}
                      </span>
                      {r.plan && <span className="text-xs text-app-secondary">套餐：{r.plan}</span>}
                      {r.device_type && <span className="text-xs text-app-secondary">终端：{r.device_type}</span>}
                    </div>
                    <div className="flex items-center gap-3">
                      <span className={`text-xs px-2 py-0.5 rounded-full border ${
                        r.status === 'pending' ? 'text-yellow-400 border-yellow-500/30 bg-yellow-500/10'
                        : r.status === 'refunded' ? 'text-green-400 border-green-500/30 bg-green-500/10'
                        : 'text-app-secondary border-app-subtle'
                      }`}>{r.status}</span>
                      <span className="text-xs text-app-muted">
                        {new Date(r.created_at).toLocaleString('zh-CN')}
                      </span>
                    </div>
                  </div>
                  {r.detail && (
                    <p className="text-sm text-app-secondary whitespace-pre-wrap mb-2">{r.detail}</p>
                  )}
                  {r.screenshot_url && (
                    <a href={r.screenshot_url} target="_blank" rel="noopener noreferrer"
                       className="text-sm text-mirror hover:underline">查看截图 ↗</a>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </>
  )
}
