import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { stripe } from '@/lib/stripe'
import { createAdminClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'

// Plan key → subscription duration in days
const PLAN_DURATION: Record<string, number> = {
  monthly:   30,
  quarterly: 91,
  yearly:    365,
  biennial:  730,
}

export async function POST(req: NextRequest) {
  const body      = await req.text()
  const sig       = req.headers.get('stripe-signature') ?? ''
  const secret    = process.env.STRIPE_WEBHOOK_SECRET

  if (!secret) {
    console.error('STRIPE_WEBHOOK_SECRET not configured')
    return NextResponse.json({ error: 'webhook secret not configured' }, { status: 500 })
  }

  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(body, sig, secret)
  } catch (err: any) {
    console.error('Webhook signature verification failed:', err.message)
    return NextResponse.json({ error: `Webhook Error: ${err.message}` }, { status: 400 })
  }

  const admin = createAdminClient()

  try {
    switch (event.type) {
      // ── Checkout completed ──────────────────────────────────────
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        const userId  = session.metadata?.supabase_user_id
        const planKey = session.metadata?.plan

        if (!userId || !planKey) break

        const days    = PLAN_DURATION[planKey] ?? 30
        const now     = new Date()
        const expires = new Date(now.getTime() + days * 24 * 60 * 60 * 1000)

        // Upsert subscription (one record per user)
        const { error: upsertErr } = await (admin.from('subscriptions' as any) as any).upsert({
          user_id:                userId,
          stripe_subscription_id: session.subscription as string | null,
          status:                 'active',
          plan_key:               planKey,
          expires_at:             expires.toISOString(),
          cancel_at_period_end:   false,
          updated_at:             now.toISOString(),
        }, { onConflict: 'user_id' })

        if (upsertErr) console.error('[webhook] subscription upsert error:', upsertErr)

        break
      }

      // ── Subscription updated ────────────────────────────────────
      case 'customer.subscription.updated': {
        const sub    = event.data.object as Stripe.Subscription
        const userId = sub.metadata?.supabase_user_id
        if (!userId) break

        const status = sub.status === 'active'   ? 'active'
                     : sub.status === 'past_due'  ? 'past_due'
                     : sub.status === 'canceled'  ? 'cancelled'
                     : sub.status

        // current_period_end may be undefined in newer Stripe API versions
        const periodEndTs = (sub as any).current_period_end
        const periodEnd   = periodEndTs ? new Date(periodEndTs * 1000) : null

        const updatePayload: Record<string, any> = {
          status,
          cancel_at_period_end: sub.cancel_at_period_end,
          updated_at:           new Date().toISOString(),
        }
        if (periodEnd) updatePayload.expires_at = periodEnd.toISOString()

        const { error } = await (admin.from('subscriptions' as any) as any)
          .update(updatePayload).eq('user_id', userId)

        if (error) console.error('[webhook] subscription update error:', error)

        break
      }

      // ── Subscription cancelled/deleted ─────────────────────────
      case 'customer.subscription.deleted': {
        const sub    = event.data.object as Stripe.Subscription
        const userId = sub.metadata?.supabase_user_id
        if (!userId) break

        await (admin.from('subscriptions' as any) as any).update({
          status:     'cancelled',
          updated_at: new Date().toISOString(),
        }).eq('user_id', userId)

        break
      }

      // ── Invoice paid (renew) ────────────────────────────────────
      case 'invoice.payment_succeeded': {
        const invoice  = event.data.object as Stripe.Invoice
        const sub      = invoice.subscription as string | null
        const customerId = invoice.customer as string
        const amountPaid = invoice.amount_paid   // cents
        const currency   = invoice.currency

        if (!sub) break

        // Look up user by Stripe customer ID
        const { data: profile } = await (admin.from('profiles' as any) as any)
          .select('id').eq('stripe_customer_id', customerId).single()

        if (!profile?.id) break

        // Record payment
        await (admin.from('payments' as any) as any).insert({
          user_id:      profile.id,
          amount_cents: amountPaid,
          currency:     currency,
          status:       'succeeded',
          stripe_payment_intent_id: typeof invoice.payment_intent === 'string'
            ? invoice.payment_intent
            : (invoice.payment_intent as any)?.id ?? null,
          created_at:   new Date(invoice.created * 1000).toISOString(),
        })

        break
      }

      // ── Invoice payment failed ──────────────────────────────────
      case 'invoice.payment_failed': {
        const invoice    = event.data.object as Stripe.Invoice
        const customerId = invoice.customer as string

        const { data: profile } = await (admin.from('profiles' as any) as any)
          .select('id').eq('stripe_customer_id', customerId).single()

        if (!profile?.id) break

        await (admin.from('payments' as any) as any).insert({
          user_id:      profile.id,
          amount_cents: invoice.amount_due,
          currency:     invoice.currency,
          status:       'failed',
          created_at:   new Date(invoice.created * 1000).toISOString(),
        })

        break
      }

      // ── Alipay / WeChat Pay one-time payment succeeded ──────────
      case 'payment_intent.succeeded': {
        const pi      = event.data.object as Stripe.PaymentIntent
        const meta    = pi.metadata ?? {}
        const userId  = meta.supabase_user_id
        const planKey = meta.plan
        const payType = meta.payment_type

        // Only handle our CN one-time payments
        if (!userId || !planKey || payType !== 'cn_onetime') break

        const days    = PLAN_DURATION[planKey] ?? 30
        const now     = new Date()
        const expires = new Date(now.getTime() + days * 24 * 60 * 60 * 1000)

        // Activate subscription (no Stripe sub ID for one-time payments)
        await (admin.from('subscriptions' as any) as any).upsert({
          user_id:              userId,
          stripe_subscription_id: null,
          status:               'active',
          plan_key:             planKey,
          expires_at:           expires.toISOString(),
          cancel_at_period_end: false,
          updated_at:           now.toISOString(),
        }, { onConflict: 'user_id' })

        // Record payment
        const customerId = typeof pi.customer === 'string' ? pi.customer : null
        if (customerId) {
          const { data: profile } = await (admin.from('profiles' as any) as any)
            .select('id').eq('stripe_customer_id', customerId).single()

          if (profile?.id) {
            await (admin.from('payments' as any) as any).insert({
              user_id:      profile.id,
              amount_cents: pi.amount,
              currency:     pi.currency,
              status:       'succeeded',
              stripe_payment_intent_id: pi.id,
              created_at:   now.toISOString(),
            })
          }
        }

        break
      }

      default:
        // Unhandled event — ignore
        break
    }
  } catch (err: any) {
    console.error('Webhook handler error:', err)
    return NextResponse.json({ error: 'Handler error' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
