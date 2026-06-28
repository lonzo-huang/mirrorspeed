import { redirect } from 'next/navigation'
import { getUserProfile } from '@/lib/supabase/server'
import { DashboardNav } from '@/components/dashboard/nav'
import { I18nProvider } from '@/lib/i18n'

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const profile = await getUserProfile()
  if (!profile) redirect('/login')

  return (
    <I18nProvider>
      <div data-theme="dark" className="ms-landing min-h-screen bg-app text-app-primary relative overflow-hidden">
        <div className="absolute inset-0 grid-bg opacity-30 pointer-events-none" />
        <div className="absolute -top-32 left-1/4 h-96 w-96 rounded-full pointer-events-none" style={{ background: 'var(--accent-cyan-glow)', filter: 'blur(140px)', opacity: 0.2 }} />
        <DashboardNav profile={profile} />
        <main className="relative mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
          {children}
        </main>
      </div>
    </I18nProvider>
  )
}
