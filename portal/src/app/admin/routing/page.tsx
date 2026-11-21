import { redirect } from 'next/navigation'
import { getUser, createAdminClient } from '@/lib/supabase/server'
import { ForceDarkTheme } from '@/components/ForceDarkTheme'
import RoutingSettings from './RoutingSettings'

export const dynamic = 'force-dynamic'

export default async function AdminRoutingPage() {
  const user = await getUser()
  if (!user) redirect('/login')
  const admin = createAdminClient()
  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if ((profile as any)?.role !== 'admin') redirect('/dashboard')
  return <><ForceDarkTheme /><RoutingSettings /></>
}
