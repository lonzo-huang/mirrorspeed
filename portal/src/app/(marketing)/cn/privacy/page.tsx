import PrivacyView from '@/components/marketing/privacy-view'
import { I18nProvider } from '@/lib/i18n'

// 中文专属网址：服务端稳定渲染中文，不随访客浏览器语言漂移。
export default function CnPrivacyPage() {
  return (
    <I18nProvider forcedLang="zh">
      <PrivacyView />
    </I18nProvider>
  )
}
