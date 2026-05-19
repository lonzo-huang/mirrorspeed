import { createServerSupabaseClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import { Monitor, CreditCard, CheckCircle, AlertCircle, Clock, ArrowRight } from 'lucide-react'
import { formatDistanceToNow, format } from 'date-fns'
import { zhCN } from 'date-fns/locale'
import { ServerStatus } from '@/components/dashboard/server-status'

export default async function DashboardPage() {
  const supabase = await createServerSupabaseClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // 并行拉取所需数据
  const [{ data: profile }, { data: subscription }, { data: devices }, { data: payments }] =
    await Promise.all([
      supabase.from('profiles').select('*').eq('id', user.id).single(),
      supabase.from('subscriptions').select('*, plan:plans(*)').eq('user_id', user.id)
        .in('status', ['active', 'past_due']).maybeSingle(),
      supabase.from('vpn_devices').select('*').eq('user_id', user.id).eq('is_active', true)
        .order('created_at', { ascending: false }),
      supabase.from('payments').select('*').eq('user_id', user.id)
        .order('created_at', { ascending: false }).limit(3),
    ])

  const plan = (subscription as any)?.plan
  const deviceCount = devices?.length ?? 0
  const isActive = subscription?.status === 'active'

  return (
    <div className="space-y-6">
      {/* 欢迎标题 */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          你好，{profile?.display_name ?? user.email?.split('@')[0]}
        </h1>
        <p className="mt-1 text-sm text-gray-500">以下是你的 VPN 服务概览</p>
      </div>

      {/* 无订阅引导横幅 */}
      {!subscription && (
        <div className="rounded-xl border border-brand-200 bg-brand-50 p-5 flex items-start gap-4">
          <AlertCircle className="h-5 w-5 text-brand-600 mt-0.5 shrink-0" />
          <div className="flex-1">
            <p className="font-medium text-brand-900">您尚未订阅 VPN 服务</p>
            <p className="mt-1 text-sm text-brand-700">订阅后即可添加设备并获取 Clash 订阅链接。</p>
          </div>
          <Link href="/dashboard/billing" className="btn-primary shrink-0 text-sm">
            立即订阅
          </Link>
        </div>
      )}

      {/* 状态卡片 */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {/* 订阅状态 */}
        <div className="card">
          <div className="flex items-center gap-3 mb-3">
            <div className="rounded-lg bg-brand-50 p-2">
              <CreditCard className="h-5 w-5 text-brand-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">订阅状态</span>
          </div>
          {subscription ? (
            <>
              <div className="flex items-center gap-2 mb-1">
                {isActive
                  ? <><CheckCircle className="h-4 w-4 text-green-500" /><span className="badge-active">有效</span></>
                  : <><Clock className="h-4 w-4 text-yellow-500" /><span className="badge-pending">待续费</span></>
                }
              </div>
              <p className="text-xs text-gray-500">
                {plan?.name}
                {subscription.expires_at && (
                  <> · 到期 {format(new Date(subscription.expires_at), 'yyyy/MM/dd')}</>
                )}
              </p>
            </>
          ) : (
            <p className="text-sm text-gray-400">未订阅</p>
          )}
        </div>

        {/* 设备数量 */}
        <div className="card">
          <div className="flex items-center gap-3 mb-3">
            <div className="rounded-lg bg-purple-50 p-2">
              <Monitor className="h-5 w-5 text-purple-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">已添加设备</span>
          </div>
          <p className="text-2xl font-bold text-gray-900">{deviceCount} <span className="text-base font-normal text-gray-400">/ 2</span></p>
          <p className="text-xs text-gray-500 mt-1">
            {deviceCount < 2 ? `还可添加 ${2 - deviceCount} 台设备` : '已达设备上限'}
          </p>
        </div>

        {/* 最近支付 */}
        <div className="card">
          <div className="flex items-center gap-3 mb-3">
            <div className="rounded-lg bg-green-50 p-2">
              <CheckCircle className="h-5 w-5 text-green-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">最近账单</span>
          </div>
          {payments && payments.length > 0 ? (
            <>
              <p className="text-xl font-bold text-gray-900">
                {CURRENCY_SYMBOL[payments[0].currency as keyof typeof CURRENCY_SYMBOL]}
                {(payments[0].amount_cents / 100).toFixed(2)}
              </p>
              <p className="text-xs text-gray-500 mt-1">
                {formatDistanceToNow(new Date(payments[0].created_at), { locale: zhCN, addSuffix: true })}
              </p>
            </>
          ) : (
            <p className="text-sm text-gray-400">暂无记录</p>
          )}
        </div>
      </div>

      {/* 服务器状态（客户端组件，自动轮询）*/}
      <ServerStatus />

      {/* 设备列表快览 */}
      {(devices && devices.length > 0) && (
        <div className="card">
          <div className="flex items-center justify-between mb-4">
            <h2 className="font-semibold text-gray-900">我的设备</h2>
            <Link href="/dashboard/devices" className="flex items-center gap-1 text-sm text-brand-600 hover:underline">
              管理 <ArrowRight className="h-3 w-3" />
            </Link>
          </div>
          <div className="space-y-3">
            {devices.map(device => (
              <div key={device.id} className="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
                <div className="flex items-center gap-3">
                  <Monitor className="h-4 w-4 text-gray-400" />
                  <div>
                    <p className="text-sm font-medium text-gray-900">{device.device_label}</p>
                    <p className="text-xs text-gray-400">{device.vpn_ip}</p>
                  </div>
                </div>
                <span className={device.is_active ? 'badge-active' : 'badge-expired'}>
                  {device.is_active ? '在线' : '已停用'}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

const CURRENCY_SYMBOL = { usd: '$', eur: '€', cny: '¥' }
