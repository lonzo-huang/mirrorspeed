import { createAdminClient } from '@/lib/supabase/server'
import { unstable_noStore as noStore } from 'next/cache'
import { NextResponse } from 'next/server'

// 必须 force-dynamic：GET() 不接收 request、也不用动态 API，Next 会在【构建时】
// 把本路由静态预渲染，之后永远返回「上次部署时」的公告——运营改了 app_config
// 也不生效（曾导致公告撤不下来）。CDN 仍按下方 s-maxage=60 缓存 60 秒。
export const dynamic = 'force-dynamic'

// GET /api/announcement — 公开的全局通告（运营在 app_config.announcement 下发）
// app_config.announcement.value 存一段 JSON，例如：
//   {"id":"2026-06-08","title":"系统维护","body":"今晚 02:00 维护 30 分钟","level":"warning","active":true,"url":null}
// active=false 或不存在 → 返回 {announcement:null}
export async function GET() {
  noStore()   // 双保险：绝不在构建期预渲染
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
