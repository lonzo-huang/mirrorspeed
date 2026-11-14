import { MetadataRoute } from 'next'
import { TUTORIALS } from '@/lib/tutorials'

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
    { url: `${SITE_URL}/servers`,    priority: 0.7, changeFrequency: 'daily'   },
    { url: `${SITE_URL}/support`,    priority: 0.5, changeFrequency: 'monthly' },
    { url: `${SITE_URL}/about`,      priority: 0.6, changeFrequency: 'monthly' },

    // 中文教程集群（原创内容，搜索流量主力）
    { url: `${SITE_URL}/tutorials`,  priority: 0.8, changeFrequency: 'monthly' },
    ...TUTORIALS.map(t => ({
      url: `${SITE_URL}/tutorials/${t.slug}`,
      priority: 0.7,
      changeFrequency: 'monthly' as const,
    })),

    // 法律页：收录价值低但属于信任信号，保留在索引内
    { url: `${SITE_URL}/privacy`,    priority: 0.3, changeFrequency: 'yearly'  },
    { url: `${SITE_URL}/terms`,      priority: 0.3, changeFrequency: 'yearly'  },
    { url: `${SITE_URL}/cookies`,    priority: 0.2, changeFrequency: 'yearly'  },
    { url: `${SITE_URL}/disclaimer`, priority: 0.2, changeFrequency: 'yearly'  },
  ]

  return entries.map(e => ({ lastModified: now, ...e }))
}
