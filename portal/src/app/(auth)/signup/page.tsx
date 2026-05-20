'use client'

import { Suspense, useState } from 'react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { useSearchParams } from 'next/navigation'
import { Mail } from 'lucide-react'
import { useI18n } from '@/lib/i18n'

function SignupForm() {
  const { t } = useI18n()
  const searchParams = useSearchParams()
  const next  = searchParams.get('next') ?? '/dashboard'

  const [email, setEmail]         = useState('')
  const [loading, setLoading]     = useState<string | null>(null)
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

  async function signUpWithEmail(e: React.FormEvent) {
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
    <div className="min-h-screen bg-background text-foreground flex items-center justify-center p-6">
      <div className="w-full max-w-md">
        <Link href="/" className="block text-center text-lg font-extrabold tracking-tighter uppercase mb-8 text-foreground hover:text-mirror transition-colors">
          MirrorSpeed
        </Link>

        <div className="glass-panel p-10 rounded-3xl">
          {magicSent ? (
            <div className="text-center py-4">
              <Mail className="w-12 h-12 text-mirror mx-auto mb-3" />
              <h2 className="font-semibold text-foreground mb-1">邮件已发送</h2>
              <p className="text-sm text-muted-foreground">
                请检查 <strong>{email}</strong> 的收件箱，点击链接完成注册。
              </p>
              <button
                className="mt-4 text-sm text-mirror hover:underline"
                onClick={() => setMagicSent(false)}
              >
                重新发送
              </button>
            </div>
          ) : (
            <>
              <h2 className="text-2xl font-bold mb-8 text-center text-foreground">
                {t.auth.signupTitle}
              </h2>

              {/* OAuth buttons */}
              <div className="space-y-3">
                <button
                  onClick={signInWithGoogle}
                  disabled={loading !== null}
                  className="w-full flex items-center justify-center gap-3 py-3 glass-panel rounded-xl hover:bg-white/5 transition-all disabled:opacity-50"
                >
                  <svg width="18" height="18" viewBox="0 0 18 18">
                    <path fill="#4285F4" d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.258h2.908c1.702-1.567 2.684-3.875 2.684-6.615z"/>
                    <path fill="#34A853" d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18z"/>
                    <path fill="#FBBC05" d="M3.964 10.71A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.042l3.007-2.332z"/>
                    <path fill="#EA4335" d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z"/>
                  </svg>
                  <span className="text-sm font-medium text-foreground">
                    {loading === 'google' ? '跳转中...' : t.auth.google}
                  </span>
                </button>

                <button
                  onClick={signInWithMicrosoft}
                  disabled={loading !== null}
                  className="w-full flex items-center justify-center gap-3 py-3 glass-panel rounded-xl hover:bg-white/5 transition-all disabled:opacity-50"
                >
                  <svg width="18" height="18" viewBox="0 0 18 18">
                    <rect width="8" height="8" fill="#F25022"/>
                    <rect x="10" width="8" height="8" fill="#7FBA00"/>
                    <rect y="10" width="8" height="8" fill="#00A4EF"/>
                    <rect x="10" y="10" width="8" height="8" fill="#FFB900"/>
                  </svg>
                  <span className="text-sm font-medium text-foreground">
                    {loading === 'microsoft' ? '跳转中...' : t.auth.microsoft}
                  </span>
                </button>
              </div>

              {/* Divider */}
              <div className="relative py-5 flex items-center gap-4">
                <div className="h-px flex-grow bg-white/10" />
                <span className="text-[10px] text-muted-foreground uppercase font-bold tracking-widest">
                  {t.auth.orEmail}
                </span>
                <div className="h-px flex-grow bg-white/10" />
              </div>

              {/* Magic Link form */}
              <form onSubmit={signUpWithEmail} className="space-y-3">
                <input
                  type="email"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  placeholder={t.auth.email}
                  required
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-mirror transition-colors"
                />
                <button
                  type="submit"
                  disabled={loading !== null}
                  className="w-full flex items-center justify-center gap-2 py-3 bg-primary text-primary-foreground font-bold rounded-xl hover:bg-mirror transition-all disabled:opacity-50"
                >
                  <Mail className="w-4 h-4" />
                  {loading === 'email' ? '发送中...' : t.auth.submit}
                </button>
              </form>
            </>
          )}
        </div>

        <p className="text-center text-sm text-muted-foreground mt-6">
          <Link href="/login" className="hover:text-mirror transition-colors">
            {t.auth.switchToLogin}
          </Link>
        </p>
      </div>
    </div>
  )
}

export default function SignupPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-muted-foreground">加载中...</div>
      </div>
    }>
      <SignupForm />
    </Suspense>
  )
}
