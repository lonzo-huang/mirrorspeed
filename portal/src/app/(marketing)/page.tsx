import LandingPage from '@/components/landing/LandingPage'
import { FaqJsonLd } from '@/components/landing/FaqJsonLd'

// 主页：采用设计师新版落地页（自带导航/页脚/深色主题/11 语言，自动按地区语言）。
// 服务端渲染出的是英文版，故 FAQ 结构化数据用英文（与 `/` 的 canonical 语言一致）。
export default function HomePage() {
  return (
    <>
      <FaqJsonLd lang="en" />
      <LandingPage />
    </>
  )
}
