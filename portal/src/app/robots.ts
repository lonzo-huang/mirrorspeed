import { MetadataRoute } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

// 私有/无收录价值的路径：登录态页面、接口、OAuth 回调。
const DISALLOW = ['/admin', '/dashboard', '/auth', '/login', '/signup', '/api/']

// 主流 AI 抓取器。默认全放行其实已经允许它们抓，但显式列出有两个好处：
//   1. 明确表态允许训练/检索抓取，避免某些抓取器在「没有明确许可」时保守跳过；
//   2. 日后若要对某家收紧，改这一处即可。
const AI_CRAWLERS = [
  'GPTBot',              // OpenAI 训练
  'OAI-SearchBot',       // ChatGPT 搜索索引
  'ChatGPT-User',        // ChatGPT 实时取页
  'ClaudeBot',           // Anthropic 训练
  'Claude-User',         // Claude 实时取页
  'Claude-SearchBot',    // Claude 搜索索引
  'PerplexityBot',       // Perplexity 索引
  'Perplexity-User',     // Perplexity 实时取页
  'Google-Extended',     // Gemini / Vertex 训练（不影响 Google 搜索收录）
  'Applebot-Extended',   // Apple Intelligence
  'Bingbot',             // Bing + Copilot
  'DuckAssistBot',
  'cohere-ai',
  'meta-externalagent',
]

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: '*', allow: '/', disallow: DISALLOW },
      ...AI_CRAWLERS.map(ua => ({ userAgent: ua, allow: '/', disallow: DISALLOW })),
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  }
}
