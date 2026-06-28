'use client'

import { Suspense, useState } from 'react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { useSearchParams, useRouter } from 'next/navigation'
import { Mail, KeyRound } from 'lucide-react'
import { useI18n } from '@/lib/i18n'

function SignupForm() {
  const { t } = useI18n()
  const searchParams = useSearchParams()
  const router = useRouter()
  const next  = searchParams.get('next') ?? '/dashboard'

  const [email, setEmail]     = useState('')
  const [otp, setOtp]         = useState('')
  const [step, setStep]       = useState<'email' | 'otp'>('email')
  const [loading, setLoading] = useState<string | null>(null)
  const [error, setError]     = useState<string | null>(null)
  const supabase = createClient()

  const redirectTo = `${typeof window !== 'undefined' ? window.location.origin : process.env.NEXT_PUBLIC_APP_URL}/api/auth/callback?next=${encodeURIComponent(next)}`

  async function signInWithGoogle() {
    setLoading('google')
    await supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo } })
  }

  async function sendOtp(e: React.FormEvent) {
    e.preventDefault()
    if (!email.trim()) return
    setLoading('email')
    setError(null)
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { shouldCreateUser: true },
    })
    setLoading(null)
    if (error) { setError(error.message); return }
    setStep('otp')
  }

  async function verifyOtp(e: React.FormEvent) {
    e.preventDefault()
    if (!otp.trim()) return
    setLoading('verify')
    setError(null)
    const { error } = await supabase.auth.verifyOtp({
      email: email.trim(),
      token: otp.trim(),
      type: 'email',
    })
    setLoading(null)
    if (error) { setError(t.auth.invalidOtp); return }
    setLoading('redirecting')
    router.push(next)
    router.refresh()
  }

  return (
    <div data-theme="dark" className="ms-landing min-h-screen bg-app text-app-primary flex items-center justify-center p-6 relative overflow-hidden">
      <div className="absolute inset-0 grid-bg opacity-40 pointer-events-none" />
      <div className="absolute top-1/4 left-1/4 h-[500px] w-[500px] rounded-full pointer-events-none" style={{ background: 'var(--accent-cyan-glow)', filter: 'blur(140px)', opacity: 0.35 }} />
      <div className="absolute bottom-1/4 right-1/4 h-[400px] w-[400px] rounded-full pointer-events-none" style={{ background: 'rgba(255,0,85,0.15)', filter: 'blur(120px)' }} />
      <div className="w-full max-w-md relative">
        <Link href="/" className="flex items-center justify-center gap-2.5 mb-8 hover:scale-[1.02] transition-transform" data-testid="signup-back-home">
          <img src="/icon-192.png" alt="MirrorSpeed" className="h-9 w-9 rounded-lg" style={{ boxShadow: '0 0 12px rgba(34,211,160,0.4)' }} />
          <span className="font-heading text-2xl font-black tracking-tighter uppercase text-gradient-cyan">MirrorSpeed</span>
        </Link>

        <div className="glass-panel p-10 rounded-3xl border-app-subtle">
          {error && (
            <div className="mb-4 rounded-lg bg-red-500/10 border border-red-500/20 px-4 py-3 text-sm text-red-400">
              {error}
            </div>
          )}

          {step === 'otp' ? (
            /* ── OTP 验证码输入 ── */
            <div>
              <div className="text-center mb-6">
                <Mail className="w-12 h-12 text-accent-cyan mx-auto mb-3" />
                <h2 className="font-heading font-semibold text-app-primary mb-1">{t.auth.otpSent}</h2>
                <p className="text-sm text-app-secondary">{t.auth.enterOtp}</p>
                <p className="text-xs text-accent-cyan mt-1">{email}</p>
              </div>
              <form onSubmit={verifyOtp} className="space-y-3">
                <input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  maxLength={6}
                  value={otp}
                  onChange={e => setOtp(e.target.value.replace(/\D/g, ''))}
                  placeholder={t.auth.otpPlaceholder}
                  required
                  autoFocus
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-4 text-2xl text-center tracking-[0.5em] text-app-primary placeholder:text-app-muted/40 focus:outline-none focus:border-[var(--accent-cyan)] transition-colors"
                />
                <button
                  type="submit"
                  disabled={loading !== null || otp.length < 6}
                  className="w-full flex items-center justify-center gap-2 py-3 font-bold rounded-xl transition-all disabled:opacity-50 glow-cyan hover:scale-[1.01]"
                  style={{ background: 'linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)', color: '#000' }}
                >
                  <KeyRound className="w-4 h-4" />
                  {loading === 'verify' || loading === 'redirecting' ? t.auth.redirecting : t.auth.verify}
                </button>
              </form>
              <button
                className="mt-4 w-full text-sm text-app-muted hover:text-accent-cyan transition-colors"
                onClick={() => { setStep('email'); setOtp(''); setError(null); }}
              >
                ← {t.auth.resend}
              </button>
            </div>
          ) : (
            /* ── 邮箱输入 ── */
            <>
              <h2 className="font-heading text-2xl font-black mb-8 text-center tracking-tighter">
                <span className="text-gradient-cyan">{t.auth.signupTitle}</span>
              </h2>

              {/* OAuth */}
              <div className="space-y-3">
                <button onClick={signInWithGoogle} disabled={loading !== null}
                  className="w-full flex items-center justify-center gap-3 py-3 glass-panel rounded-xl hover:bg-white/5 transition-all disabled:opacity-50">
                  <svg width="18" height="18" viewBox="0 0 18 18">
                    <path fill="#4285F4" d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.258h2.908c1.702-1.567 2.684-3.875 2.684-6.615z"/>
                    <path fill="#34A853" d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18z"/>
                    <path fill="#FBBC05" d="M3.964 10.71A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.042l3.007-2.332z"/>
                    <path fill="#EA4335" d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z"/>
                  </svg>
                  <span className="text-sm font-medium text-app-primary">
                    {loading === 'google' ? t.auth.redirecting : t.auth.google}
                  </span>
                </button>
              </div>

              <div className="relative py-5 flex items-center gap-4">
                <div className="h-px flex-grow bg-white/10" />
                <span className="text-[10px] text-app-muted uppercase font-bold tracking-widest">{t.auth.orEmail}</span>
                <div className="h-px flex-grow bg-white/10" />
              </div>

              <form onSubmit={sendOtp} className="space-y-3">
                <input
                  type="email"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  placeholder={t.auth.email}
                  required
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-sm text-app-primary placeholder:text-app-muted focus:outline-none focus:border-[var(--accent-cyan)] transition-colors"
                />
                <button
                  type="submit"
                  disabled={loading !== null}
                  className="w-full flex items-center justify-center gap-2 py-3 font-bold rounded-xl glow-cyan hover:scale-[1.01] transition-all disabled:opacity-50"
                  style={{ background: 'linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)', color: '#000' }}
                >
                  <Mail className="w-4 h-4" />
                  {loading === 'email' ? t.auth.sending : t.auth.submit}
                </button>
              </form>
            </>
          )}
        </div>

        <p className="text-center text-sm text-app-muted mt-6">
          <Link href="/login" className="hover:text-accent-cyan transition-colors">
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
      <div data-theme="dark" className="ms-landing min-h-screen bg-app flex items-center justify-center">
        <div className="text-app-muted">Loading…</div>
      </div>
    }>
      <SignupForm />
    </Suspense>
  )
}
