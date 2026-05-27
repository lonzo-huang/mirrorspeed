'use client'

import Link from 'next/link'
import { Monitor, CreditCard, CheckCircle, AlertCircle, Clock, ArrowRight } from 'lucide-react'
import { formatDistanceToNow, format } from 'date-fns'
import { ServerStatus } from '@/components/dashboard/server-status'
import { useI18n } from '@/lib/i18n'

interface Profile {
  display_name?: string | null
}

interface Plan {
  name?: string | null
}

interface Subscription {
  status: string
  expires_at?: string | null
  plan?: Plan | null
}

interface Device {
  id: string
  device_label: string
  vpn_ip: string
  is_active: boolean
}

interface Payment {
  id: string
  amount_cents: number
  currency: string
  created_at: string
}

interface Props {
  userEmail: string
  displayName: string
  profile: Profile | null
  subscription: Subscription | null
  devices: Device[]
  payments: Payment[]
  isAdmin: boolean
}

const CURRENCY_SYMBOL: Record<string, string> = { usd: '$', eur: '€', cny: '¥' }

const RECOMMENDED_NODES = [
  { id: 'HK', location: 'Hong Kong', locationZh: '香港', latency: 14 },
  { id: 'SG', location: 'Singapore', locationZh: '新加坡', latency: 32 },
  { id: 'JP', location: 'Japan', locationZh: '日本', latency: 28 },
  { id: 'US', location: 'United States', locationZh: '美国', latency: 118 },
]

export function DashboardView({ userEmail, displayName, profile, subscription, devices, payments, isAdmin }: Props) {
  const { t, lang } = useI18n()
  const d = t.dash
  const deviceCount = devices.length
  const isActive = subscription?.status === 'active'
  const plan = subscription?.plan

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">
          {d.greeting}，{displayName}
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">{d.vpnOverview}</p>
      </div>

      {!subscription && (
        <div className="glass-panel rounded-xl p-5 flex items-start gap-4 border-mirror/20">
          <AlertCircle className="h-5 w-5 text-mirror mt-0.5 shrink-0" />
          <div className="flex-1">
            <p className="font-medium text-foreground">{d.noSub}</p>
            <p className="mt-1 text-sm text-muted-foreground">{d.noSubDesc}</p>
          </div>
          <Link href="/dashboard/billing" className="btn-primary shrink-0 text-sm">
            {d.subscribe}
          </Link>
        </div>
      )}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {/* Subscription status */}
        <div className="glass-panel rounded-2xl p-4">
          <div className="flex items-center gap-3 mb-3">
            <div className="rounded-lg bg-mirror/10 p-2">
              <CreditCard className="h-5 w-5 text-mirror" />
            </div>
            <span className="text-sm font-medium text-muted-foreground">{d.subStatus}</span>
          </div>
          {subscription ? (
            <>
              <div className="flex items-center gap-2 mb-1">
                {isActive
                  ? <><CheckCircle className="h-4 w-4 text-green-400" /><span className="badge-active">{d.statusActive}</span></>
                  : <><Clock className="h-4 w-4 text-yellow-400" /><span className="badge-pending">{d.statusPastDue}</span></>
                }
              </div>
              <p className="text-xs text-muted-foreground">
                {plan?.name}
                {subscription.expires_at && (
                  <> · {format(new Date(subscription.expires_at), 'yyyy/MM/dd')}</>
                )}
              </p>
            </>
          ) : (
            <p className="text-sm text-muted-foreground">{d.notSubscribed}</p>
          )}
        </div>

        {/* Devices */}
        <div className="glass-panel rounded-2xl p-4">
          <div className="flex items-center gap-3 mb-3">
            <div className="rounded-lg bg-purple-500/10 p-2">
              <Monitor className="h-5 w-5 text-purple-400" />
            </div>
            <span className="text-sm font-medium text-muted-foreground">{d.devicesLabel}</span>
          </div>
          <p className="text-2xl font-bold text-foreground">
            {deviceCount} <span className="text-base font-normal text-muted-foreground">/ 2</span>
          </p>
          <p className="text-xs text-muted-foreground mt-1">
            {deviceCount < 2
              ? `${2 - deviceCount} ${d.devSlotsLeft}`
              : d.devLimitReached}
          </p>
        </div>

        {/* Recent payment */}
        <div className="glass-panel rounded-2xl p-4">
          <div className="flex items-center gap-3 mb-3">
            <div className="rounded-lg bg-green-500/10 p-2">
              <CheckCircle className="h-5 w-5 text-green-400" />
            </div>
            <span className="text-sm font-medium text-muted-foreground">{d.recentPayment}</span>
          </div>
          {payments.length > 0 ? (
            <>
              <p className="text-xl font-bold text-foreground">
                {CURRENCY_SYMBOL[payments[0].currency] ?? '$'}
                {(payments[0].amount_cents / 100).toFixed(2)}
              </p>
              <p className="text-xs text-muted-foreground mt-1">
                {formatDistanceToNow(new Date(payments[0].created_at), { addSuffix: true })}
              </p>
            </>
          ) : (
            <p className="text-sm text-muted-foreground">{d.noPayments}</p>
          )}
        </div>
      </div>

      {/* Recommended Nodes */}
      <div className="glass-panel rounded-2xl p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold text-foreground">{d.recNodes}</h2>
          <Link href="/servers" className="flex items-center gap-1 text-sm text-mirror hover:underline">
            {d.viewAll} <ArrowRight className="h-3 w-3" />
          </Link>
        </div>
        <div className="grid grid-cols-2 gap-3">
          {RECOMMENDED_NODES.map(node => (
            <div key={node.id} className="flex items-center justify-between rounded-xl bg-white/5 border border-white/5 px-4 py-3">
              <div>
                <p className="text-sm font-medium text-foreground">{node.id}</p>
                <p className="text-xs text-muted-foreground">{lang === 'zh' ? node.locationZh : node.location}</p>
              </div>
              <div className="text-right">
                <p className="text-sm font-bold text-mirror">{node.latency}ms</p>
                <p className="text-xs text-green-400">{d.nodeOnline}</p>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Admin-only server status */}
      <ServerStatus isAdmin={isAdmin} />

      {/* My Devices */}
      {devices.length > 0 && (
        <div className="glass-panel rounded-2xl p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="font-semibold text-foreground">{d.myDevices}</h2>
            <Link href="/dashboard/devices" className="flex items-center gap-1 text-sm text-mirror hover:underline">
              {d.manage} <ArrowRight className="h-3 w-3" />
            </Link>
          </div>
          <div className="space-y-3">
            {devices.map(device => (
              <div key={device.id} className="flex items-center justify-between py-2 border-b border-border last:border-0">
                <div className="flex items-center gap-3">
                  <Monitor className="h-4 w-4 text-muted-foreground" />
                  <div>
                    <p className="text-sm font-medium text-foreground">{device.device_label}</p>
                    <p className="text-xs text-muted-foreground">{device.vpn_ip}</p>
                  </div>
                </div>
                <span className={device.is_active ? 'badge-active' : 'badge-expired'}>
                  {device.is_active ? d.nodeOnline : d.notSubscribed}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
