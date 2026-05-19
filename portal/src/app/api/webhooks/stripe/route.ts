import { createAdminClient } from '@/lib/supabase/server'
import { stripe } from '@/lib/stripe'
import { deleteVpnPeer } from '@/lib/vpn-api'
import { NextRequest, NextResponse } from 'next/server'
import type Stripe from 'stripe'

// Stripe Webhook 处理：订阅生命周期事件
// 需要在 Stripe Dashboard 注册此端点并获取 STRIPE_WEBHOOK_SECRET
export async function POST(req: NextRequest) {
  const body      = await req.text()
  const signature = req.headers.get('stripe-signature')!

  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(body, signature, process.env.STRIPE_WEBHOOK_SECRET!)
  } catch (err) {
    console.error('[webhook] Signature verification failed:', err)
    return NextResponse.json({ error: 'Invalid signature' }, { status: 400 })
  }

  const admin = createAdminClient()

  try {
    switch (event.type) {

      // ── 订阅激活（首次支付成功）──────────────────────────────────────────
      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription
        const userId   = sub.metadata?.supabase_user_id
        const currency = sub.metadata?.currency ?? 'usd'
        if (!userId) break

        const status = stripeStatusToLocal(sub.status)
        const expiresAt = new Date(sub.current_period_end * 1000).toISOString()

        // upsert 订阅记录
        const { data: existing } = await admin.from('subscriptions')
          .select('id').eq('stripe_subscription_id', sub.id).maybeSingle()

        if (existing) {
          await admin.from('subscriptions').update({
            status,
            expires_at:           expiresAt,
            cancel_at_period_end: sub.cancel_at_period_end,
            updated_at:           new Date().toISOString(),
          }).eq('id', existing.id)
        } else {
          // 查找套餐 ID
          const priceId = sub.items.data[0]?.price.id
          const { data: plan } = await admin.from('plans')
            .select('id').or(`stripe_price_usd.eq.${priceId},stripe_price_eur.eq.${priceId},stripe_price_cny.eq.${priceId}`)
            .single()

          await admin.from('subscriptions').insert({
            user_id:               userId,
            plan_id:               plan?.id,
            status,
            currency,
            started_at:            new Date(sub.start_date * 1000).toISOString(),
            expires_at:            expiresAt,
            stripe_subscription_id: sub.id,
            cancel_at_period_end:  sub.cancel_at_period_end,
          })
        }

        await admin.from('audit_log').insert({
          user_id: userId,
          action:  `subscription_${event.type.split('.')[2]}`,
          detail:  { stripe_sub_id: sub.id, status, currency },
        })
        break
      }

      // ── 订阅到期/取消 → 停用所有 VPN 设备 ───────────────────────────────
      case 'customer.subscription.deleted': {
        const sub    = event.data.object as Stripe.Subscription
        const userId = sub.metadata?.supabase_user_id
        if (!userId) break

        // 更新订阅状态
        await admin.from('subscriptions').update({ status: 'expired', updated_at: new Date().toISOString() })
          .eq('stripe_subscription_id', sub.id)

        // 拉取该用户所有活跃设备并逐一从 VPN 服务器删除
        const { data: devices } = await admin.from('vpn_devices')
          .select('id, peer_name').eq('user_id', userId).eq('is_active', true)

        for (const device of devices ?? []) {
          await deleteVpnPeer(device.peer_name).catch(e =>
            console.error(`[webhook] Failed to delete peer ${device.peer_name}:`, e)
          )
          await admin.from('vpn_devices').update({ is_active: false }).eq('id', device.id)
        }

        await admin.from('audit_log').insert({
          user_id: userId,
          action:  'subscription_expired',
          detail:  { stripe_sub_id: sub.id, devices_removed: devices?.length ?? 0 },
        })
        break
      }

      // ── 支付成功 → 写入支付记录 ──────────────────────────────────────────
      case 'invoice.payment_succeeded': {
        const invoice = event.data.object as Stripe.Invoice
        const subId   = typeof invoice.subscription === 'string' ? invoice.subscription : invoice.subscription?.id

        if (!subId) break

        const { data: sub } = await admin.from('subscriptions')
          .select('id, user_id, currency').eq('stripe_subscription_id', subId).single()

        if (!sub) break

        await admin.from('payments').insert({
          user_id:          sub.user_id,
          subscription_id:  sub.id,
          amount_cents:     invoice.amount_paid,
          currency:         sub.currency,
          status:           'succeeded',
          stripe_payment_id: invoice.payment_intent as string,
          stripe_invoice_id: invoice.id,
          description:      `VPN 月订阅 - ${new Date(invoice.period_start * 1000).toLocaleDateString()}`,
        })
        break
      }

      // ── 支付失败 ─────────────────────────────────────────────────────────
      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        const subId   = typeof invoice.subscription === 'string' ? invoice.subscription : invoice.subscription?.id
        if (!subId) break

        await admin.from('subscriptions').update({ status: 'past_due', updated_at: new Date().toISOString() })
          .eq('stripe_subscription_id', subId)
        break
      }

      default:
        // 忽略未处理的事件类型
        break
    }
  } catch (err) {
    console.error(`[webhook] Handler error for ${event.type}:`, err)
    return NextResponse.json({ error: 'Handler failed' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}

function stripeStatusToLocal(status: Stripe.Subscription.Status): string {
  const map: Record<string, string> = {
    active:             'active',
    past_due:           'past_due',
    canceled:           'cancelled',
    unpaid:             'past_due',
    trialing:           'active',
    incomplete:         'pending',
    incomplete_expired: 'expired',
    paused:             'cancelled',
  }
  return map[status] ?? 'pending'
}
