import DownloadView from '@/components/marketing/download-view'
import { I18nProvider } from '@/lib/i18n'

// 中文专属网址：强制中文渲染，服务端产出的 HTML 稳定是中文，
// 不随访客的浏览器语言漂移（爬虫看到的必须和 hreflang 声明一致）。
export default function CnDownloadPage() {
  return (
    <I18nProvider forcedLang="zh">
      <DownloadView />
    </I18nProvider>
  )
}
