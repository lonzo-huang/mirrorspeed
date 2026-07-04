import { MetadataRoute } from 'next'

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: '*',
        allow: '/',
        disallow: ['/admin', '/dashboard', '/auth', '/login', '/signup'],
      },
    ],
    sitemap: 'https://www.mirrorspeed.com/sitemap.xml',
  }
}
