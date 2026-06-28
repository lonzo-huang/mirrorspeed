import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: 'MirrorSpeed 镜速加速器 — 智能分流 VPN，无惧干扰，极速连接全球',
  description: 'MirrorSpeed 镜速 — 自研加速引擎，UDP 协议封装，智能分流：国内直连、境外加速。单用户最高 1000 Mbps 不限速，多国节点零日志，永久免费试用。',
  keywords: [
    '镜速加速器', 'MirrorSpeed', 'mirrorspeed',
    '网络加速', '低延迟', '加速器', '智能分流', '国内直连',
    '流媒体解锁', '游戏加速', 'AI 加速', 'ChatGPT 加速',
    '免费试用', '全球节点',
  ],
  alternates: {
    canonical: `${SITE_URL}/cn`,
    languages: {
      en:        `${SITE_URL}/en`,
      'zh-CN':   `${SITE_URL}/cn`,
      'x-default': SITE_URL,
    },
  },
  openGraph: {
    title:    'MirrorSpeed 镜速加速器 — 无惧干扰，极速连接全球',
    description: '智能分流 · 国内直连 · 境外加速 · 永久免费试用 · 多国节点零日志 · 单用户 1000 Mbps',
    siteName: 'MirrorSpeed',
    url:      `${SITE_URL}/cn`,
    locale:   'zh_CN',
    type:     'website',
    images:   [{ url: '/og-cn.png', width: 1200, height: 630, alt: 'MirrorSpeed — 无惧干扰，极速连接全球' }],
  },
  twitter: {
    card:    'summary_large_image',
    title:   'MirrorSpeed 镜速加速器 — 无惧干扰，极速连接全球',
    description: '自研加速引擎 · UDP 协议封装 · 智能分流 · 永久免费试用 · 多国节点零日志',
    images:  ['/og-cn.png'],
  },
}

export default function CnLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
