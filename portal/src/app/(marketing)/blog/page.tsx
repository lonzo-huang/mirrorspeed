import Link           from 'next/link'
import { createClient } from '@supabase/supabase-js'
import { SiteNav }    from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'

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

async function getPosts(): Promise<Post[]> {
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

export default async function BlogPage() {
  const posts = await getPosts()

  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <div className="max-w-4xl mx-auto">

          {/* Header */}
          <div className="mb-14">
            <p className="text-[11px] font-mono uppercase tracking-widest text-muted-foreground mb-3">MirrorSpeed</p>
            <h1 className="text-4xl md:text-5xl font-bold tracking-tighter mb-4">Blog</h1>
            <p className="text-muted-foreground text-lg">
              VPN guides, privacy tips, and network updates.
            </p>
          </div>

          {posts.length === 0 ? (
            <div className="text-center py-24 text-muted-foreground">
              <p className="text-5xl mb-4">✍️</p>
              <p className="text-lg">No posts yet — check back soon.</p>
            </div>
          ) : (
            <div className="grid gap-6 md:grid-cols-2">
              {posts.map(post => (
                <Link key={post.id} href={`/blog/${post.slug}`} className="group block">
                  <article className="glass-panel rounded-2xl overflow-hidden h-full hover:border-mirror/30 transition-colors">
                    {post.cover_url && (
                      <div className="aspect-[16/7] overflow-hidden">
                        <img
                          src={post.cover_url}
                          alt={post.title}
                          className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                        />
                      </div>
                    )}
                    <div className="p-6">
                      {post.tags.length > 0 && (
                        <div className="flex flex-wrap gap-2 mb-3">
                          {post.tags.slice(0, 3).map(tag => (
                            <span key={tag} className="text-[10px] font-bold uppercase tracking-widest text-mirror bg-mirror/10 rounded-full px-2.5 py-0.5">
                              {tag}
                            </span>
                          ))}
                        </div>
                      )}
                      <h2 className="text-lg font-bold mb-2 group-hover:text-mirror transition-colors line-clamp-2">
                        {post.title}
                      </h2>
                      {post.excerpt && (
                        <p className="text-sm text-muted-foreground line-clamp-3 mb-4">{post.excerpt}</p>
                      )}
                      <div className="flex items-center justify-between text-xs text-muted-foreground mt-auto pt-2 border-t border-border">
                        <span>{post.author}</span>
                        <time dateTime={post.published_at}>
                          {new Date(post.published_at).toLocaleDateString('en-US', {
                            year: 'numeric', month: 'short', day: 'numeric',
                          })}
                        </time>
                      </div>
                    </div>
                  </article>
                </Link>
              ))}
            </div>
          )}

        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
