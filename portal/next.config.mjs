/** @type {import('next').NextConfig} */
const nextConfig = {
  eslint: {
    // Lint errors are checked locally; skip during Vercel builds
    ignoreDuringBuilds: true,
  },
  typescript: {
    // Type errors are checked locally; skip during Vercel builds
    ignoreBuildErrors: true,
  },
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'lh3.googleusercontent.com' },
      { protocol: 'https', hostname: '*.gravatar.com' },
    ],
  },
  experimental: {
    serverActions: { allowedOrigins: ['localhost:3000'] },
  },
  async redirects() {
    return [
      // 博客已迁到子域名 blog.mirrorspeed.com（A 方案）。
      // 旧的 /blog 及其子路径 301 跳到子域名首页（旧 slug 与新 WP slug 不同，不逐篇映射）。
      { source: '/blog',        destination: 'https://blog.mirrorspeed.com/', permanent: true },
      { source: '/blog/:path*', destination: 'https://blog.mirrorspeed.com/', permanent: true },
    ]
  },
}

export default nextConfig
