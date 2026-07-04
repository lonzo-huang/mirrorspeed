import { MetadataRoute } from 'next'
import { createClient } from '@supabase/supabase-js'

const SITE_URL = 'https://www.mirrorspeed.com'

export const revalidate = 3600 // ISR: revalidate every hour to catch new blog posts

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  try {
    // Fetch published blog posts
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
      { auth: { persistSession: false } }
    )
    const { data: posts } = await supabase
      .from('blog_posts')
      .select('slug, published_at, updated_at')
      .eq('published', true)
      .order('published_at', { ascending: false })

    const blogEntries: MetadataRoute.Sitemap = (posts ?? []).map(post => ({
      url: `${SITE_URL}/blog/${post.slug}`,
      lastModified: post.updated_at || post.published_at,
      priority: 0.7,
    }))

    // Static pages
    const staticPages: MetadataRoute.Sitemap = [
      {
        url: SITE_URL,
        lastModified: new Date(),
        priority: 1.0,
      },
      {
        url: `${SITE_URL}/blog`,
        lastModified: new Date(),
        priority: 0.9,
      },
      {
        url: `${SITE_URL}/pricing`,
        lastModified: new Date(),
        priority: 0.8,
      },
      {
        url: `${SITE_URL}/download`,
        lastModified: new Date(),
        priority: 0.8,
      },
      {
        url: `${SITE_URL}/help`,
        lastModified: new Date(),
        priority: 0.6,
      },
    ]

    return [...staticPages, ...blogEntries]
  } catch (error) {
    console.error('[sitemap] Error fetching posts:', error)
    return [
      {
        url: SITE_URL,
        lastModified: new Date(),
        priority: 1.0,
      },
    ]
  }
}
