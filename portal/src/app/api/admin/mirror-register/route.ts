import { NextRequest, NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/server'

export const runtime = 'nodejs'

// POST /api/admin/mirror-register
// Body: { token, platform: 'android'|'windows', url, version }
// Called by release.ps1 after uploading to Vercel Blob, as a backup to the
// onUploadCompleted Vercel Blob callback (which may not fire in CI environments).
export async function POST(req: NextRequest) {
  let body: { token?: string; platform?: string; url?: string; version?: string }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  if (body.token !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { platform, url, version } = body
  if (!platform || !url) {
    return NextResponse.json({ error: 'Missing platform or url' }, { status: 400 })
  }

  const key = platform === 'android' ? 'cn_apk_url' : 'cn_win_url'
  const admin = createAdminClient()

  const { error } = await (admin.from('app_config' as any) as any)
    .upsert({ key, value: url }, { onConflict: 'key' })

  if (error) {
    console.error('[mirror-register] Supabase error:', error)
    return NextResponse.json({ error: 'DB write failed' }, { status: 500 })
  }

  console.log(`[mirror-register] ${platform} v${version ?? '?'} → ${url}`)
  return NextResponse.json({ ok: true, key, url })
}
