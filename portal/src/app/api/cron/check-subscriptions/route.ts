import { NextRequest, NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/server'
import { sendEmail, makeExpiryWarningEmail, makeExpiredEmail } from '@/lib/email'

export const dynamic = 'force-dynamic'

// Vercel Cron — runs daily at 02:00 UTC (see vercel.json)
// 1. Find subscriptions expiring in 6-8 days → send warning email once
// 2. Find subscriptions past expires_at and still 'active' → mark 'expired' + send email

export async function GET(req: NextRequest) {
  // Protect against unauthorized calls
  const authHeader = req.headers.get('authorization')
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const admin = createAdminClient()
  const now   = new Date()

  let warned  = 0
  let expired = 0
  const errors: string[] = []

  try {
    // ── 1. Expiry warning: expires in 6-8 days, not yet warned ──────────────
    const warnFrom = new Date(now.getTime() + 6  * 24 * 60 * 60 * 1000)
    const warnTo   = new Date(now.getTime() + 8  * 24 * 60 * 60 * 1000)

    const { data: toWarn } = await (admin.from('subscriptions' as any) as any)
      .select('id, user_id, plan_key, expires_at, notified_expiry')
      .eq('status', 'active')
      .gte('expires_at', warnFrom.toISOString())
      .lte('expires_at', warnTo.toISOString())
      .neq('notified_expiry', true)

    for (const sub of (toWarn ?? [])) {
      try {
        // Get user email + lang preference
        const { data: profile } = await (admin.from('profiles' as any) as any)
          .select('email, display_name, lang').eq('id', sub.user_id).single()

        if (!profile?.email) continue

        const displayName = profile.display_name ?? profile.email.split('@')[0]
        const lang        = profile.lang ?? 'en'
        const expiresAt   = new Date(sub.expires_at)

        const { subject, html } = makeExpiryWarningEmail({
          displayName,
          expiresAt,
          planKey: sub.plan_key,
          lang,
        })

        await sendEmail({ to: profile.email, subject, html })

        // Mark as warned so we don't re-send
        await (admin.from('subscriptions' as any) as any)
          .update({ notified_expiry: true })
          .eq('id', sub.id)

        warned++
      } catch (e: any) {
        errors.push(`warn user=${sub.user_id}: ${e?.message}`)
      }
    }

    // ── 2. Expire: active subscriptions past expires_at ─────────────────────
    const { data: toExpire } = await (admin.from('subscriptions' as any) as any)
      .select('id, user_id, plan_key')
      .eq('status', 'active')
      .lt('expires_at', now.toISOString())

    for (const sub of (toExpire ?? [])) {
      try {
        // Mark expired
        await (admin.from('subscriptions' as any) as any)
          .update({
            status:     'expired',
            updated_at: now.toISOString(),
          })
          .eq('id', sub.id)

        // Also reset any VPN device configs (optional: deactivate devices)
        await (admin.from('vpn_devices' as any) as any)
          .update({ is_active: false })
          .eq('user_id', sub.user_id)
          .eq('is_active', true)

        // Send expiry email
        const { data: profile } = await (admin.from('profiles' as any) as any)
          .select('email, display_name, lang').eq('id', sub.user_id).single()

        if (profile?.email) {
          const displayName = profile.display_name ?? profile.email.split('@')[0]
          const lang        = profile.lang ?? 'en'

          const { subject, html } = makeExpiredEmail({
            displayName,
            planKey: sub.plan_key,
            lang,
          })

          await sendEmail({ to: profile.email, subject, html })
        }

        expired++
      } catch (e: any) {
        errors.push(`expire user=${sub.user_id}: ${e?.message}`)
      }
    }

  } catch (err: any) {
    console.error('[check-subscriptions] fatal:', err)
    return NextResponse.json({ error: err?.message }, { status: 500 })
  }

  console.log(`[check-subscriptions] warned=${warned} expired=${expired} errors=${errors.length}`)
  return NextResponse.json({ ok: true, warned, expired, errors })
}
