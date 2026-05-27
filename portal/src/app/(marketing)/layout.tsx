import type { Metadata } from 'next'
import { I18nProvider } from '@/lib/i18n'

export const metadata: Metadata = {
  title: 'MirrorSpeed – Fast Global VPN',
  description: 'Mirror-latency WireGuard VPN. Smart split routing for China users. Android & Windows apps.',
}

export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <I18nProvider>
      {children}
    </I18nProvider>
  )
}
