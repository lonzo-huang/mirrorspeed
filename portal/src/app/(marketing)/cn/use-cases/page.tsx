import { UseCaseIndexView } from '@/components/marketing/use-case-view'
import { I18nProvider } from '@/lib/i18n'

export default function CnUseCasesPage() {
  return (
    <I18nProvider forcedLang="zh">
      <UseCaseIndexView lang="zh" />
    </I18nProvider>
  )
}
