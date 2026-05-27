import { createServerSupabaseClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { DashboardView } from '@/components/dashboard/DashboardView'

const ADMIN_EMAIL = 'lonzo.huang@gmail.com'

export default async function DashboardPage() {
  const supabase = await createServerSupabaseClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: profile }, { data: subscription }, { data: devices }, { data: payments }] =
    await Promise.all([
      supabase.from('profiles').select('*').eq('id', user.id).single(),
      supabase.from('subscriptions').select('*, plan:plans(*)').eq('user_id', user.id)
        .in('status', ['active', 'past_due']).maybeSingle(),
      supabase.from('vpn_devices').select('*').eq('user_id', user.id).eq('is_active', true)
        .order('created_at', { ascending: false }),
      supabase.from('payments').select('*').eq('user_id', user.id)
        .order('created_at', { ascending: false }).limit(3),
    ])

  const displayName = (profile as any)?.display_name ?? user.email?.split('@')[0] ?? ''
  const isAdmin = user.email === ADMIN_EMAIL

  return (
    <DashboardView
      userEmail={user.email ?? ''}
      displayName={displayName}
      profile={profile}
      subscription={subscription as any}
      devices={devices ?? []}
      payments={payments ?? []}
      isAdmin={isAdmin}
    />
  )
}
