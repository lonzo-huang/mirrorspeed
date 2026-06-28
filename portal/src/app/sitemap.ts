import type { MetadataRoute } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

/**
 * Dynamic XML sitemap — Next.js serves this at /sitemap.xml.
 * Add new public routes here when you publish them.
 */
export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date()

  const routes: Array<{ path: string; priority: number; changeFrequency: MetadataRoute.Sitemap[number]['changeFrequency'] }> = [
    { path: '',           priority: 1.0, changeFrequency: 'weekly'  },
    { path: '/cn',        priority: 0.95, changeFrequency: 'weekly' },
    { path: '/en',        priority: 0.95, changeFrequency: 'weekly' },
    { path: '/download',  priority: 0.9, changeFrequency: 'weekly'  },
    { path: '/pricing',   priority: 0.9, changeFrequency: 'weekly'  },
    { path: '/servers',   priority: 0.8, changeFrequency: 'daily'   },
    { path: '/blog',      priority: 0.8, changeFrequency: 'daily'   },
    { path: '/help',      priority: 0.7, changeFrequency: 'monthly' },
    { path: '/support',   priority: 0.7, changeFrequency: 'monthly' },
    { path: '/privacy',   priority: 0.5, changeFrequency: 'yearly'  },
    { path: '/terms',     priority: 0.5, changeFrequency: 'yearly'  },
    { path: '/cookies',   priority: 0.4, changeFrequency: 'yearly'  },
    { path: '/disclaimer',priority: 0.4, changeFrequency: 'yearly'  },
  ]

  return routes.map((r) => ({
    url: `${SITE_URL}${r.path}`,
    lastModified: now,
    changeFrequency: r.changeFrequency,
    priority: r.priority,
    alternates: r.path === '' || r.path === '/cn' || r.path === '/en'
      ? {
          languages: {
            en:        `${SITE_URL}/en`,
            'zh-CN':   `${SITE_URL}/cn`,
            'x-default': SITE_URL,
          },
        }
      : undefined,
  }))
}
