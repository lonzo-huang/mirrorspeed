import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '加速节点网络 — 实时延迟与负载' },
  description:
    '查看镜速加速器各节点的实时延迟、负载与容量，覆盖美国、德国、西班牙、日本、新加坡与香港。可自动择优，也可手动指定。',
  alternates: {
    canonical: `${SITE_URL}/cn/servers`,
    languages: { en: `${SITE_URL}/servers`, 'zh-CN': `${SITE_URL}/cn/servers` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/servers`,
    title: '加速节点网络 — 实时延迟与负载',
    description: '查看镜速加速器各节点的实时延迟、负载与容量，覆盖美国、德国、西班牙、日本、新加坡与香港。可自动择优，也可手动指定。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '加速节点网络 — 实时延迟与负载' }],
  },
}

export default function CnServersLayout({ children }: { children: React.ReactNode }) {
  return children
}
