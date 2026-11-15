import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '镜速VPN帮助中心 — 连接、节点、免费时长与会员' },
  description:
    '镜速VPN常见问题：如何连接、如何选择节点、免费时长怎么算、看广告换时长、' +
    '智能分流与全局模式的区别、连上了但网页打不开怎么办、如何升级与管理订阅。',
  alternates: {
    canonical: `${SITE_URL}/cn/help`,
    languages: { en: `${SITE_URL}/help`, 'zh-CN': `${SITE_URL}/cn/help` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/help`,
    title: '镜速VPN帮助中心',
    description: '连接、节点选择、免费时长、会员订阅等常见问题解答。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '镜速VPN帮助中心' }],
  },
}

export default function CnHelpLayout({ children }: { children: React.ReactNode }) {
  return children
}
