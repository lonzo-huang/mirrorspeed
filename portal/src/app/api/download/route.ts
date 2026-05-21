import { NextRequest, NextResponse } from 'next/server'
import { unstable_noStore as noStore } from 'next/cache'

export const dynamic = 'force-dynamic'

function cleanToken(raw: string | undefined): string {
  if (!raw) return ''
  return raw.replace(/﻿/g, '').trim()
}

// GET /api/download?id=<github_asset_id>&name=<filename>
// Proxies private-repo GitHub Release asset via server-side token auth.
// GitHub returns a 302 → CDN URL; we relay that redirect to the browser.
export async function GET(req: NextRequest) {
  noStore()

  const id   = req.nextUrl.searchParams.get('id')
  const name = req.nextUrl.searchParams.get('name') ?? 'download'

  if (!id) {
    return NextResponse.json({ error: 'Missing asset id' }, { status: 400 })
  }

  const token = cleanToken(process.env.GITHUB_TOKEN)
  const repo  = cleanToken(process.env.GITHUB_REPO) || 'lonzo-huang/mirrorspeed'

  if (!token) {
    return NextResponse.json({ error: 'Server not configured for private downloads' }, { status: 500 })
  }

  // Ask GitHub for the binary — it will 302-redirect to a time-limited CDN URL
  const res = await fetch(
    `https://api.github.com/repos/${repo}/releases/assets/${id}`,
    {
      headers: {
        Accept:               'application/octet-stream',
        Authorization:        `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent':         'MirrorSpeed-Portal/1.0',
      },
      redirect: 'manual',  // capture the Location header instead of following
    },
  )

  // GitHub responds with 302 → short-lived CDN URL (no auth required)
  if (res.status === 301 || res.status === 302) {
    const cdnUrl = res.headers.get('location')
    if (cdnUrl) return NextResponse.redirect(cdnUrl)
  }

  // Fallback: stream directly (handles 200 OK from some configurations)
  if (res.ok) {
    const headers = new Headers({
      'Content-Type':        res.headers.get('content-type') ?? 'application/octet-stream',
      'Content-Disposition': `attachment; filename="${name}"`,
    })
    const ct = res.headers.get('content-length')
    if (ct) headers.set('Content-Length', ct)
    return new NextResponse(res.body, { headers })
  }

  return NextResponse.json(
    { error: 'GitHub asset fetch failed', status: res.status },
    { status: 502 },
  )
}
