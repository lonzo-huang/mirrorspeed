import type { Metadata } from 'next'
import { I18nProvider } from '@/lib/i18n'

export const metadata: Metadata = {
  title: 'MirrorSpeed – Fast Global VPN',
  description: 'Mirror-latency VPN powered by the MirrorSpeed in-house engine. Smart split routing for China users. Android, HarmonyOS & Windows apps.',
}

export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <I18nProvider>
      {children}
    </I18nProvider>
  )
}
