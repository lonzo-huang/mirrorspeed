import { createServerSupabaseClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { RefundView } from '@/components/refund/RefundView'

export default async function RefundPage() {
  const supabase = await createServerSupabaseClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return <RefundView defaultEmail={user.email ?? ''} />
}
