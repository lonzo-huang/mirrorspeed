import type { Metadata } from 'next'

const SITE_URL = 'https://www.mirrorspeed.com'

export const metadata: Metadata = {
  title: { absolute: '镜速加速器价格 — 永久免费套餐，付费每月最低 ¥8' },
  description:
    '镜速加速器套餐与价格：永久免费套餐每天赠送时长、无需信用卡；付费套餐去广告、不限时长，' +
    '单用户最高 1000 Mbps，一个账号最多 8 台设备。月付 ¥24，年付每月 ¥9，两年付每月 ¥8。支持支付宝、微信与信用卡，7 天无理由退款。',
  alternates: {
    canonical: `${SITE_URL}/cn/pricing`,
    languages: { en: `${SITE_URL}/pricing`, 'zh-CN': `${SITE_URL}/cn/pricing` },
  },
  openGraph: {
    url: `${SITE_URL}/cn/pricing`,
    title: '镜速加速器价格 — 永久免费，付费每月最低 ¥8',
    description: '永久免费套餐 · 付费每月最低 ¥8 · 不限速 · 8 台设备 · 7 天无理由退款',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '镜速加速器价格' }],
  },
}

export default function CnPricingLayout({ children }: { children: React.ReactNode }) {
  return children
}
