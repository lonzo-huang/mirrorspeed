import { MetadataRoute } from 'next'
import { TUTORIALS } from '@/lib/tutorials'
import { USE_CASES } from '@/lib/useCases'

const SITE_URL = 'https://www.mirrorspeed.com'

// 站点地图只列「能直接返回 200 的规范网址」。
// 不再从 Supabase 拉博客文章：/blog 与 /blog/* 已在 next.config 里 301 到
// blog.mirrorspeed.com，把 301 网址放进 sitemap 只会浪费抓取预算并被 GSC 标为错误。
// 博客子域名有自己的 sitemap（WordPress / Rank Math 的 sitemap_index.xml）。

const now = new Date()

// 英文首页与中文首页互为语言版本（`/en` 不列入：它的 canonical 指向 `/`）
const HOME_ALTERNATES = {
  languages: {
    en: SITE_URL,
    'zh-CN': `${SITE_URL}/cn`,
  },
}

export default function sitemap(): MetadataRoute.Sitemap {
  const entries: MetadataRoute.Sitemap = [
    { url: SITE_URL,                 priority: 1.0, changeFrequency: 'weekly',  alternates: HOME_ALTERNATES },
    { url: `${SITE_URL}/cn`,         priority: 0.9, changeFrequency: 'weekly',  alternates: HOME_ALTERNATES },

    // 产品页（中英各一个网址，互为 hreflang 对照）
    ...(['pricing', 'download', 'help'] as const).flatMap(slug => {
      const languages = { en: `${SITE_URL}/${slug}`, 'zh-CN': `${SITE_URL}/cn/${slug}` }
      return [
        { url: `${SITE_URL}/${slug}`,     priority: 0.8, changeFrequency: 'weekly' as const, alternates: { languages } },
        { url: `${SITE_URL}/cn/${slug}`,  priority: 0.8, changeFrequency: 'weekly' as const, alternates: { languages } },
      ]
    }),
    // 注意：/about 与 /support 在下方「信息页与法律页」的成对循环里，别在这里重复列出。
    { url: `${SITE_URL}/servers`,    priority: 0.7, changeFrequency: 'daily',
      alternates: { languages: { en: `${SITE_URL}/servers`, 'zh-CN': `${SITE_URL}/cn/servers` } } },

    // 场景落地页（中英成对，互为 hreflang）
    ...['', 'cn/'].map(prefix => ({
      url: `${SITE_URL}/${prefix}use-cases`,
      priority: 0.7,
      changeFrequency: 'monthly' as const,
      alternates: { languages: { en: `${SITE_URL}/use-cases`, 'zh-CN': `${SITE_URL}/cn/use-cases` } },
    })),
    ...USE_CASES.flatMap(u => {
      const languages = {
        en: `${SITE_URL}/use-cases/${u.slug}`,
        'zh-CN': `${SITE_URL}/cn/use-cases/${u.slug}`,
      }
      return [
        { url: languages.en,      priority: 0.7, changeFrequency: 'monthly' as const, alternates: { languages } },
        { url: languages['zh-CN'], priority: 0.7, changeFrequency: 'monthly' as const, alternates: { languages } },
      ]
    }),

    // 安装指南：英文一页通览，中文是 9 篇图文教程（不是逐篇对译，故 hreflang
    // 指向教程索引而非同名页面）
    { url: `${SITE_URL}/setup`, priority: 0.8, changeFrequency: 'monthly',
      alternates: { languages: { en: `${SITE_URL}/setup`, 'zh-CN': `${SITE_URL}/cn/tutorials` } } },

    // 中文教程集群（原创内容，搜索流量主力）
    { url: `${SITE_URL}/cn/tutorials`,  priority: 0.8, changeFrequency: 'monthly',
      alternates: { languages: { en: `${SITE_URL}/setup`, 'zh-CN': `${SITE_URL}/cn/tutorials` } } },
    ...TUTORIALS.map(t => ({
      url: `${SITE_URL}/cn/tutorials/${t.slug}`,
      priority: 0.7,
      changeFrequency: 'monthly' as const,
    })),

    // 信息页与法律页：中英成对（收录价值低，但属于信任信号）
    ...(
      [
        ['about',      0.6],
        ['support',    0.5],
        ['privacy',    0.3],
        ['terms',      0.3],
        ['cookies',    0.2],
        ['disclaimer', 0.2],
      ] as const
    ).flatMap(([slug, priority]) => {
      const languages = { en: `${SITE_URL}/${slug}`, 'zh-CN': `${SITE_URL}/cn/${slug}` }
      return [
        { url: languages.en,       priority, changeFrequency: 'yearly' as const, alternates: { languages } },
        { url: languages['zh-CN'], priority, changeFrequency: 'yearly' as const, alternates: { languages } },
      ]
    }),
    { url: `${SITE_URL}/cn/servers`, priority: 0.7, changeFrequency: 'daily' as const,
      alternates: { languages: { en: `${SITE_URL}/servers`, 'zh-CN': `${SITE_URL}/cn/servers` } } },
    { url: `${SITE_URL}/disclaimer`, priority: 0.2, changeFrequency: 'yearly'  },
  ]

  return entries.map(e => ({ lastModified: now, ...e }))
}
