import { notFound }  from 'next/navigation'
import Link           from 'next/link'
import { LandingChrome } from '@/components/landing/LandingPage'
import { createClient } from '@supabase/supabase-js'
import parse from 'html-react-parser'
import hljs from 'highlight.js'
import 'highlight.js/styles/atom-one-dark.css'
import './blog.css'
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

async function getPost(slug: string, lang?: string): Promise<Post | null> {
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

    let query = supabase
      .from('blog_posts')
      .select('*')
      .eq('slug', slug)
      .eq('published', true)

    // Only filter by language if lang is explicitly specified
    if (lang === 'zh') {
      query = query.eq('language', 'zh')
    } else if (lang === 'en') {
      query = query.eq('language', 'en')
    }
    // If no lang specified, just get the post regardless of language

    const { data } = await query.single()
    return data ?? null
  } catch {
    return null
  }
}

function renderContent(content: string) {
  if (!content) return null

  // Parse HTML and enhance it
  if (content.trimStart().startsWith('<')) {
    const sanitized = sanitizeAndEnhanceHtml(content)
    return (
      <div className="prose-blog">
        {parse(sanitized, {
          replace: (node: any) => {
            if (node.type === 'tag') {
              if (node.name === 'img') {
                return (
                  <figure key={node.attribs.src} className="my-6">
                    <img
                      src={node.attribs.src}
                      alt={node.attribs.alt || 'Blog image'}
                      className="w-full rounded-lg"
                      loading="lazy"
                    />
                    {node.attribs.alt && <figcaption className="text-sm text-app-muted text-center mt-2">{node.attribs.alt}</figcaption>}
                  </figure>
                )
              }
              if (node.name === 'code' && node.parent?.name === 'pre') {
                const code = node.children?.[0]?.data || ''
                const lang = node.attribs.class?.replace('language-', '') || 'text'
                try {
                  const highlighted = hljs.highlight(code, { language: lang, ignoreIllegals: true }).value
                  return (
                    <pre key={code} className="bg-[#282c34] rounded-lg p-4 overflow-x-auto my-4">
                      <code dangerouslySetInnerHTML={{ __html: highlighted }} className={`hljs language-${lang}`} />
                    </pre>
                  )
                } catch {
                  return <pre className="bg-[#282c34] rounded-lg p-4 text-sm my-4"><code>{code}</code></pre>
                }
              }
            }
          }
        })}
      </div>
    )
  }

  return <div className="text-app-secondary leading-relaxed">{content}</div>
}

function sanitizeAndEnhanceHtml(html: string): string {
  return html
    .replace(/<p>/g, '<p class="mb-4 leading-relaxed">')
    .replace(/<h1>/g, '<h1 class="text-3xl font-bold mt-8 mb-4 text-foreground">')
    .replace(/<h2>/g, '<h2 class="text-2xl font-bold mt-8 mb-4 text-foreground">')
    .replace(/<h3>/g, '<h3 class="text-xl font-bold mt-6 mb-3 text-foreground">')
    .replace(/<h4>/g, '<h4 class="text-lg font-bold mt-6 mb-3 text-foreground">')
    .replace(/<h5>/g, '<h5 class="font-bold mt-4 mb-2 text-foreground">')
    .replace(/<h6>/g, '<h6 class="font-bold mt-4 mb-2 text-foreground">')
    .replace(/<li>/g, '<li class="ml-6 mb-2 list-disc">')
    .replace(/<ul>/g, '<ul class="my-4">')
    .replace(/<ol>/g, '<ol class="my-4">')
    .replace(/<blockquote>/g, '<blockquote class="border-l-4 border-accent-cyan pl-4 italic my-4 text-app-secondary">')
    .replace(/<table>/g, '<table class="w-full border-collapse border border-app-subtle my-4">')
    .replace(/<td>/g, '<td class="border border-app-subtle px-3 py-2">')
    .replace(/<th>/g, '<th class="border border-app-subtle px-3 py-2 bg-app-subtle font-bold">')
    .replace(/<img /g, '<img class="max-w-full h-auto rounded-lg my-4" ')
    .replace(/<a /g, '<a class="text-accent-cyan hover:underline" ')
    .replace(/<code[^>]*>/g, '<code class="bg-[#1e1e1e] px-2 py-1 rounded text-sm font-mono text-accent-cyan">')
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

export async function generateMetadata(
  { params, searchParams }: { params: { slug: string }; searchParams: { lang?: string } }
): Promise<Metadata> {
  const lang = searchParams?.lang || 'en'
  const post = await getPost(params.slug, lang)
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

export default async function BlogPostPage({ params, searchParams }: { params: { slug: string }; searchParams: { lang?: string } }) {
  const lang = searchParams?.lang || 'en'
  const post = await getPost(params.slug, lang)
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
