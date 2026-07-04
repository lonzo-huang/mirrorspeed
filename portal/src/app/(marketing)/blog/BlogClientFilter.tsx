'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { useI18n } from '@/lib/i18n'

interface Post {
  id: string
  slug: string
  title: string
  excerpt: string | null
  tags: string[]
  author: string
  cover_url: string | null
  published_at: string
}

export function BlogClientFilter({ allPosts }: { allPosts: Post[] }) {
  const { lang } = useI18n()
  const [filteredPosts, setFilteredPosts] = useState<Post[]>(allPosts)

  useEffect(() => {
    if (lang === 'zh') {
      setFilteredPosts(allPosts.filter(post => post.slug.endsWith('-cn')))
    } else {
      setFilteredPosts(allPosts.filter(post => !post.slug.endsWith('-cn')))
    }
  }, [lang, allPosts])

  if (filteredPosts.length === 0) {
    return (
      <div className="text-center py-24 text-app-muted">
        <p className="text-5xl mb-4">✍️</p>
        <p className="text-lg">No posts yet — check back soon.</p>
      </div>
    )
  }

  return (
    <div className="space-y-8">
      {filteredPosts.map(post => (
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
  )
}
