'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useSearchParams } from 'next/navigation'
import { Shield, Mail, Chrome } from 'lucide-react'

export default function LoginPage() {
  const searchParams = useSearchParams()
  const next  = searchParams.get('next') ?? '/dashboard'
  const error = searchParams.get('error')

  const [email, setEmail]       = useState('')
  const [loading, setLoading]   = useState<string | null>(null)
  const [magicSent, setMagicSent] = useState(false)
  const supabase = createClient()

  const redirectTo = `${process.env.NEXT_PUBLIC_APP_URL}/api/auth/callback?next=${encodeURIComponent(next)}`

  async function signInWithGoogle() {
    setLoading('google')
    await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo },
    })
  }

  async function signInWithMicrosoft() {
    setLoading('microsoft')
    await supabase.auth.signInWithOAuth({
      provider: 'azure',
      options: { redirectTo, scopes: 'openid email profile' },
    })
  }

  async function signInWithEmail(e: React.FormEvent) {
    e.preventDefault()
    if (!email.trim()) return
    setLoading('email')
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: redirectTo },
    })
    setLoading(null)
    if (!error) setMagicSent(true)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-brand-900 via-brand-700 to-brand-500 px-4">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-white/10 backdrop-blur mb-4">
            <Shield className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-white">Enterprise VPN Portal</h1>
          <p className="mt-1 text-brand-100 text-sm">企业安全远程接入平台</p>
        </div>

        <div className="card">
          {error && (
            <div className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
              登录失败，请重试。({error})
            </div>
          )}

          {magicSent ? (
            <div className="text-center py-4">
              <Mail className="w-12 h-12 text-brand-500 mx-auto mb-3" />
              <h2 className="font-semibold text-gray-900 mb-1">邮件已发送</h2>
              <p className="text-sm text-gray-500">
                请检查 <strong>{email}</strong> 的收件箱，点击链接完成登录。
              </p>
              <button
                className="mt-4 text-sm text-brand-600 hover:underline"
                onClick={() => setMagicSent(false)}
              >
                重新发送
              </button>
            </div>
          ) : (
            <>
              {/* OAuth 按钮 */}
              <div className="space-y-3">
                <button
                  onClick={signInWithGoogle}
                  disabled={loading !== null}
                  className="btn-secondary w-full"
                >
                  {/* Google SVG */}
                  <svg className="w-4 h-4" viewBox="0 0 24 24">
                    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                  </svg>
                  {loading === 'google' ? '跳转中...' : '使用 Google 账号登录'}
                </button>

                <button
                  onClick={signInWithMicrosoft}
                  disabled={loading !== null}
                  className="btn-secondary w-full"
                >
                  {/* Microsoft SVG */}
                  <svg className="w-4 h-4" viewBox="0 0 21 21">
                    <rect x="1" y="1" width="9" height="9" fill="#f25022"/>
                    <rect x="11" y="1" width="9" height="9" fill="#7fba00"/>
                    <rect x="1" y="11" width="9" height="9" fill="#00a4ef"/>
                    <rect x="11" y="11" width="9" height="9" fill="#ffb900"/>
                  </svg>
                  {loading === 'microsoft' ? '跳转中...' : '使用 Microsoft 账号登录'}
                </button>
              </div>

              {/* 分割线 */}
              <div className="relative my-6">
                <div className="absolute inset-0 flex items-center">
                  <div className="w-full border-t border-gray-200" />
                </div>
                <div className="relative flex justify-center text-xs">
                  <span className="bg-white px-3 text-gray-400">或使用邮箱</span>
                </div>
              </div>

              {/* 邮箱 Magic Link */}
              <form onSubmit={signInWithEmail} className="space-y-3">
                <input
                  type="email"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  placeholder="your@email.com"
                  required
                  className="w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm
                             focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                />
                <button
                  type="submit"
                  disabled={loading !== null}
                  className="btn-primary w-full"
                >
                  <Mail className="w-4 h-4" />
                  {loading === 'email' ? '发送中...' : '发送登录链接'}
                </button>
              </form>
            </>
          )}
        </div>

        <p className="mt-4 text-center text-xs text-brand-200">
          登录即表示您同意公司 IT 安全使用政策
        </p>
      </div>
    </div>
  )
}
