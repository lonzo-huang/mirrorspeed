import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

// 需要登录才能访问的路径前缀
const PROTECTED_PREFIXES = ['/dashboard', '/admin']
// 已登录用户不应访问的路径（重定向到 dashboard）
const AUTH_ONLY_PATHS = ['/login']

export async function middleware(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  const { data: { user } } = await supabase.auth.getUser()
  const pathname = request.nextUrl.pathname

  // 未登录访问受保护路径 → 跳转登录页
  if (!user && PROTECTED_PREFIXES.some(p => pathname.startsWith(p))) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    url.searchParams.set('next', pathname)
    return NextResponse.redirect(url)
  }

  // 已登录访问登录页 → 跳转 dashboard
  if (user && AUTH_ONLY_PATHS.includes(pathname)) {
    const url = request.nextUrl.clone()
    url.pathname = '/dashboard'
    return NextResponse.redirect(url)
  }

  // admin 路径额外检查 role（从 JWT 自定义 claim 读取）
  if (user && pathname.startsWith('/admin')) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single()

    if (profile?.role !== 'admin') {
      const url = request.nextUrl.clone()
      url.pathname = '/dashboard'
      return NextResponse.redirect(url)
    }
  }

  return supabaseResponse
}

export const config = {
  // 仅在真正需要服务端会话的路径运行 middleware：
  //   - /dashboard、/admin：cookie 会话刷新 + 登录/角色门（页面层另有兜底）
  //   - /login：已登录用户反向重定向到 dashboard
  // 其余路径（/api/*、营销页、静态资源）不再触发 supabase.auth.getUser()，
  // 大幅降低 Supabase Auth egress。api/mobile/* 走 Bearer 自校验，无需 middleware。
  matcher: ['/dashboard/:path*', '/admin/:path*', '/login'],
}
