import { createAdminClient } from '@/lib/supabase/server'
import { stripe } from '@/lib/stripe'
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

        const status    = stripeStatusToLocal(sub.status)
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
          // 新订阅：查找套餐 ID
          const priceId = sub.items.data[0]?.price.id
          const { data: plan } = await admin.from('plans')
            .select('id, name').or(`stripe_price_usd.eq.${priceId},stripe_price_eur.eq.${priceId},stripe_price_cny.eq.${priceId}`)
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

          // ── 邀请奖励：仅首次订阅时触发 ─────────────────────────
          if (status === 'active') {
            await handleReferralReward(admin, userId, sub, plan?.name ?? null)
          }
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

        // 拉取该用户所有活跃设备
        const { data: devices } = await admin.from('vpn_devices')
          .select('id').eq('user_id', userId).eq('is_active', true)
        const deviceIds = (devices ?? []).map(d => d.id)

        // 拉取这些设备在各服务器上的 peer（含该服务器自己的 api_secret）
        const { data: peers } = deviceIds.length
          ? await admin.from('vpn_device_peers')
              .select('id, peer_name, server:vpn_servers(api_url, api_secret)')
              .in('device_id', deviceIds)
              .eq('is_active', true)
          : { data: [] as any[] }

        // 逐一从各自服务器删除 peer
        for (const peer of peers ?? []) {
          const apiUrl = (peer.server as any)?.api_url
          const secret = (peer.server as any)?.api_secret
          if (apiUrl && secret) {
            await fetch(`${apiUrl}/peers/${encodeURIComponent(peer.peer_name)}`, {
              method:  'DELETE',
              headers: { 'X-API-Secret': secret },
            }).catch(e => console.error(`[webhook] delete peer ${peer.peer_name} failed:`, e))
          }
          await admin.from('vpn_device_peers').update({ is_active: false }).eq('id', peer.id)
        }

        // 停用设备
        for (const id of deviceIds) {
          await admin.from('vpn_devices').update({ is_active: false }).eq('id', id)
        }

        await admin.from('audit_log').insert({
          user_id: userId,
          action:  'subscription_expired',
          detail:  { stripe_sub_id: sub.id, devices_removed: deviceIds.length },
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

// ── 邀请奖励：根据订阅时长计算奖励天数 ──────────────────────────────────────
// 规则：1个月→3天，1季度→10天，1年→30天，2年→60天
function getReferralBonusDays(interval: string, intervalCount: number): number {
  const months = interval === 'year' ? intervalCount * 12 : intervalCount
  if (months >= 24) return 60
  if (months >= 12) return 30
  if (months >= 3)  return 10
  return 3
}

// ── 处理邀请奖励（仅新订阅首次触发）────────────────────────────────────────
async function handleReferralReward(
  admin:    ReturnType<typeof createAdminClient>,
  inviteeUserId: string,
  sub:      Stripe.Subscription,
  planName: string | null,
) {
  try {
    // 1. 查找被邀请人的 referred_by
    const { data: inviteeProfile } = await admin
      .from('profiles')
      .select('id, referred_by')
      .eq('id', inviteeUserId)
      .single()

    if (!inviteeProfile?.referred_by) return  // 没有邀请人，跳过

    const referrerId  = inviteeProfile.referred_by

    // 2. 检查是否已经为此被邀请人发放过奖励（invitee_id UNIQUE 防止重复）
    const { data: existingReward } = await admin
      .from('referral_rewards')
      .select('id')
      .eq('invitee_id', inviteeUserId)
      .maybeSingle()

    if (existingReward) return  // 已奖励过，续费不重复发放

    // 3. 计算奖励天数
    const price         = sub.items.data[0]?.price
    const interval      = price?.recurring?.interval      ?? 'month'
    const intervalCount = price?.recurring?.interval_count ?? 1
    const bonusDays     = getReferralBonusDays(interval, intervalCount)

    // 4. 写入 referral_rewards 记录
    await admin.from('referral_rewards').insert({
      referrer_id: referrerId,
      invitee_id:  inviteeUserId,
      plan_name:   planName,
      bonus_days:  bonusDays,
    })

    // 5. 延长邀请人的奖励到期时间
    //    - 如果已有 referral_bonus_expires_at 且未到期：在此基础上叠加
    //    - 如果已到期或没有：从当天开始计算
    const { data: referrerProfile } = await admin
      .from('profiles')
      .select('referral_bonus_expires_at')
      .eq('id', referrerId)
      .single()

    const now         = new Date()
    const currentExpiry = referrerProfile?.referral_bonus_expires_at
      ? new Date(referrerProfile.referral_bonus_expires_at)
      : null
    const baseDate    = currentExpiry && currentExpiry > now ? currentExpiry : now
    const newExpiry   = new Date(baseDate.getTime() + bonusDays * 86_400_000)

    await admin
      .from('profiles')
      .update({ referral_bonus_expires_at: newExpiry.toISOString() })
      .eq('id', referrerId)

    // 6. 写入审计日志
    await admin.from('audit_log').insert({
      user_id: referrerId,
      action:  'referral_reward_granted',
      detail:  {
        invitee_id:   inviteeUserId,
        plan_name:    planName,
        bonus_days:   bonusDays,
        new_expiry:   newExpiry.toISOString(),
      },
    })

    console.log(
      `[referral] Granted ${bonusDays} days to referrer ${referrerId} ` +
      `(invited by ${inviteeUserId}, plan: ${planName})`
    )
  } catch (err) {
    // 奖励失败不影响主流程
    console.error('[referral] Reward processing failed:', err)
  }
}
