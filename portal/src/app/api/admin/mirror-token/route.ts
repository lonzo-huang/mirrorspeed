import { handleUpload, type HandleUploadBody } from '@vercel/blob/client'
import { NextRequest, NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/server'

export const runtime = 'nodejs'

// POST /api/admin/mirror-token
//
// Handles two request types (both use the same endpoint):
//
// 1. type = blob.generate-client-token  (from release.ps1)
//    Headers: x-upload-secret: <CRON_SECRET>
//    → verifies auth, returns { clientToken, url } for direct CDN upload
//
// 2. type = blob.upload-completed  (called by Vercel Blob after upload)
//    → stores the final blob URL into Supabase app_config
export async function POST(req: NextRequest): Promise<NextResponse> {
  // Capture auth header before body is consumed
  const uploadSecret = req.headers.get('x-upload-secret')

  let body: HandleUploadBody
  try {
    body = await req.json() as HandleUploadBody
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  try {
    const jsonResponse = await handleUpload({
      body,
      request: req,

      // Called when release.ps1 requests an upload token
      onBeforeGenerateToken: async (pathname) => {
        if (uploadSecret !== process.env.CRON_SECRET) {
          throw new Error('Unauthorized: invalid upload secret')
        }
        return {
          allowedContentTypes: [
            'application/vnd.android.package-archive',
            'application/zip',
            'application/octet-stream',
          ],
          maximumSizeInBytes: 500 * 1024 * 1024, // 500 MB
          tokenPayload: pathname,                  // carry pathname through to callback
        }
      },

      // Called by Vercel Blob servers after upload completes
      onUploadCompleted: async ({ blob, tokenPayload }) => {
        const admin = createAdminClient()
        const pathname = String(tokenPayload ?? blob.pathname)

        // Determine platform from filename
        const lower = pathname.toLowerCase()
        const platform: 'android' | 'windows' =
          lower.endsWith('.apk') || lower.includes('android') ? 'android' : 'windows'

        const key = platform === 'android' ? 'cn_apk_url' : 'cn_win_url'

        await (admin.from('app_config' as any) as any)
          .upsert({ key, value: blob.url }, { onConflict: 'key' })

        console.log(`[mirror-token] Registered ${platform} CDN URL: ${blob.url}`)
      },
    })

    return NextResponse.json(jsonResponse)
  } catch (err: any) {
    console.error('[mirror-token] handleUpload error:', err)
    return NextResponse.json({ error: String(err?.message ?? err) }, { status: 500 })
  }
}
