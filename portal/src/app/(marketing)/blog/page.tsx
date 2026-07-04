import Link           from 'next/link'
import { createClient } from '@supabase/supabase-js'
import { LandingChrome } from '@/components/landing/LandingPage'

interface Post {
  id:           string
  slug:         string
  title:        string
  excerpt:      string | null
  tags:         string[]
  author:       string
  cover_url:    string | null
  published_at: string
}

async function getPosts(lang?: string): Promise<Post[]> {
  try {
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
      { auth: { persistSession: false } }
    )

    const { data } = await supabase
      .from('blog_posts')
      .select('id, slug, title, excerpt, tags, author, cover_url, published_at')
      .eq('published', true)
      .order('published_at', { ascending: false })
      .limit(50)

    // Client-side filtering by language if needed
    if (lang === 'zh' && data) {
      return data.filter(post => post.slug.endsWith('-cn'))
    } else if (lang === 'en' && data) {
      return data.filter(post => !post.slug.endsWith('-cn'))
    }

    return data ?? []
  } catch {
    return []
  }
}

export const revalidate = 300 // ISR: revalidate every 5 min

export const metadata = {
  title:       'Blog — MirrorSpeed',
  description: 'VPN tips, privacy guides, and global network updates from MirrorSpeed.',
}

export default async function BlogPage({ searchParams }: { searchParams: { lang?: string } }) {
  const lang = searchParams?.lang || 'en'
  const posts = await getPosts(lang)

  return (
    <LandingChrome>
      <main className="px-6 pb-24">
        <div className="max-w-4xl mx-auto">

          {/* Header */}
          <div className="mb-14 text-center">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">// Blog</span>
            <h1 className="font-heading text-5xl md:text-6xl font-black tracking-tighter mb-4">
              <span className="text-gradient-cyan">MirrorSpeed Blog</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-xl mx-auto">
              VPN guides, privacy tips, and network updates.
            </p>
          </div>

          {posts.length === 0 ? (
            <div className="text-center py-24 text-app-muted">
              <p className="text-5xl mb-4">✍️</p>
              <p className="text-lg">No posts yet — check back soon.</p>
            </div>
          ) : (
            <div className="space-y-8">
              {posts.map(post => (
                <Link key={post.id} href={`/blog/${post.slug}`} className="group block">
                  <article className="glass-panel rounded-2xl overflow-hidden hover:border-[var(--accent-cyan)] transition-colors">
                    <div className="md:flex gap-6">
                      {post.cover_url && (
                        <div className="md:w-1/3 aspect-video md:aspect-auto overflow-hidden flex-shrink-0">
                          <img
                            src={post.cover_url}
                            alt={post.title}
                            className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                          />
                        </div>
                      )}
                      <div className="p-6 flex-1 flex flex-col justify-between">
                        {post.tags.length > 0 && (
                          <div className="flex flex-wrap gap-2 mb-3">
                            {post.tags.slice(0, 2).map(tag => (
                              <span key={tag} className="text-[10px] font-bold uppercase tracking-widest text-accent-cyan bg-[var(--accent-cyan-glow)] rounded-full px-2.5 py-0.5">
                                {tag}
                              </span>
                            ))}
                          </div>
                        )}
                        <div>
                          <h2 className="text-2xl font-bold mb-2 text-app-primary group-hover:text-accent-cyan transition-colors line-clamp-2">
                            {post.title}
                          </h2>
                          {post.excerpt && (
                            <p className="text-base text-app-secondary line-clamp-2 mb-4">{post.excerpt}</p>
                          )}
                        </div>
                        <div className="flex items-center justify-between text-sm text-app-muted pt-2 border-t border-app-subtle">
                          <span className="font-medium">{post.author}</span>
                          <time dateTime={post.published_at}>
                            {new Date(post.published_at).toLocaleDateString('en-US', {
                              year: 'numeric', month: 'short', day: 'numeric',
                            })}
                          </time>
                        </div>
                      </div>
                    </div>
                  </article>
                </Link>
              ))}
            </div>
          )}

        </div>
      </main>
    </LandingChrome>
  )
}
