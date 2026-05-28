/**
 * Blog API
 *
 * GET  /api/blog          — list published posts (public)
 * POST /api/blog          — create/upsert post (requires x-api-key: BLOG_API_KEY)
 *
 * Bot request body (POST):
 * {
 *   slug:        string   (URL-safe identifier, unique)
 *   title:       string
 *   excerpt?:    string
 *   content:     string   (markdown or HTML)
 *   tags?:       string[]
 *   author?:     string
 *   coverUrl?:   string
 *   published?:  boolean  (default true)
 *   publishedAt?: string  (ISO date, default now)
 * }
 */

import { NextRequest, NextResponse } from 'next/server'
import { createClient }              from '@supabase/supabase-js'

function adminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false } }
  )
}

// ── GET — list posts (public) ─────────────────────────────────────────────────
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const limit  = Math.min(parseInt(searchParams.get('limit')  ?? '20'),  100)
  const offset = Math.max(parseInt(searchParams.get('offset') ?? '0'),   0)
  const tag    = searchParams.get('tag')

  const supabase = adminClient()
  let query = supabase
    .from('blog_posts')
    .select('id, slug, title, excerpt, tags, author, cover_url, published_at')
    .eq('published', true)
    .order('published_at', { ascending: false })
    .range(offset, offset + limit - 1)

  if (tag) query = query.contains('tags', [tag])

  const { data, error } = await query
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ posts: data })
}

// ── POST — create / upsert post (bot) ────────────────────────────────────────
export async function POST(req: NextRequest) {
  const apiKey = req.headers.get('x-api-key')
  if (!apiKey || apiKey !== process.env.BLOG_API_KEY) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  let body: any
  try { body = await req.json() } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const { slug, title, content, excerpt, tags, author, coverUrl, published, publishedAt } = body

  if (!slug || !title || !content) {
    return NextResponse.json({ error: 'slug, title, and content are required' }, { status: 400 })
  }

  const supabase = adminClient()
  const { data, error } = await supabase
    .from('blog_posts')
    .upsert({
      slug,
      title,
      content,
      excerpt:      excerpt      ?? null,
      tags:         tags         ?? [],
      author:       author       ?? 'MirrorSpeed',
      cover_url:    coverUrl     ?? null,
      published:    published    ?? true,
      published_at: publishedAt  ?? new Date().toISOString(),
      updated_at:   new Date().toISOString(),
    }, { onConflict: 'slug' })
    .select('id, slug, title, published_at')
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ post: data }, { status: 201 })
}
