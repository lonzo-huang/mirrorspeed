import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'lh3.googleusercontent.com' },  // Google avatar
      { protocol: 'https', hostname: '*.gravatar.com' },
    ],
  },
  // Stripe 和 supabase 需要 server actions
  experimental: {
    serverActions: { allowedOrigins: ['localhost:3000'] },
  },
}

export default nextConfig
