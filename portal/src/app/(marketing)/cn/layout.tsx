import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  // title.absolute：标题自带品牌名，避免再被 '%s | MirrorSpeed' 模板追加一次。
  title: { absolute: '镜速加速器 MirrorSpeed — 永久免费，智能分流不限速' },
  // 中文描述控制在 80 字内，超出会在搜索结果里被截断。
  description:
    '镜速加速器是支持安卓、Windows、鸿蒙的网络加速器。永久免费套餐每天赠时长，' +
    '付费每月最低 ¥8，单用户最高 1000 Mbps，不记录上网日志。',
  // 不再输出 meta keywords：搜索引擎不看，只会暴露关键词策略。
  alternates: {
    canonical: `${SITE_URL}/cn`,
    languages: {
      en:          SITE_URL,
      'zh-CN':     `${SITE_URL}/cn`,
      'x-default': SITE_URL,
    },
  },
  openGraph: {
    title:    'MirrorSpeed 镜速加速器 — 永久免费，极速连接全球',
    description: '永久免费 · 智能分流 · 国内直连 · 境外加速 · 多国节点零日志 · 单用户 1000 Mbps 不限速',
    siteName: 'MirrorSpeed',
    url:      `${SITE_URL}/cn`,
    locale:   'zh_CN',
    type:     'website',
    images:   [{ url: '/og-cn.png', width: 1200, height: 630, alt: 'MirrorSpeed 镜速加速器 — 永久免费，极速连接全球' }],
  },
  twitter: {
    card:    'summary_large_image',
    title:   'MirrorSpeed 镜速加速器 — 永久免费，极速连接全球',
    description: '永久免费 · 自研加速引擎 · UDP 协议封装 · 智能分流 · 多国节点零日志',
    images:  ['/og-cn.png'],
  },
}

export default function CnLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      {/* 中文页的 <html lang> 修正。
          App Router 里 <html> 只能由根布局输出，而根布局要读路径就得用 headers()，
          那会让全站退出静态渲染（营销页全部变成每次请求现算）——代价远大于收益。
          折中：水合前用内联脚本改写 lang。Googlebot/Bingbot 会执行 JS，能读到 zh-CN；
          不执行 JS 的爬虫则依靠 hreflang 与正文语言判断，这两个本就是更强的信号。 */}
      <script
        dangerouslySetInnerHTML={{
          __html: `document.documentElement.lang='zh-CN';`,
        }}
      />
      {children}
    </>
  )
}
