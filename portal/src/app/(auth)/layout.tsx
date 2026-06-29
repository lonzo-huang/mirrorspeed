import type { Metadata } from 'next'
import { I18nProvider } from '@/lib/i18n'
import { ForceDarkTheme } from '@/components/ForceDarkTheme'

export const metadata: Metadata = {
  // Login / signup pages shouldn't be indexed in search engines
  robots: { index: false, follow: true, nocache: true },
}

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return <I18nProvider><ForceDarkTheme />{children}</I18nProvider>
}
