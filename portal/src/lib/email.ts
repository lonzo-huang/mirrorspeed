/**
 * Email utility. Prefers SMTP when configured, otherwise falls back to the
 * Brevo HTTP API.
 *
 * SMTP (preferred if set) — e.g. send via mirrorspeed@mirrorquant.com:
 *   SMTP_HOST  — e.g. smtp.gmail.com / smtp.zoho.com / smtp-mail.outlook.com
 *   SMTP_PORT  — 465 (SSL) or 587 (STARTTLS). Default 465.
 *   SMTP_USER  — full mailbox address (also used as From if EMAIL_FROM_ADDRESS unset)
 *   SMTP_PASS  — app-specific password (NOT the login password for Gmail/Workspace)
 *
 * Brevo (fallback) — used only when SMTP_HOST is not set:
 *   BREVO_API_KEY  — from Brevo → SMTP & API → API keys
 *
 * Optional (both paths):
 *   EMAIL_FROM_ADDRESS — From address (SMTP defaults to SMTP_USER; Brevo to noreply@mirrorspeed.com)
 *   EMAIL_FROM_NAME    — defaults to MirrorSpeed
 */

import nodemailer from 'nodemailer'

interface SendEmailOptions {
  to:      string
  subject: string
  html:    string
}

export interface SendEmailResult {
  ok:      boolean
  status?: number
  error?:  string
  from?:   string
}

export async function sendEmail(opts: SendEmailOptions): Promise<SendEmailResult> {
  // SMTP 优先（若已配置）
  if (process.env.SMTP_HOST) {
    return sendViaSmtp(opts)
  }
  return sendViaBrevo(opts)
}

// ── SMTP 发送（nodemailer）───────────────────────────────────────────────────
async function sendViaSmtp({ to, subject, html }: SendEmailOptions): Promise<SendEmailResult> {
  const host = process.env.SMTP_HOST!
  const port = parseInt(process.env.SMTP_PORT ?? '465', 10)
  const user = process.env.SMTP_USER
  const pass = process.env.SMTP_PASS
  if (!user || !pass) {
    console.warn('[email] SMTP_USER / SMTP_PASS not set, cannot send to', to)
    return { ok: false, error: 'SMTP_USER / SMTP_PASS not configured' }
  }
  const from = process.env.EMAIL_FROM_ADDRESS ?? user
  const name = process.env.EMAIL_FROM_NAME ?? 'MirrorSpeed'

  try {
    const transporter = nodemailer.createTransport({
      host,
      port,
      secure: port === 465,           // 465 = SSL；587 = STARTTLS
      auth: { user, pass },
    })
    await transporter.sendMail({
      from: `"${name}" <${from}>`,
      to,
      subject,
      html,
    })
    return { ok: true, from }
  } catch (e: any) {
    console.error('[email] SMTP send failed:', e?.message)
    return { ok: false, error: `smtp: ${e?.message}`, from }
  }
}

// ── Brevo HTTP API 发送（回退）──────────────────────────────────────────────
async function sendViaBrevo({ to, subject, html }: SendEmailOptions): Promise<SendEmailResult> {
  const apiKey = process.env.BREVO_API_KEY
  if (!apiKey) {
    console.warn('[email] BREVO_API_KEY not configured, skipping email to', to)
    return { ok: false, error: 'BREVO_API_KEY not configured' }
  }

  const fromEmail = process.env.EMAIL_FROM_ADDRESS ?? 'noreply@mirrorspeed.com'
  const fromName  = process.env.EMAIL_FROM_NAME    ?? 'MirrorSpeed'

  let res: Response
  try {
    res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method:  'POST',
      headers: {
        'api-key':      apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        sender:      { name: fromName, email: fromEmail },
        to:          [{ email: to }],
        subject,
        htmlContent: html,
      }),
    })
  } catch (e: any) {
    console.error('[email] Brevo fetch failed:', e?.message)
    return { ok: false, error: `fetch failed: ${e?.message}`, from: fromEmail }
  }

  if (!res.ok) {
    const text = await res.text().catch(() => '')
    console.error('[email] Brevo API error:', res.status, text)
    return { ok: false, status: res.status, error: text, from: fromEmail }
  }
  return { ok: true, status: res.status, from: fromEmail }
}

// ── Email templates ────────────────────────────────────────────────────────

export function makeSubscriptionConfirmEmail(opts: {
  displayName: string
  planKey:     string
  expiresAt:   Date
  amountCents: number
  currency:    string
  lang:        string
}): { subject: string; html: string } {
  const { displayName, planKey, expiresAt, amountCents, currency, lang } = opts
  const dateStr  = expiresAt.toISOString().split('T')[0]
  const symbol   = currency === 'cny' ? '¥' : currency === 'eur' ? '€' : '$'
  const amount   = `${symbol}${(amountCents / 100).toFixed(2)}`
  const isChinese = lang === 'zh'

  if (isChinese) {
    return {
      subject: '【镜速加速器】订阅成功确认',
      html: `
<!DOCTYPE html><html lang="zh"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 8px">镜速加速器</h1>
  <p style="color:#aaa;margin:0 0 24px;font-size:14px">MirrorSpeed</p>
  <p>您好 ${displayName}，</p>
  <p>🎉 您的订阅已成功激活！</p>
  <table style="width:100%;border-collapse:collapse;margin:20px 0;font-size:14px">
    <tr style="border-bottom:1px solid #333">
      <td style="padding:10px 0;color:#aaa">套餐</td>
      <td style="padding:10px 0;text-align:right;color:#a78bfa;font-weight:bold;text-transform:capitalize">${planKey}</td>
    </tr>
    <tr style="border-bottom:1px solid #333">
      <td style="padding:10px 0;color:#aaa">付款金额</td>
      <td style="padding:10px 0;text-align:right">${amount}</td>
    </tr>
    <tr>
      <td style="padding:10px 0;color:#aaa">有效期至</td>
      <td style="padding:10px 0;text-align:right">${dateStr}</td>
    </tr>
  </table>
  <div style="margin:24px 0;text-align:center">
    <a href="https://mirrorspeed.com/dashboard"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      进入控制台
    </a>
  </div>
  <p style="color:#666;font-size:12px">如有疑问，请联系 support@mirrorspeed.com</p>
</div>
</body></html>`,
    }
  }

  return {
    subject: '[MirrorSpeed] Subscription Confirmed',
    html: `
<!DOCTYPE html><html lang="en"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 24px">MirrorSpeed</h1>
  <p>Hi ${displayName},</p>
  <p>🎉 Your subscription is now active!</p>
  <table style="width:100%;border-collapse:collapse;margin:20px 0;font-size:14px">
    <tr style="border-bottom:1px solid #333">
      <td style="padding:10px 0;color:#aaa">Plan</td>
      <td style="padding:10px 0;text-align:right;color:#a78bfa;font-weight:bold;text-transform:capitalize">${planKey}</td>
    </tr>
    <tr style="border-bottom:1px solid #333">
      <td style="padding:10px 0;color:#aaa">Amount paid</td>
      <td style="padding:10px 0;text-align:right">${amount}</td>
    </tr>
    <tr>
      <td style="padding:10px 0;color:#aaa">Valid until</td>
      <td style="padding:10px 0;text-align:right">${dateStr}</td>
    </tr>
  </table>
  <div style="margin:24px 0;text-align:center">
    <a href="https://mirrorspeed.com/dashboard"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      Go to Dashboard
    </a>
  </div>
  <p style="color:#666;font-size:12px">Questions? Email support@mirrorspeed.com</p>
</div>
</body></html>`,
  }
}

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
    <a href="https://mirrorspeed.com/dashboard/billing"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      立即续费
    </a>
  </div>
  <p style="color:#666;font-size:12px">如有疑问，请联系 support@mirrorspeed.com</p>
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
    <a href="https://mirrorspeed.com/dashboard/billing"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      Renew Now
    </a>
  </div>
  <p style="color:#666;font-size:12px">Questions? Email support@mirrorspeed.com</p>
</div>
</body></html>`,
  }
}

// 退款申请通知（发给团队邮箱）。
export function makeRefundRequestEmail(opts: {
  email:        string
  reasonLabel:  string
  detail:       string
  plan?:        string | null
  deviceType?:  string | null
  screenshotUrl?: string | null
  createdAt:    Date
}): { subject: string; html: string } {
  const { email, reasonLabel, detail, plan, deviceType, screenshotUrl, createdAt } = opts
  const dateStr = createdAt.toISOString().replace('T', ' ').slice(0, 16)
  const shot = screenshotUrl
    ? `<tr><td style="padding:10px 0;color:#aaa">截图</td><td style="padding:10px 0;text-align:right"><a href="${screenshotUrl}" style="color:#a78bfa">查看图片</a></td></tr>`
    : ''
  return {
    subject: `【镜速加速器】新退款申请 · ${reasonLabel}`,
    html: `
<!DOCTYPE html><html lang="zh"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 8px">新退款申请</h1>
  <p style="color:#aaa;margin:0 0 24px;font-size:14px">MirrorSpeed · 镜速加速器</p>
  <table style="width:100%;border-collapse:collapse;margin:12px 0;font-size:14px">
    <tr style="border-bottom:1px solid #333"><td style="padding:10px 0;color:#aaa">订阅邮箱</td><td style="padding:10px 0;text-align:right">${email}</td></tr>
    <tr style="border-bottom:1px solid #333"><td style="padding:10px 0;color:#aaa">退款原因</td><td style="padding:10px 0;text-align:right;color:#a78bfa;font-weight:bold">${reasonLabel}</td></tr>
    <tr style="border-bottom:1px solid #333"><td style="padding:10px 0;color:#aaa">套餐</td><td style="padding:10px 0;text-align:right">${plan ?? '—'}</td></tr>
    <tr style="border-bottom:1px solid #333"><td style="padding:10px 0;color:#aaa">终端类型</td><td style="padding:10px 0;text-align:right">${deviceType ?? '—'}</td></tr>
    ${shot}
    <tr><td style="padding:10px 0;color:#aaa">提交时间</td><td style="padding:10px 0;text-align:right">${dateStr}</td></tr>
  </table>
  <div style="margin:16px 0;padding:14px;background:#0a0a0a;border:1px solid #222;border-radius:10px">
    <p style="color:#aaa;font-size:12px;margin:0 0 6px">用户描述</p>
    <p style="margin:0;white-space:pre-wrap;font-size:14px">${(detail || '（未填写）').replace(/</g, '&lt;')}</p>
  </div>
  <div style="margin:24px 0;text-align:center">
    <a href="https://mirrorspeed.com/admin/refunds"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      前往管理后台处理
    </a>
  </div>
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
    <a href="https://mirrorspeed.com/dashboard/billing"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      重新订阅
    </a>
  </div>
  <p style="color:#666;font-size:12px">如有疑问，请联系 support@mirrorspeed.com</p>
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
    <a href="https://mirrorspeed.com/dashboard/billing"
       style="display:inline-block;padding:12px 32px;background:#a78bfa;color:#000;font-weight:700;border-radius:10px;text-decoration:none">
      Resubscribe
    </a>
  </div>
  <p style="color:#666;font-size:12px">Questions? Email support@mirrorspeed.com</p>
</div>
</body></html>`,
  }
}
