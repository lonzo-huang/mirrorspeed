import { notFound } from 'next/navigation'
import { UseCaseView } from '@/components/marketing/use-case-view'
import { getUseCase } from '@/lib/useCases'

export default function UseCasePage({ params }: { params: { slug: string } }) {
  const useCase = getUseCase(params.slug)
  if (!useCase) notFound()
  return <UseCaseView useCase={useCase} lang="en" />
}
