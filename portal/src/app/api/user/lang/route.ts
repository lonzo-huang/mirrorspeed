import { createServerSupabaseClient, createAdminClient } from '@/lib/supabase/server'
import { NextRequest, NextResponse } from 'next/server'

const VALID_LANGS = ['en', 'zh', 'de', 'fr', 'it', 'es', 'uk', 'ja']

// PATCH /api/user/lang — persist language preference to profile
export async function PATCH(req: NextRequest) {
  try {
    const supabase = await createServerSupabaseClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const { lang } = await req.json()
    if (!VALID_LANGS.includes(lang)) {
      return NextResponse.json({ error: 'Invalid lang' }, { status: 400 })
    }

    const admin = createAdminClient()
    await (admin.from('profiles' as any) as any)
      .update({ lang })
      .eq('id', user.id)

    return NextResponse.json({ ok: true })
  } catch (err: any) {
    return NextResponse.json({ error: err?.message }, { status: 500 })
  }
}
