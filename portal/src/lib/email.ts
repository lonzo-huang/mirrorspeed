/**
 * Email utility via Resend API.
 * Requires RESEND_API_KEY in environment variables.
 * Sign up at https://resend.com and add a verified sending domain.
 */

interface SendEmailOptions {
  to:      string
  subject: string
  html:    string
}

export async function sendEmail({ to, subject, html }: SendEmailOptions): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY
  if (!apiKey) {
    console.warn('[email] RESEND_API_KEY not configured, skipping email to', to)
    return
  }

  const from = process.env.EMAIL_FROM ?? 'MirrorSpeed <noreply@mirrorspeed.io>'

  const res = await fetch('https://api.resend.com/emails', {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({ from, to, subject, html }),
  })

  if (!res.ok) {
    const text = await res.text().catch(() => '')
    console.error('[email] Resend error:', res.status, text)
  }
}

// ── Email templates ────────────────────────────────────────────────────────

export function makeExpiryWarningEmail(opts: {
  displayName: string
  expiresAt:   Date
  planKey:     string
  lang:        string
}): { subject: string; html: string } {
  const { displayName, expiresAt, planKey, lang } = opts
  const days     = Math.ceil((expiresAt.getTime() - Date.now()) / (1000 * 60 * 60 * 24))
  const dateStr  = expiresAt.toISOString().split('T')[0]
  const isChinese = lang === 'zh'

  if (isChinese) {
    return {
      subject: '【镜速加速器】您的订阅即将于 7 天后到期',
      html: `
<!DOCTYPE html><html lang="zh"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 8px">镜速加速器</h1>
  <p style="color:#aaa;margin:0 0 24px;font-size:14px">MirrorSpeed</p>
  <p>您好 ${displayName}，</p>
  <p>您的 <strong style="color:#a78bfa">${planKey}</strong> 套餐将于 <strong>${dateStr}</strong>（约 ${days} 天后）到期。</p>
  <p>到期后您将自动退回到免费用户模式，请及时续费以保持服务不中断。</p>
  <div style="margin:24px 0;text-align:center">
    <a href="https://mirrorspeed.io/dashboard/billing"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      立即续费
    </a>
  </div>
  <p style="color:#666;font-size:12px">如有疑问，请联系 support@mirrorspeed.io</p>
</div>
</body></html>`,
    }
  }

  return {
    subject: `[MirrorSpeed] Your subscription expires in ${days} days`,
    html: `
<!DOCTYPE html><html lang="en"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 24px">MirrorSpeed</h1>
  <p>Hi ${displayName},</p>
  <p>Your <strong style="color:#a78bfa">${planKey}</strong> plan expires on <strong>${dateStr}</strong> (in ${days} days).</p>
  <p>After expiry your account will revert to the free tier. Renew now to keep your connection uninterrupted.</p>
  <div style="margin:24px 0;text-align:center">
    <a href="https://mirrorspeed.io/dashboard/billing"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      Renew Now
    </a>
  </div>
  <p style="color:#666;font-size:12px">Questions? Email support@mirrorspeed.io</p>
</div>
</body></html>`,
  }
}

export function makeExpiredEmail(opts: {
  displayName: string
  planKey:     string
  lang:        string
}): { subject: string; html: string } {
  const { displayName, planKey, lang } = opts
  const isChinese = lang === 'zh'

  if (isChinese) {
    return {
      subject: '【镜速加速器】您的订阅已到期',
      html: `
<!DOCTYPE html><html lang="zh"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 8px">镜速加速器</h1>
  <p style="color:#aaa;margin:0 0 24px;font-size:14px">MirrorSpeed</p>
  <p>您好 ${displayName}，</p>
  <p>您的 <strong style="color:#a78bfa">${planKey}</strong> 套餐已到期，账户已恢复至免费用户模式。</p>
  <p>续费后可立即恢复全部节点访问权限。</p>
  <div style="margin:24px 0;text-align:center">
    <a href="https://mirrorspeed.io/dashboard/billing"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      重新订阅
    </a>
  </div>
  <p style="color:#666;font-size:12px">如有疑问，请联系 support@mirrorspeed.io</p>
</div>
</body></html>`,
    }
  }

  return {
    subject: '[MirrorSpeed] Your subscription has expired',
    html: `
<!DOCTYPE html><html lang="en"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 24px">MirrorSpeed</h1>
  <p>Hi ${displayName},</p>
  <p>Your <strong style="color:#a78bfa">${planKey}</strong> subscription has expired and your account has been reverted to the free tier.</p>
  <p>Resubscribe at any time to restore full access.</p>
  <div style="margin:24px 0;text-align:center">
    <a href="https://mirrorspeed.io/dashboard/billing"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      Resubscribe
    </a>
  </div>
  <p style="color:#666;font-size:12px">Questions? Email support@mirrorspeed.io</p>
</div>
</body></html>`,
  }
}
