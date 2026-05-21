import { NextResponse } from 'next/server'

const GITHUB_REPO = process.env.GITHUB_REPO ?? 'lonzo-huang/mirrorspeed'
const GITHUB_TOKEN = process.env.GITHUB_TOKEN  // 可选，提高 API 限速上限

export const dynamic = 'force-dynamic'  // 运行时渲染，通过 Cache-Control 由 CDN 缓存

export interface ReleaseAsset {
  name:                 string
  browser_download_url: string
  size:                 number   // bytes
  platform:             'android' | 'windows' | 'ios' | 'macos' | 'other'
}

export interface LatestRelease {
  version:    string   // e.g. "1.2.0"
  tag:        string   // e.g. "v1.2.0"
  name:       string
  body:       string
  published:  string   // ISO date
  assets:     ReleaseAsset[]
}

function detectPlatform(name: string): ReleaseAsset['platform'] {
  const n = name.toLowerCase()
  if (n.includes('android') || n.endsWith('.apk'))         return 'android'
  if (n.includes('windows') || n.endsWith('.zip') || n.endsWith('.exe') || n.endsWith('.msix')) return 'windows'
  if (n.includes('ios')     || n.endsWith('.ipa'))         return 'ios'
  if (n.includes('macos')   || n.endsWith('.dmg'))         return 'macos'
  return 'other'
}

// GET /api/releases/latest
// 返回 GitHub 最新 Release 信息（带 CDN 缓存）
export async function GET() {
  try {
    const token = process.env.GITHUB_TOKEN
    const repo  = process.env.GITHUB_REPO ?? 'lonzo-huang/mirrorspeed'

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
      if (res.status === 404) {
        return NextResponse.json({ version: null, assets: [] })
      }
      const body = await res.text()
      return NextResponse.json(
        { error: 'GitHub API error', status: res.status, detail: body },
        { status: 502 },
      )
    }

    const data = await res.json()

    const release: LatestRelease = {
      version:   String(data.tag_name ?? '').replace(/^v/, ''),
      tag:       data.tag_name ?? '',
      name:      data.name ?? '',
      body:      data.body ?? '',
      published: data.published_at ?? '',
      assets: Array.isArray(data.assets) ? (data.assets as any[]).map(a => ({
        name:                 a.name,
        browser_download_url: a.browser_download_url,
        size:                 a.size,
        platform:             detectPlatform(a.name),
      })) : [],
    }

    return NextResponse.json(release, {
      headers: { 'Cache-Control': 'public, s-maxage=3600, stale-while-revalidate=86400' },
    })
  } catch (err: any) {
    return NextResponse.json(
      { error: 'Internal error', detail: String(err?.message ?? err) },
      { status: 500 },
    )
  }
}
