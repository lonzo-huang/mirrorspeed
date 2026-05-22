import { redirect } from 'next/navigation'
import { getUserProfile } from '@/lib/supabase/server'
import { DashboardNav } from '@/components/dashboard/nav'
import { I18nProvider } from '@/lib/i18n'

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const profile = await getUserProfile()
  if (!profile) redirect('/login')

  return (
    <I18nProvider>
      <div className="min-h-screen bg-background text-foreground">
        <DashboardNav profile={profile} />
        <main className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
          {children}
        </main>
      </div>
    </I18nProvider>
  )
}
