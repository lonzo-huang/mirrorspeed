import type { Metadata } from 'next'
import { NODE_COUNTRIES } from '@/lib/product'

const SITE_URL = 'https://www.mirrorspeed.com'

// 这一页显示的是实时节点数据。描述里写死「20+ 节点」会和正文里读出来的真实数量
// 直接打架（页面显示 8 个地区），同一页自相矛盾对搜索和 AI 都是减分项。
// 这里只讲覆盖的国家与页面提供的信息，不写会过期的数字。
export const metadata: Metadata = {
  title: 'VPN Server Network — Live Latency and Load',
  description:
    `MirrorSpeed nodes in ${NODE_COUNTRIES.en.join(', ')}. See live latency, load and capacity for each one, and pick a server automatically or by hand.`,
  alternates: {
    canonical: `${SITE_URL}/servers`,
    languages: { en: `${SITE_URL}/servers`, 'zh-CN': `${SITE_URL}/cn/servers` },
  },
  openGraph: {
    title: 'VPN Server Network — Live Latency and Load',
    description: 'Live latency, load and capacity for every MirrorSpeed node.',
    url: `${SITE_URL}/servers`,
  },
}

export default function ServersLayout({ children }: { children: React.ReactNode }) {
  return children
}
