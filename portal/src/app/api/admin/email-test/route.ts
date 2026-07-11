import { NextResponse } from 'next/server'
import { getUser, createAdminClient } from '@/lib/supabase/server'
import { sendEmail } from '@/lib/email'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

const TEAM_EMAIL = 'mirrorspeed@mirrorquant.com'

// GET /api/admin/email-test — 管理员专用邮件自检。
// 直接返回 Brevo 的真实结果，用于诊断「收不到邮件」到底是哪种原因：
//   - BREVO_API_KEY not configured  → 环境变量没配
//   - status 400 + sender ...        → 发件人未在 Brevo 验证
//   - ok:true                        → 已发出（检查垃圾箱 / Brevo 后台 Logs）
export async function GET() {
  const user = await getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const admin = createAdminClient()
  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if ((profile as any)?.role !== 'admin') {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const result = await sendEmail({
    to:      TEAM_EMAIL,
    subject: '【镜速加速器】邮件自检测试',
    html:    '<p>这是一封来自 /api/admin/email-test 的测试邮件。收到即表示邮件通道正常。</p>',
  })

  return NextResponse.json({
    sentTo:            TEAM_EMAIL,
    from:              result.from ?? '(default noreply@mirrorspeed.com)',
    hasBrevoKey:       !!process.env.BREVO_API_KEY,
    emailFromEnvSet:   !!process.env.EMAIL_FROM_ADDRESS,
    result,
  })
}
