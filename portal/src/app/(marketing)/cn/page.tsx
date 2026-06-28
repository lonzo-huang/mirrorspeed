import LandingPage from '@/components/landing/LandingPage'

// 中文主页：锁定中文渲染（cn/layout.tsx 提供中文 SEO 元数据）。
export default function CnHomePage() {
  return <LandingPage forcedLang="zh" />
}
