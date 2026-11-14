import type { Metadata } from 'next'
import { TUTORIALS } from '@/lib/tutorials'

// 教程区为纯中文内容（唯一的中文内容集群），此前无 metadata → 被当成首页副本，
// 完全无法收录。这里给出中文 title/description + 自身 canonical + hreflang。
export const metadata: Metadata = {
  // 中文标题用 absolute：避免被英文模板追加成「…教程 | MirrorSpeed」中英混排。
  title: { absolute: '镜速加速器使用教程 — Windows / 安卓 / 鸿蒙 / iOS 安装与连接' },
  description:
    `镜速加速器图文教程：Windows 11、Windows 7 安装与连接，安卓安装与后台保活，华为鸿蒙机型设置，iOS 无法使用排查，连不上网怎么办。共 ${TUTORIALS.length} 篇，按设备选择。`,
  alternates: {
    canonical: '/tutorials',
    languages: { 'zh-CN': '/tutorials' },
  },
  openGraph: {
    url: '/tutorials',
    title: '镜速加速器使用教程 — 安装、连接与故障排查',
    description: '按设备查找图文教程：Windows、安卓、鸿蒙、iOS 的安装、连接与常见问题排查。',
    locale: 'zh_CN',
    images: [{ url: '/og-cn.png', width: 1200, height: 630, alt: '镜速加速器使用教程' }],
  },
}

export default function TutorialsLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      {/* 教程区为纯中文内容，水合前把 <html lang> 改为 zh-CN（原因见 /cn/layout.tsx 注释）。 */}
      <script dangerouslySetInnerHTML={{ __html: `document.documentElement.lang='zh-CN';` }} />
      {children}
    </>
  )
}
