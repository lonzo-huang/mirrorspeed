import { NextRequest, NextResponse } from 'next/server'
import { list, del } from '@vercel/blob'
import { createAdminClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

// GET /api/cron/gc-refund-blobs
// 每日清理退款截图：删除 refunds/ 下上传超过 14 天的 Blob，并把对应记录的
// screenshot_url 置空（保留申请记录本身）。鉴权：Authorization: Bearer <CRON_SECRET>。
const CRON_SECRET = process.env.CRON_SECRET
const TTL_MS = 14 * 24 * 60 * 60 * 1000

export async function GET(req: NextRequest) {
  const auth = req.headers.get('authorization')
  if (CRON_SECRET && auth !== `Bearer ${CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const cutoff = Date.now() - TTL_MS
  const staleUrls: string[] = []

  try {
    let cursor: string | undefined = undefined
    do {
      const res: Awaited<ReturnType<typeof list>> = await list({ prefix: 'refunds/', cursor, limit: 1000 })
      for (const b of res.blobs) {
        if (new Date(b.uploadedAt).getTime() < cutoff) staleUrls.push(b.url)
      }
      cursor = res.hasMore ? res.cursor : undefined
    } while (cursor)

    if (staleUrls.length > 0) {
      await del(staleUrls)
      // 把对应记录的截图链接置空（记录本身保留）
      const admin = createAdminClient()
      await (admin.from('refund_requests') as any)
        .update({ screenshot_url: null })
        .in('screenshot_url', staleUrls)
    }
  } catch (e: any) {
    console.error('[gc-refund-blobs] failed:', e)
    return NextResponse.json({ error: e?.message ?? 'failed' }, { status: 500 })
  }

  return NextResponse.json({ deleted: staleUrls.length, timestamp: new Date().toISOString() })
}
