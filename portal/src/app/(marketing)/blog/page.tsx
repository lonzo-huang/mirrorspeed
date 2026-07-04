import { createClient } from '@supabase/supabase-js'
import { LandingChrome } from '@/components/landing/LandingPage'
import { BlogClientFilter } from './BlogClientFilter'

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
  const allPosts = await getPosts()

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

          <BlogClientFilter allPosts={allPosts} />

        </div>
      </main>
    </LandingChrome>
  )
}
