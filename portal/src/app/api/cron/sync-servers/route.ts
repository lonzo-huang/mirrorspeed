import { NextRequest, NextResponse } from 'next/server'

// ⚠️ 临时探针（用完即删）：这个端点的真活儿已迁到控制机 VM01-FRA-DE 的
// ms-sync-servers.timer。但仍有个来历不明的外部定时器每 60s 在打它，
// 这里只把调用方身份打进日志，好把它揪出来关掉。不做任何实际工作。
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  console.log('[probe] ua=%j ip=%j fwd=%j ref=%j auth=%j',
    req.headers.get('user-agent'),
    req.headers.get('x-real-ip'),
    req.headers.get('x-forwarded-for'),
    req.headers.get('referer'),
    req.headers.get('authorization') ? 'present' : 'none',
  )
  return new NextResponse(null, { status: 204 })
}
