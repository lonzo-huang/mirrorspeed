import { redirect } from 'next/navigation'
import { getUser, createAdminClient } from '@/lib/supabase/server'
import { ForceDarkTheme } from '@/components/ForceDarkTheme'
import { BlogEditor } from './BlogEditor'

export const dynamic = 'force-dynamic'

export default async function AdminBlogPage() {
  const user = await getUser()
  if (!user) redirect('/login')
  const admin = createAdminClient()
  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if ((profile as any)?.role !== 'admin') redirect('/dashboard')
  return (
    <>
      <ForceDarkTheme />
      <div className="ms-landing min-h-screen bg-app text-app-primary" data-theme="dark">
        <BlogEditor />
      </div>
    </>
  )
}
