import { revalidatePath, revalidateTag } from 'next/cache'
import { NextRequest, NextResponse } from 'next/server'

// POST /api/revalidate?token=<CRON_SECRET>&path=/download
// 由构建脚本在上传完成后调用，强制刷新指定页面的 Next.js 缓存
export async function POST(req: NextRequest) {
  const token = req.nextUrl.searchParams.get('token')
  if (token !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const path = req.nextUrl.searchParams.get('path') ?? '/download'

  revalidatePath(path)
  revalidateTag('releases')   // 同时清 /api/releases/latest 的 fetch 缓存

  return NextResponse.json({ revalidated: true, path, ts: Date.now() })
}
