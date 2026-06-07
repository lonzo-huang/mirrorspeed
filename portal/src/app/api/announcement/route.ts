import { createAdminClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

// GET /api/announcement — 公开的全局通告（运营在 app_config.announcement 下发）
// app_config.announcement.value 存一段 JSON，例如：
//   {"id":"2026-06-08","title":"系统维护","body":"今晚 02:00 维护 30 分钟","level":"warning","active":true,"url":null}
// active=false 或不存在 → 返回 {announcement:null}
export async function GET() {
  try {
    const admin = createAdminClient()
    const { data } = await admin
      .from('app_config' as any)
      .select('value')
      .eq('key', 'announcement')
      .maybeSingle()

    let ann: any = null
    const raw = (data as any)?.value
    if (raw) {
      try {
        const parsed = JSON.parse(raw)
        if (parsed && parsed.active !== false && (parsed.title || parsed.body)) {
          ann = {
            id:    parsed.id    ?? null,
            title: parsed.title ?? '',
            body:  parsed.body  ?? '',
            level: parsed.level ?? 'info',   // info | warning | critical
            url:   parsed.url   ?? null,
          }
        }
      } catch { /* 非 JSON：当作纯文本 body */
        ann = { id: null, title: '', body: String(raw), level: 'info', url: null }
      }
    }

    return NextResponse.json({ announcement: ann }, {
      headers: { 'Cache-Control': 'public, s-maxage=60, stale-while-revalidate=120' },
    })
  } catch {
    return NextResponse.json({ announcement: null })
  }
}
