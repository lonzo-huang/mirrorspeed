import { NextResponse } from 'next/server'
import { unstable_noStore as noStore } from 'next/cache'

// force-dynamic + no-store：与 /api/releases/latest 一致，始终实时取 GitHub，无缓存。
export const dynamic = 'force-dynamic'

export interface ChangelogEntry {
  version:   string   // 3.0.1（去掉 v 前缀）
  tag:       string   // v3.0.1
  name:      string   // Release 标题
  body:      string   // Release 正文（markdown；可含 <!--LANG:zh--> / <!--LANG:en--> 分段）
  published: string   // ISO 时间
  prerelease: boolean
}

function cleanEnvToken(raw: string | undefined): string {
  if (!raw) return ''
  return raw.replace(/﻿/g, '').trim()
}

// GET /api/releases?limit=20 —— 列出历史 Release，供下载页「更新日志」渲染。
export async function GET(req: Request) {
  noStore()

  try {
    const url    = new URL(req.url)
    const limit  = Math.min(Math.max(Number(url.searchParams.get('limit') ?? 20), 1), 50)
    const token  = cleanEnvToken(process.env.GITHUB_TOKEN)
    const repo   = cleanEnvToken(process.env.GITHUB_REPO) || 'lonzo-huang/mirrorspeed'

    const reqHeaders: Record<string, string> = {
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    }
    if (token) reqHeaders['Authorization'] = `Bearer ${token}`

    const res = await fetch(
      `https://api.github.com/repos/${repo}/releases?per_page=${limit}`,
      { headers: reqHeaders, cache: 'no-store' },
    )

    if (!res.ok) {
      if (res.status === 404) return NextResponse.json({ releases: [] })
      const body = await res.text()
      return NextResponse.json(
        { error: 'GitHub API error', status: res.status, detail: body },
        { status: 502 },
      )
    }

    const data = await res.json()
    const releases: ChangelogEntry[] = Array.isArray(data)
      ? (data as any[])
          .filter(r => !r.draft)   // 草稿不展示
          .map(r => ({
            version:    String(r.tag_name ?? '').replace(/^v/, ''),
            tag:        r.tag_name     ?? '',
            name:       r.name         ?? '',
            body:       r.body         ?? '',
            published:  r.published_at ?? '',
            prerelease: Boolean(r.prerelease),
          }))
      : []

    return NextResponse.json(
      { releases },
      { headers: { 'Cache-Control': 'no-store, no-cache, must-revalidate' } },
    )
  } catch (err: any) {
    return NextResponse.json(
      { error: 'Internal error', detail: String(err?.message ?? err) },
      { status: 500 },
    )
  }
}
