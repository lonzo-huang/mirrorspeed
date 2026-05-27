import { createServerSupabaseClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { BillingView } from '@/components/billing/BillingView'

export default async function BillingPage() {
  const supabase = await createServerSupabaseClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: subscription }, { data: payments }] = await Promise.all([
    supabase.from('subscriptions').select('*').eq('user_id', user.id)
      .in('status', ['active', 'past_due', 'cancelled'])
      .order('created_at', { ascending: false })
      .maybeSingle(),
    supabase.from('payments').select('*').eq('user_id', user.id)
      .order('created_at', { ascending: false }).limit(10),
  ])

  return (
    <BillingView
      subscription={subscription as any}
      payments={payments ?? []}
    />
  )
}
