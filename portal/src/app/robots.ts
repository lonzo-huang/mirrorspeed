import type { MetadataRoute } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

/**
 * Robots.txt — Next.js serves this at /robots.txt.
 * Public marketing pages indexed; private API + dashboard + admin disallowed.
 */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: '*',
        allow: ['/'],
        disallow: [
          '/api/',
          '/admin',
          '/admin/',
          '/dashboard',
          '/dashboard/',
          '/billing',
          '/devices',
          '/login',
          '/signup',
          '/og/',          // internal OG-render route (the PNG is fine, the dynamic route is internal)
          '/cn.html',      // crawlers should read /cn instead; html is for sharing only
          '/en.html',
        ],
        // Crawl-delay seconds — friendly to small servers, ignored by Googlebot
        crawlDelay: 1,
      },
      // Allow major search engines full speed
      { userAgent: 'Googlebot',  allow: '/' },
      { userAgent: 'Bingbot',    allow: '/' },
      { userAgent: 'DuckDuckBot',allow: '/' },
      // Block aggressive AI training crawlers from private routes (optional — comment out if you WANT them to index your marketing pages)
      { userAgent: 'GPTBot',          allow: '/', disallow: ['/api/', '/admin', '/dashboard'] },
      { userAgent: 'ClaudeBot',       allow: '/', disallow: ['/api/', '/admin', '/dashboard'] },
      { userAgent: 'PerplexityBot',   allow: '/', disallow: ['/api/', '/admin', '/dashboard'] },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  }
}
