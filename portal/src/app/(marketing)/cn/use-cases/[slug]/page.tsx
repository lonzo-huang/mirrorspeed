import { notFound } from 'next/navigation'
import { UseCaseView } from '@/components/marketing/use-case-view'
import { I18nProvider } from '@/lib/i18n'
import { getUseCase } from '@/lib/useCases'

export default function CnUseCasePage({ params }: { params: { slug: string } }) {
  const useCase = getUseCase(params.slug)
  if (!useCase) notFound()
  return (
    <I18nProvider forcedLang="zh">
      <UseCaseView useCase={useCase} lang="zh" />
    </I18nProvider>
  )
}
