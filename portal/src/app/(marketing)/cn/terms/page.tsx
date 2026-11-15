import TermsView from '@/components/marketing/terms-view'
import { I18nProvider } from '@/lib/i18n'

// 中文专属网址：服务端稳定渲染中文，不随访客浏览器语言漂移。
export default function CnTermsPage() {
  return (
    <I18nProvider forcedLang="zh">
      <TermsView />
    </I18nProvider>
  )
}
