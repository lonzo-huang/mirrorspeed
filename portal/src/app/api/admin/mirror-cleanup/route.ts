import { list, del } from '@vercel/blob'
import { NextRequest, NextResponse } from 'next/server'

export const runtime = 'nodejs'

// POST /api/admin/mirror-cleanup
// Headers: x-upload-secret: <CRON_SECRET>
// Body: { keep?: string }  — version substring to KEEP (e.g. "2.1.0"); everything
//        else under apk/ is deleted. Omit keep → delete all apk/ blobs.
//
// Vercel Blob Hobby plan caps at 1GB;每次发版都上传新包，旧包不清理会撑满，
// 导致后续上传失败、cn_apk_url 卡在旧版本。release.ps1 在上传前调用本接口，
// 把存储限制在「当前版本」一份左右。list/del 用环境里的 BLOB_READ_WRITE_TOKEN。
export async function POST(req: NextRequest): Promise<NextResponse> {
  if (req.headers.get('x-upload-secret') !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const { keep } = (await req.json().catch(() => ({}))) as { keep?: string }

  try {
    let deleted = 0
    let cursor: string | undefined
    do {
      const res = await list({ prefix: 'apk/', cursor, limit: 1000 })
      const urls = res.blobs
        .filter(b => !keep || !b.pathname.includes(keep))
        .map(b => b.url)
      if (urls.length) { await del(urls); deleted += urls.length }
      cursor = res.cursor
    } while (cursor)

    return NextResponse.json({ ok: true, deleted, kept: keep ?? null })
  } catch (err: any) {
    return NextResponse.json({ error: String(err?.message ?? err) }, { status: 500 })
  }
}
