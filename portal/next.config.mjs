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

      // 中文教程并到 /cn/ 之下，与其余中文页网址结构一致（/cn/pricing、/cn/help…）。
      // 旧网址 301 保留：之前 canonical 被错误指向首页，它们从未被收录，
      // 但站外/App 内可能已有链接。
      { source: '/tutorials',        destination: '/cn/tutorials',        permanent: true },
      { source: '/tutorials/:slug',  destination: '/cn/tutorials/:slug',  permanent: true },
    ]
  },
}

export default nextConfig
