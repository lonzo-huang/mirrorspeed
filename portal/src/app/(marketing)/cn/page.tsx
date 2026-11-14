import LandingPage from '@/components/landing/LandingPage'
import { FaqJsonLd } from '@/components/landing/FaqJsonLd'

// 中文主页：锁定中文渲染（cn/layout.tsx 提供中文 SEO 元数据）。
export default function CnHomePage() {
  return (
    <>
      <FaqJsonLd lang="zh" />
      <LandingPage forcedLang="zh" />
    </>
  )
}
