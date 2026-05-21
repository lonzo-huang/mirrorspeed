import { NextResponse } from 'next/server'
import { unstable_noStore as noStore } from 'next/cache'

// force-dynamic: opt out of ALL static rendering / build-time prerendering
export const dynamic = 'force-dynamic'

export interface ReleaseAsset {
  id:                   number   // GitHub asset ID — used by /api/download proxy
  name:                 string
  browser_download_url: string
  size:                 number   // bytes
  platform:             'android' | 'windows' | 'ios' | 'macos' | 'other'
}

export interface LatestRelease {
  version:    string
  tag:        string
  name:       string
  body:       string
  published:  string
  assets:     ReleaseAsset[]
}

function detectPlatform(name: string): ReleaseAsset['platform'] {
  const n = name.toLowerCase()
  if (n.includes('android') || n.endsWith('.apk'))                                          return 'android'
  if (n.includes('windows') || n.endsWith('.zip') || n.endsWith('.exe') || n.endsWith('.msix')) return 'windows'
  if (n.includes('ios')     || n.endsWith('.ipa'))                                          return 'ios'
  if (n.includes('macos')   || n.endsWith('.dmg'))                                          return 'macos'
  return 'other'
}

// Strip BOM and whitespace that can sneak in via env-var storage tools
function cleanEnvToken(raw: string | undefined): string {
  if (!raw) return ''
  return raw.replace(/﻿/g, '').trim()
}

// GET /api/releases/latest
export async function GET() {
  // noStore() tells Next.js never to prerender this route at build time
  noStore()

  try {
    const token = cleanEnvToken(process.env.GITHUB_TOKEN)
    const repo  = cleanEnvToken(process.env.GITHUB_REPO) || 'lonzo-huang/mirrorspeed'

    const reqHeaders: Record<string, string> = {
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    }
    if (token) reqHeaders['Authorization'] = `Bearer ${token}`

    const res = await fetch(
      `https://api.github.com/repos/${repo}/releases/latest`,
      { headers: reqHeaders, cache: 'no-store' },
    )

    if (!res.ok) {
      if (res.status === 404) return NextResponse.json({ version: null, assets: [] })
      const body = await res.text()
      return NextResponse.json(
        { error: 'GitHub API error', status: res.status, detail: body },
        { status: 502 },
      )
    }

    const data = await res.json()

    const release: LatestRelease = {
      version:   String(data.tag_name ?? '').replace(/^v/, ''),
      tag:       data.tag_name  ?? '',
      name:      data.name      ?? '',
      body:      data.body      ?? '',
      published: data.published_at ?? '',
      assets: Array.isArray(data.assets)
        ? (data.assets as any[]).map(a => ({
            id:                   a.id,
            name:                 a.name,
            browser_download_url: a.browser_download_url,
            size:                 a.size,
            platform:             detectPlatform(a.name),
          }))
        : [],
    }

    return NextResponse.json(release, {
      headers: { 'Cache-Control': 'no-store, no-cache, must-revalidate' },
    })
  } catch (err: any) {
    return NextResponse.json(
      { error: 'Internal error', detail: String(err?.message ?? err) },
      { status: 500 },
    )
  }
}
