/**
 * Admin Blog API — session-gated (admin role). Powers the /admin/blog editor.
 *   GET    /api/admin/blog        — list ALL posts (incl. drafts)
 *   POST   /api/admin/blog        — create/upsert a post (by slug)
 *   DELETE /api/admin/blog?slug=  — delete a post
 */
import { NextRequest, NextResponse } from 'next/server'
import { getUser, createAdminClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'

async function requireAdmin() {
  const user = await getUser()
  if (!user) return null
  const admin = createAdminClient()
  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if ((profile as any)?.role !== 'admin') return null
  return admin
}

export async function GET(req: NextRequest) {
  const admin = await requireAdmin()
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const slug = new URL(req.url).searchParams.get('slug')
  if (slug) {
    // 单篇完整内容（含 content），供编辑器回填。
    const { data, error } = await admin.from('blog_posts').select('*').eq('slug', slug).single()
    if (error) return NextResponse.json({ error: error.message }, { status: 404 })
    return NextResponse.json({ post: data })
  }

  const { data, error } = await admin
    .from('blog_posts')
    .select('id, slug, title, excerpt, tags, author, cover_url, published, published_at, updated_at')
    .order('published_at', { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ posts: data })
}

export async function POST(req: NextRequest) {
  const admin = await requireAdmin()
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: any
  try { body = await req.json() } catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }) }

  const { slug, title, content, excerpt, tags, author, coverUrl, published, publishedAt } = body
  if (!slug || !title || !content) {
    return NextResponse.json({ error: 'slug、title、content 必填' }, { status: 400 })
  }

  const { data, error } = await admin
    .from('blog_posts')
    .upsert({
      slug: String(slug).trim(),
      title,
      content,
      excerpt:      excerpt  ?? null,
      tags:         Array.isArray(tags) ? tags : [],
      author:       author   ?? 'MirrorSpeed',
      cover_url:    coverUrl  ?? null,
      published:    published ?? true,
      published_at: publishedAt ?? new Date().toISOString(),
      updated_at:   new Date().toISOString(),
    }, { onConflict: 'slug' })
    .select('id, slug, title, published, published_at')
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ post: data }, { status: 201 })
}

export async function DELETE(req: NextRequest) {
  const admin = await requireAdmin()
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const slug = new URL(req.url).searchParams.get('slug')
  if (!slug) return NextResponse.json({ error: 'slug required' }, { status: 400 })
  const { error } = await admin.from('blog_posts').delete().eq('slug', slug)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
