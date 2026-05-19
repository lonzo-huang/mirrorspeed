import { I18nProvider } from '@/lib/i18n'

export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <I18nProvider>
      {children}
    </I18nProvider>
  )
}
