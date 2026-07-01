'use client'

import { useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

/**
 * App → 浏览器 单点登录桥接页。
 * Flutter 客户端已登录时，用 `/auth/app-bridge#at=<access>&rt=<refresh>&next=<path>`
 * 打开浏览器：本页从 URL fragment(#，不会发送到服务器/不进日志) 取出 Supabase 会话，
 * 用 setSession 在浏览器建立同一会话(写入 cookie)，随后跳到目标页——用户无需重复登录。
 */
export default function AppBridgePage() {
  useEffect(() => {
    const run = async () => {
      const goLogin = (next: string) =>
        window.location.replace('/login?next=' + encodeURIComponent(next))
      try {
        const raw = window.location.hash.replace(/^#/, '')
        const p = new URLSearchParams(raw)
        const at = p.get('at')
        const rt = p.get('rt')
        let next = p.get('next') || '/dashboard'
        if (!next.startsWith('/')) next = '/dashboard'   // 只允许站内相对路径
        if (!at || !rt) return goLogin(next)

        const supabase = createClient()
        const { error } = await supabase.auth.setSession({
          access_token: at,
          refresh_token: rt,
        })
        // 清掉地址栏里的 token，避免留在历史记录
        try { history.replaceState(null, '', '/auth/app-bridge') } catch (_) {}
        if (error) return goLogin(next)
        window.location.replace(next)
      } catch {
        window.location.replace('/login')
      }
    }
    run()
  }, [])

  return (
    <div data-theme="dark" className="ms-landing min-h-screen bg-app text-app-primary flex items-center justify-center">
      <div className="text-app-secondary text-sm">正在登录… / Signing in…</div>
    </div>
  )
}
