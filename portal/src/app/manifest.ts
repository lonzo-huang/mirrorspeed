import type { MetadataRoute } from 'next'

/**
 * PWA Web App Manifest — Next.js serves this at /manifest.webmanifest.
 * Tells browsers / OS this is an installable web app.
 */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name:             'MirrorSpeed — Fast VPN',
    short_name:       'MirrorSpeed',
    description:      'High-speed VPN with proprietary UDP engine, unlimited speed, and a free forever tier.',
    start_url:        '/',
    display:          'standalone',
    background_color: '#06090E',
    theme_color:      '#06090E',
    orientation:      'portrait',
    categories:       ['utilities', 'productivity'],
    lang:             'en',
    icons: [
      { src: '/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
      { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' },
    ],
  }
}
