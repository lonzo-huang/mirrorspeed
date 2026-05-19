import { createServerSupabaseClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { CheckCircle, CreditCard, Clock, ExternalLink } from 'lucide-react'
import { format } from 'date-fns'
import { CheckoutButton } from '@/components/billing/checkout-button'
import { ManageButton } from '@/components/billing/manage-button'

const CURRENCY_LABEL = { usd: 'USD $', eur: 'EUR €', cny: 'CNY ¥' }
const CURRENCY_SYMBOL = { usd: '$', eur: '€', cny: '¥' }

export default async function BillingPage() {
  const supabase = await createServerSupabaseClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: profile }, { data: plan }, { data: subscription }, { data: payments }] =
    await Promise.all([
      supabase.from('profiles').select('*').eq('id', user.id).single(),
      supabase.from('plans').select('*').eq('is_active', true).single(),
      supabase.from('subscriptions').select('*').eq('user_id', user.id)
        .in('status', ['active', 'past_due', 'cancelled']).order('created_at', { ascending: false }).maybeSingle(),
      supabase.from('payments').select('*').eq('user_id', user.id)
        .order('created_at', { ascending: false }).limit(10),
    ])

  const currency = (profile?.preferred_currency ?? 'usd') as keyof typeof CURRENCY_LABEL
  const isActive = subscription?.status === 'active'
  const isPastDue = subscription?.status === 'past_due'

  // 根据货币显示价格
  const priceMap = {
    usd: plan ? plan.price_usd_cents / 100 : 0,
    eur: plan ? plan.price_eur_cents / 100 : 0,
    cny: plan ? plan.price_cny_fen  / 100 : 0,
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">订阅与账单</h1>
        <p className="mt-1 text-sm text-gray-500">管理你的 VPN 订阅套餐和查看支付记录</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        {/* 当前套餐卡片 */}
        <div className="card">
          <h2 className="font-semibold text-gray-900 mb-4">当前套餐</h2>

          {isActive ? (
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <CheckCircle className="h-5 w-5 text-green-500" />
                <span className="font-medium text-green-700">订阅有效</span>
              </div>
              <div className="rounded-lg bg-gray-50 p-4 space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">套餐</span>
                  <span className="font-medium">{plan?.name}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">计费</span>
                  <span className="font-medium">
                    {CURRENCY_SYMBOL[currency]}{priceMap[currency].toFixed(2)} / 月
                  </span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">到期时间</span>
                  <span className="font-medium">
                    {subscription?.expires_at
                      ? format(new Date(subscription.expires_at), 'yyyy 年 MM 月 dd 日')
                      : '—'}
                  </span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">自动续费</span>
                  <span className={subscription?.cancel_at_period_end ? 'text-red-600' : 'text-green-600'}>
                    {subscription?.cancel_at_period_end ? '已关闭（到期停止）' : '已开启'}
                  </span>
                </div>
              </div>
              {/* 跳转 Stripe Customer Portal 管理订阅 */}
              <ManageButton />
            </div>
          ) : isPastDue ? (
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <Clock className="h-5 w-5 text-yellow-500" />
                <span className="font-medium text-yellow-700">账单逾期，请更新付款方式</span>
              </div>
              <ManageButton label="更新付款方式" />
            </div>
          ) : (
            /* 未订阅 — 显示套餐卡 */
            plan && (
              <div className="space-y-4">
                <div className="rounded-xl border-2 border-brand-500 bg-brand-50 p-5">
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="font-bold text-brand-900 text-lg">{plan.name}</p>
                      <p className="text-sm text-brand-700 mt-1">{plan.description}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-2xl font-bold text-brand-900">
                        {CURRENCY_SYMBOL[currency]}{priceMap[currency].toFixed(2)}
                      </p>
                      <p className="text-xs text-brand-600">/ 月</p>
                    </div>
                  </div>
                  <ul className="mt-4 space-y-2">
                    {[
                      '最多 2 台设备同时在线',
                      '香港/新加坡 CN2 优质线路',
                      'WireGuard 内核级加密隧道',
                      'Clash 订阅自动更新',
                      '企业支付记录（虚拟结算）',
                    ].map(f => (
                      <li key={f} className="flex items-center gap-2 text-sm text-brand-800">
                        <CheckCircle className="h-4 w-4 text-brand-500 shrink-0" />
                        {f}
                      </li>
                    ))}
                  </ul>
                </div>

                {/* 货币选择 + 结账按钮 */}
                <CheckoutButton planId={plan.id} currency={currency} />
              </div>
            )
          )}
        </div>

        {/* 支付记录 */}
        <div className="card">
          <h2 className="font-semibold text-gray-900 mb-4">支付记录</h2>
          {payments && payments.length > 0 ? (
            <div className="space-y-2">
              {payments.map(p => (
                <div key={p.id} className="flex items-center justify-between py-2.5 border-b border-gray-100 last:border-0">
                  <div>
                    <p className="text-sm font-medium text-gray-900">
                      {CURRENCY_SYMBOL[p.currency as keyof typeof CURRENCY_SYMBOL]}
                      {(p.amount_cents / 100).toFixed(2)}
                      <span className="ml-1 text-xs font-normal text-gray-400 uppercase">{p.currency}</span>
                    </p>
                    <p className="text-xs text-gray-400">
                      {format(new Date(p.created_at), 'yyyy-MM-dd HH:mm')}
                    </p>
                  </div>
                  <span className={
                    p.status === 'succeeded' ? 'badge-active'
                    : p.status === 'failed'   ? 'badge-expired'
                    : 'badge-pending'
                  }>
                    {p.status === 'succeeded' ? '已完成'
                     : p.status === 'failed' ? '失败'
                     : p.status === 'refunded' ? '已退款' : '处理中'}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-10 text-gray-400">
              <CreditCard className="h-8 w-8 mb-2 opacity-30" />
              <p className="text-sm">暂无支付记录</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
