import LandingPage from '@/components/landing/LandingPage'
import { FaqJsonLd } from '@/components/landing/FaqJsonLd'

// 英文主页：锁定英文渲染。
export default function EnHomePage() {
  return (
    <>
      <FaqJsonLd lang="en" />
      <LandingPage forcedLang="en" />
    </>
  )
}
