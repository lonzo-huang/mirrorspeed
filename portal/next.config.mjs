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
}

export default nextConfig
