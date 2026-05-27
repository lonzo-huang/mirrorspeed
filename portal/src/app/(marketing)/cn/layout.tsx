import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: '镜速加速器 – 智能分流 VPN，国内直连境外加速',
  description: '镜速加速器专为国内用户设计：中国 IP 直连，境外流量走 VPN，每日免费 500 MB，Android 一键安装。',
  keywords: ['镜速加速器', 'VPN', '科学上网', '加速器', '翻墙', 'WireGuard', '智能分流', '国内直连'],
  openGraph: {
    title:    '镜速加速器',
    description: '智能分流 VPN，国内直连境外加速，每日免费 500 MB',
    siteName: '镜速加速器',
    locale:   'zh_CN',
    type:     'website',
  },
}

export default function CnLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
