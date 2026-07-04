import { notFound }  from 'next/navigation'
import Link           from 'next/link'
import { LandingChrome } from '@/components/landing/LandingPage'
import { createClient } from '@supabase/supabase-js'
import type { Metadata } from 'next'

interface Post {
  id:           string
  slug:         string
  title:        string
  excerpt:      string | null
  content:      string
  tags:         string[]
  author:       string
  cover_url:    string | null
  published_at: string
}

async function getPost(slug: string): Promise<Post | null> {
  try {
    const base = process.env.NEXT_PUBLIC_APP_URL
      ?? (process.env.VERCEL_URL
        ? `https://${process.env.VERCEL_URL}`
        : 'http://localhost:3000')
    // Fetch from Supabase directly via service role to get single post by slug
    const { createClient } = await import('@supabase/supabase-js')
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
      { auth: { persistSession: false } }
    )
    const { data } = await supabase
      .from('blog_posts')
      .select('*')
      .eq('slug', slug)
      .eq('published', true)
      .single()
    return data ?? null
  } catch {
    return null
  }
}

export async function generateMetadata(
  { params }: { params: { slug: string } }
): Promise<Metadata> {
  const post = await getPost(params.slug)
  if (!post) return { title: 'Post not found' }
  return {
    title:       `${post.title} — MirrorSpeed Blog`,
    description: post.excerpt ?? post.title,
    openGraph: {
      title:       post.title,
      description: post.excerpt ?? '',
      images:      post.cover_url ? [post.cover_url] : [],
    },
  }
}

// Simple markdown-like renderer for plain text / basic markdown
function renderContent(content: string) {
  // If content looks like HTML, render it directly
  if (content.trimStart().startsWith('<')) {
    return <div className="prose-content" dangerouslySetInnerHTML={{ __html: content }} />
  }
  // Otherwise render as plain pre-formatted text
  return (
    <div className="text-sm text-app-secondary leading-relaxed whitespace-pre-wrap">
      {content}
    </div>
  )
}

export async function generateStaticParams() {
  try {
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
      { auth: { persistSession: false } }
    )
    const { data: posts } = await supabase
      .from('blog_posts')
      .select('slug')
      .eq('published', true)
    return (posts ?? []).map(post => ({ slug: post.slug }))
  } catch {
    return []
  }
}

export default async function BlogPostPage({ params }: { params: { slug: string } }) {
  const post = await getPost(params.slug)
  if (!post) notFound()

  return (
    <LandingChrome>
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">

          {/* Back link */}
          <Link href="/blog" className="inline-flex items-center gap-1.5 text-sm text-app-muted hover:text-accent-cyan transition-colors mb-8">
            ← Blog
          </Link>

          {/* Tags */}
          {post.tags.length > 0 && (
            <div className="flex flex-wrap gap-2 mb-4">
              {post.tags.map(tag => (
                <span key={tag} className="text-[10px] font-bold uppercase tracking-widest text-accent-cyan bg-[var(--accent-cyan-glow)] rounded-full px-2.5 py-0.5">
                  {tag}
                </span>
              ))}
            </div>
          )}

          {/* Title */}
          <h1 className="font-heading text-3xl md:text-5xl font-black tracking-tighter mb-4">
            <span className="text-gradient-cyan">{post.title}</span>
          </h1>

          {/* Meta */}
          <div className="flex items-center gap-3 text-sm text-app-muted mb-8 pb-8 border-b border-app-subtle">
            <span>{post.author}</span>
            <span>·</span>
            <time dateTime={post.published_at}>
              {new Date(post.published_at).toLocaleDateString('en-US', {
                year: 'numeric', month: 'long', day: 'numeric',
              })}
            </time>
          </div>

          {/* Cover image */}
          {post.cover_url && (
            <div className="rounded-2xl overflow-hidden mb-10">
              <img src={post.cover_url} alt={post.title} className="w-full object-cover" />
            </div>
          )}

          {/* Content */}
          <div className="glass-panel rounded-2xl p-6 md:p-8">
            {renderContent(post.content)}
          </div>

        </article>
      </main>
    </LandingChrome>
  )
}
