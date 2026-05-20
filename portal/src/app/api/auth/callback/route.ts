import { createServerClient } from '@supabase/ssr'
import { NextRequest, NextResponse } from 'next/server'

// OAuth / Magic Link 回调处理
// 关键：必须先创建 redirect response，再把 session cookie 写到该 response 上
// 若使用 cookies() from next/headers + NextResponse.redirect()，cookie 不会附在新 response 上
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
    const redirectUrl = next.startsWith('/') ? `${origin}${next}` : `${origin}/dashboard`
    const response = NextResponse.redirect(redirectUrl)

    // Supabase client 直接把 cookie 写到 response 对象上
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          getAll() {
            return request.cookies.getAll()
          },
          setAll(cookiesToSet) {
            cookiesToSet.forEach(({ name, value, options }) => {
              response.cookies.set(name, value, options)
            })
          },
        },
      }
    )

    const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code)

    if (!exchangeError) {
      return response  // response 已携带 Set-Cookie，浏览器会正确写入 session
    }

    console.error('[auth/callback] Session exchange error:', exchangeError)
  }

  return NextResponse.redirect(`${origin}/login?error=callback_failed`)
}
