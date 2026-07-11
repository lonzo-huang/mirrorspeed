import { NextRequest, NextResponse } from 'next/server'
import { put } from '@vercel/blob'
import { getUser, createAdminClient } from '@/lib/supabase/server'
import { getRefundReason } from '@/lib/refund-reasons'
import { sendEmail, makeRefundRequestEmail } from '@/lib/email'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

const TEAM_EMAIL = 'mirrorspeed@mirrorquant.com'
const MAX_SHOT_BYTES = 5 * 1024 * 1024   // 5MB

// POST /api/refund — 提交退款申请（multipart/form-data）
// 字段：faq_ack(=yes)、reason_code、detail、email、screenshot(File, 可选)
// 说明：仅登记申请 + 通知，不执行任何自动退款。
export async function POST(req: NextRequest) {
  const user = await getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  let form: FormData
  try { form = await req.formData() } catch {
    return NextResponse.json({ error: 'Invalid form data' }, { status: 400 })
  }

  const faqAck     = String(form.get('faq_ack') ?? '')
  const reasonCode = String(form.get('reason_code') ?? '')
  const detail     = String(form.get('detail') ?? '').trim()
  const email      = String(form.get('email') ?? '').trim()
  const deviceType = String(form.get('device_type') ?? '').trim().slice(0, 60) || null

  if (faqAck !== 'yes') {
    return NextResponse.json({ error: '请先确认已查阅 FAQ' }, { status: 400 })
  }
  const reason = getRefundReason(reasonCode)
  if (!reason) {
    return NextResponse.json({ error: '请选择退款原因' }, { status: 400 })
  }
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return NextResponse.json({ error: '请填写有效的订阅邮箱' }, { status: 400 })
  }
  if (detail.length < 5) {
    return NextResponse.json({ error: '请描述具体原因（至少 5 个字）' }, { status: 400 })
  }

  const admin = createAdminClient()

  // ── 订阅套餐（用于记录，best-effort）─────────────────────────────
  let plan: string | null = null
  try {
    const { data: sub } = await (admin.from('subscriptions') as any)
      .select('plan_key, status')
      .eq('user_id', user.id)
      .in('status', ['active', 'past_due', 'cancelled'])
      .order('created_at', { ascending: false })
      .maybeSingle()
    plan = (sub as any)?.plan_key ?? null
  } catch { /* ignore */ }

  // ── 截图上传 Vercel Blob（refunds/ 前缀，供 cron 两周后清理）────────
  let screenshotUrl: string | null = null
  const shot = form.get('screenshot')
  if (shot && shot instanceof File && shot.size > 0) {
    if (!shot.type.startsWith('image/')) {
      return NextResponse.json({ error: '截图必须是图片文件' }, { status: 400 })
    }
    if (shot.size > MAX_SHOT_BYTES) {
      return NextResponse.json({ error: '截图不能超过 5MB' }, { status: 400 })
    }
    try {
      const ext = (shot.name.split('.').pop() || 'png').toLowerCase().replace(/[^a-z0-9]/g, '')
      const key = `refunds/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
      const blob = await put(key, shot, { access: 'public', addRandomSuffix: false })
      screenshotUrl = blob.url
    } catch (e) {
      console.error('[refund] blob upload failed:', e)
      // 上传失败不阻断申请提交
    }
  }

  // ── 写入 refund_requests ─────────────────────────────────────────
  const { data: row, error } = await (admin.from('refund_requests') as any)
    .insert({
      user_id:        user.id,
      email,
      reason_code:    reason.code,
      reason_label:   reason.zh,
      detail,
      device_type:    deviceType,
      screenshot_url: screenshotUrl,
      plan,
      status:         'pending',
    })
    .select('id')
    .single()

  if (error) {
    console.error('[refund] insert failed:', error)
    return NextResponse.json({ error: '提交失败，请稍后再试' }, { status: 500 })
  }

  // ── 邮件通知团队（best-effort，不 await 影响响应）────────────────
  const mail = makeRefundRequestEmail({
    email,
    reasonLabel: reason.zh,
    detail,
    plan,
    deviceType,
    screenshotUrl,
    createdAt: new Date(),
  })
  sendEmail({ to: TEAM_EMAIL, subject: mail.subject, html: mail.html }).catch(() => {})

  return NextResponse.json({ ok: true, id: (row as any)?.id }, { status: 201 })
}
