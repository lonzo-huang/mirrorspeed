'use client'

import { CheckCircle, CreditCard, Clock } from 'lucide-react'
import { format } from 'date-fns'
import { CheckoutButton } from '@/components/billing/checkout-button'
import { CnCheckoutButton } from '@/components/billing/cn-checkout-button'
import { ManageButton } from '@/components/billing/manage-button'
import { useI18n } from '@/lib/i18n'

const PLAN_KEYS = ['yearly', 'biennial', 'monthly', 'quarterly'] as const
type PlanKey = typeof PLAN_KEYS[number]

interface Subscription {
  status: string
  expires_at?: string | null
  cancel_at_period_end?: boolean | null
}

interface Payment {
  id: string
  amount_cents: number
  currency: string
  status: string
  created_at: string
}

interface Props {
  subscription: Subscription | null
  payments: Payment[]
}

const CURRENCY_SYMBOL: Record<string, string> = { usd: '$', eur: '€', cny: '¥' }

export function BillingView({ subscription, payments }: Props) {
  const { t, lang } = useI18n()
  // Show CNY payment options when the app is in Chinese
  const isChinese   = lang === 'zh'
  const pricing = t.pricing
  const dash    = t.dash

  const isActive  = subscription?.status === 'active'
  const isPastDue = subscription?.status === 'past_due'

  // Map plan index → planKey
  const planKeys: PlanKey[] = ['yearly', 'biennial', 'monthly', 'quarterly']

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">{dash.billingNav}</h1>
        <p className="mt-1 text-sm text-muted-foreground">{dash.manage}</p>
      </div>

      {/* Current subscription status */}
      {(isActive || isPastDue) && (
        <div className="glass-panel rounded-2xl p-6">
          <h2 className="font-semibold text-foreground mb-4">{dash.plan}</h2>
          {isActive ? (
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <CheckCircle className="h-5 w-5 text-green-400" />
                <span className="badge-active">{dash.statusActive}</span>
              </div>
              {subscription?.expires_at && (
                <p className="text-sm text-muted-foreground">
                  {dash.expires}: {format(new Date(subscription.expires_at), 'yyyy-MM-dd')}
                </p>
              )}
              <ManageButton />
            </div>
          ) : (
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <Clock className="h-5 w-5 text-yellow-400" />
                <span className="badge-pending">{dash.statusPastDue}</span>
              </div>
              <ManageButton />
            </div>
          )}
        </div>
      )}

      {/* Plan selection (only shown when no active subscription) */}
      {!isActive && !isPastDue && (
        <div>
          <h2 className="text-xl font-bold text-foreground mb-2">{pricing.title}</h2>
          <p className="text-sm text-muted-foreground mb-6">{pricing.sub}</p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {pricing.plans.map((plan, i) => {
              const key = planKeys[i]
              const isPopular = i === 0
              return (
                <div
                  key={key}
                  className={`glass-panel rounded-2xl p-6 flex flex-col gap-4
                    ${isPopular ? 'border-mirror/50 ring-1 ring-mirror/30' : ''}`}
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="font-bold text-foreground text-lg">{plan.name}</p>
                      <p className="text-xs text-muted-foreground mt-1">{plan.desc}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-2xl font-bold text-mirror">{plan.price}</p>
                      <p className="text-xs text-muted-foreground">{plan.per}</p>
                    </div>
                  </div>
                  {isPopular && (
                    <span className="self-start text-[9px] font-bold uppercase tracking-widest text-mirror bg-mirror/10 border border-mirror/20 px-2 py-0.5 rounded-full">
                      {pricing.popular}
                    </span>
                  )}
                  <ul className="space-y-1.5 flex-1">
                    {plan.feats.map(f => (
                      <li key={f} className="flex items-center gap-2 text-sm text-foreground/80">
                        <CheckCircle className="h-3.5 w-3.5 text-mirror shrink-0" />
                        {f}
                      </li>
                    ))}
                  </ul>
                  <CheckoutButton planKey={key} />
                  {isChinese && <CnCheckoutButton planKey={key} />}
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* Payment history */}
      <div className="glass-panel rounded-2xl p-6">
        <h2 className="font-semibold text-foreground mb-4">{dash.billing}</h2>
        {payments.length > 0 ? (
          <div className="space-y-2">
            {payments.map(p => (
              <div key={p.id} className="flex items-center justify-between py-2.5 border-b border-border last:border-0">
                <div>
                  <p className="text-sm font-medium text-foreground">
                    {CURRENCY_SYMBOL[p.currency] ?? '$'}
                    {(p.amount_cents / 100).toFixed(2)}
                    <span className="ml-1 text-xs font-normal text-muted-foreground uppercase">{p.currency}</span>
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {format(new Date(p.created_at), 'yyyy-MM-dd HH:mm')}
                  </p>
                </div>
                <span className={
                  p.status === 'succeeded' ? 'badge-active'
                  : p.status === 'failed'   ? 'badge-expired'
                  : 'badge-pending'
                }>
                  {p.status === 'succeeded' ? '✓'
                   : p.status === 'failed'   ? '✗'
                   : p.status === 'refunded' ? '↩'
                   : '…'}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center py-10 text-muted-foreground">
            <CreditCard className="h-8 w-8 mb-2 opacity-30" />
            <p className="text-sm">{dash.noPayments}</p>
          </div>
        )}
      </div>
    </div>
  )
}
