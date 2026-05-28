import { NextRequest, NextResponse } from 'next/server'
import { sendEmail } from '@/lib/email'

const SUPPORT_EMAIL = 'mirrorspeed@mirrorquant.com'

export async function POST(req: NextRequest) {
  try {
    const { name, email, subject, message } = await req.json()

    if (!name?.trim() || !email?.trim() || !message?.trim()) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
    }

    // Basic email validation
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return NextResponse.json({ error: 'Invalid email address' }, { status: 400 })
    }

    const subjectLine = subject?.trim()
      ? `[Support] ${subject.trim()}`
      : `[Support] Message from ${name.trim()}`

    const html = `
<!DOCTYPE html><html><body style="font-family:sans-serif;background:#f5f5f5;padding:32px">
<div style="max-width:600px;margin:0 auto;background:#fff;border-radius:12px;padding:32px;border:1px solid #e0e0e0">
  <h2 style="margin:0 0 24px;color:#111">Support Request — MirrorSpeed</h2>
  <table style="width:100%;border-collapse:collapse;font-size:14px;margin-bottom:24px">
    <tr style="border-bottom:1px solid #eee">
      <td style="padding:10px 0;color:#666;width:100px">From</td>
      <td style="padding:10px 0;font-weight:600">${name.trim()}</td>
    </tr>
    <tr style="border-bottom:1px solid #eee">
      <td style="padding:10px 0;color:#666">Email</td>
      <td style="padding:10px 0"><a href="mailto:${email.trim()}" style="color:#a78bfa">${email.trim()}</a></td>
    </tr>
    ${subject?.trim() ? `<tr style="border-bottom:1px solid #eee">
      <td style="padding:10px 0;color:#666">Subject</td>
      <td style="padding:10px 0">${subject.trim()}</td>
    </tr>` : ''}
  </table>
  <div style="background:#f9f9f9;border-radius:8px;padding:16px;font-size:14px;line-height:1.6;white-space:pre-wrap">${message.trim()}</div>
  <p style="margin-top:24px;font-size:12px;color:#999">
    Sent from MirrorSpeed support form · Reply directly to this email to respond.
  </p>
</div>
</body></html>`

    await sendEmail({
      to:      SUPPORT_EMAIL,
      subject: subjectLine,
      html,
    })

    // Send auto-reply to user
    const isZh = /[一-龥]/.test(message) || /[一-龥]/.test(name)
    await sendEmail({
      to:      email.trim(),
      subject: isZh ? '【镜速加速器】我们已收到您的留言' : '[MirrorSpeed] We received your message',
      html: isZh ? `
<!DOCTYPE html><html lang="zh"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 8px">镜速加速器</h1>
  <p>您好 ${name.trim()}，</p>
  <p>感谢您联系我们！我们已收到您的留言，将尽快回复（通常在 1 个工作日内）。</p>
  <p style="color:#666;font-size:12px">如有紧急问题，请直接发送邮件至 ${SUPPORT_EMAIL}</p>
</div>
</body></html>` : `
<!DOCTYPE html><html lang="en"><body style="font-family:sans-serif;background:#0a0a0a;color:#e5e5e5;padding:32px">
<div style="max-width:560px;margin:0 auto;background:#111;border:1px solid #222;border-radius:16px;padding:32px">
  <h1 style="color:#a78bfa;margin:0 0 24px">MirrorSpeed</h1>
  <p>Hi ${name.trim()},</p>
  <p>Thanks for reaching out! We've received your message and will get back to you as soon as possible (usually within 1 business day).</p>
  <p style="color:#666;font-size:12px">For urgent issues, email us directly at ${SUPPORT_EMAIL}</p>
</div>
</body></html>`,
    })

    return NextResponse.json({ ok: true })
  } catch (err) {
    console.error('[support] Error:', err)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
