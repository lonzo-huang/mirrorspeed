import type { Metadata } from 'next'
import { I18nProvider } from '@/lib/i18n'

export const metadata: Metadata = {
  title: 'MirrorSpeed — Free VPN · 免费加速器 · Unlimited Speed',
  description: 'Free VPN with unlimited speed and zero-logs nodes in 20+ countries — free forever, in-house engine, smart split routing for China users. 永久免费的镜速加速器，自研引擎，智能分流，不限速，多国节点零日志。Android / HarmonyOS / Windows / iOS / macOS.',
}

export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <I18nProvider>
      {children}
    </I18nProvider>
  )
}
