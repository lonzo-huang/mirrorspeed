import { createServerSupabaseClient } from '@/lib/supabase/server'
import { NextRequest, NextResponse } from 'next/server'

// OAuth / Magic Link 回调处理
// Supabase 在 OAuth 完成后重定向到 /auth/callback?code=xxx
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url)
  const code  = searchParams.get('code')
  const next  = searchParams.get('next') ?? '/dashboard'
  const error = searchParams.get('error')

  if (error) {
    console.error('[auth/callback] OAuth error:', error, searchParams.get('error_description'))
    return NextResponse.redirect(`${origin}/login?error=${encodeURIComponent(error)}`)
  }

  if (code) {
    const supabase = await createServerSupabaseClient()
    const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code)

    if (!exchangeError) {
      // 成功：跳转至原目标页或 dashboard
      const redirectUrl = next.startsWith('/') ? `${origin}${next}` : origin + '/dashboard'
      return NextResponse.redirect(redirectUrl)
    }

    console.error('[auth/callback] Session exchange error:', exchangeError)
  }

  return NextResponse.redirect(`${origin}/login?error=callback_failed`)
}
