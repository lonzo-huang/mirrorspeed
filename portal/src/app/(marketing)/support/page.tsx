'use client'

import { useState, useEffect, useCallback } from 'react'
import { LandingChrome } from '@/components/landing/LandingPage'
import { useI18n }    from '@/lib/i18n'
import { Send, CheckCircle, RefreshCw } from 'lucide-react'

const COPY = {
  en: {
    badge:       'Customer Support',
    title:       'How can we help?',
    sub:         'Our team of real engineers typically responds within 1 business day.',
    name:        'Your name',
    email:       'Email address',
    subject:     'Subject (optional)',
    message:     'Describe your issue or question…',
    send:        'Send Message',
    sending:     'Sending…',
    successTitle: 'Message sent!',
    successBody:  "We've received your message and will reply to your email shortly.",
    errorGeneric: 'Something went wrong. Please try again.',
    required:    'Please fill in your name, email, and message.',
    captchaLabel: 'Verify you are human',
    captchaPrompt: 'What is',
    captchaPlaceholder: 'Answer',
    captchaError: 'Incorrect answer, please try again.',
    captchaRefresh: 'New question',
    cards: [
      { icon: '⚡', title: 'Fast Response', desc: 'We reply within 1 business day, usually much faster.' },
      { icon: '🛡️', title: 'Real Engineers', desc: 'Your ticket goes directly to a technical team member.' },
      { icon: '📨', title: 'One Place for Help', desc: 'Send everything from this page — we track every request.' },
    ],
  },
  zh: {
    badge:       '客户支持',
    title:       '有什么我们可以帮您的？',
    sub:         '我们的真实工程师团队通常在 1 个工作日内回复。',
    name:        '您的姓名',
    email:       '电子邮件地址',
    subject:     '主题（可选）',
    message:     '描述您的问题或疑问…',
    send:        '发送消息',
    sending:     '发送中…',
    successTitle: '消息已发送！',
    successBody:  '我们已收到您的消息，将尽快回复您的邮件。',
    errorGeneric: '出现问题，请重试。',
    required:    '请填写您的姓名、电子邮件和消息。',
    captchaLabel: '请完成人机验证',
    captchaPrompt: '请计算',
    captchaPlaceholder: '答案',
    captchaError: '验证码错误，请重试。',
    captchaRefresh: '换一题',
    cards: [
      { icon: '⚡', title: '快速响应', desc: '我们在 1 个工作日内回复，通常更快。' },
      { icon: '🛡️', title: '真实工程师', desc: '您的工单直接发送给技术团队成员。' },
      { icon: '📨', title: '统一求助入口', desc: '所有问题都从本页提交，我们会逐条跟进处理。' },
    ],
  },
}

export default function SupportPage() {
  const { lang } = useI18n()
  const c = lang === 'zh' ? COPY.zh : COPY.en

  const [name,    setName]    = useState('')
  const [email,   setEmail]   = useState('')
  const [subject, setSubject] = useState('')
  const [message, setMessage] = useState('')
  const [sending, setSending] = useState(false)
  const [done,    setDone]    = useState(false)
  const [err,     setErr]     = useState<string | null>(null)

  // 验证码
  const [captchaQ,     setCaptchaQ]     = useState('')
  const [captchaToken, setCaptchaToken] = useState('')
  const [captchaAns,   setCaptchaAns]   = useState('')

  const loadCaptcha = useCallback(async () => {
    setCaptchaAns('')
    try {
      const res  = await fetch('/api/support/captcha')
      const json = await res.json()
      setCaptchaQ(json.question ?? '')
      setCaptchaToken(json.token ?? '')
    } catch {
      setCaptchaQ('')
      setCaptchaToken('')
    }
  }, [])

  useEffect(() => { loadCaptcha() }, [loadCaptcha])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setErr(null)
    if (!name.trim() || !email.trim() || !message.trim()) {
      setErr(c.required)
      return
    }
    if (!captchaAns.trim()) {
      setErr(c.captchaError)
      return
    }
    setSending(true)
    try {
      const res = await fetch('/api/support', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ name, email, subject, message, captchaToken, captchaAnswer: captchaAns }),
      })
      const json = await res.json()
      if (!res.ok) {
        if (json.code === 'CAPTCHA_FAILED') {
          setErr(c.captchaError)
          await loadCaptcha()
          return
        }
        throw new Error(json.error ?? c.errorGeneric)
      }
      setDone(true)
    } catch (e: any) {
      setErr(e.message ?? c.errorGeneric)
      await loadCaptcha()
    } finally {
      setSending(false)
    }
  }

  return (
    <LandingChrome forcedLang={lang === 'zh' ? 'zh' : 'en'}>
      <main className="px-6 pb-24">
        <div className="max-w-4xl mx-auto">

          {/* Header */}
          <div className="text-center mb-16">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {c.badge}
            </span>
            <h1 className="font-heading text-4xl md:text-6xl font-black tracking-tighter mb-4">
              <span className="text-gradient-cyan">{c.title}</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-xl mx-auto">{c.sub}</p>
          </div>

          {/* Info cards */}
          <div className="grid md:grid-cols-3 gap-6 mb-16">
            {c.cards.map((card, i) => (
              <div key={i} className="glass-panel rounded-2xl p-6 text-center">
                <div className="text-3xl mb-3">{card.icon}</div>
                <h3 className="font-bold mb-1 text-app-primary">{card.title}</h3>
                <p className="text-sm text-app-secondary">{card.desc}</p>
              </div>
            ))}
          </div>

          {/* Form or success */}
          <div className="max-w-2xl mx-auto">
            {done ? (
              <div className="glass-panel rounded-2xl p-10 text-center">
                <CheckCircle className="h-14 w-14 text-green-400 mx-auto mb-4" />
                <h2 className="text-2xl font-bold mb-3 text-app-primary">{c.successTitle}</h2>
                <p className="text-app-secondary">{c.successBody}</p>
              </div>
            ) : (
              <form onSubmit={handleSubmit} className="glass-panel rounded-2xl p-8 space-y-5">
                <div className="grid md:grid-cols-2 gap-5">
                  <div>
                    <label className="block text-sm font-medium mb-1.5 text-app-primary">{c.name} *</label>
                    <input
                      type="text"
                      value={name}
                      onChange={e => setName(e.target.value)}
                      required
                      className="w-full rounded-xl border border-border bg-white px-4 py-2.5 text-sm text-gray-900 placeholder:text-gray-400
                                 focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium mb-1.5 text-app-primary">{c.email} *</label>
                    <input
                      type="email"
                      value={email}
                      onChange={e => setEmail(e.target.value)}
                      required
                      className="w-full rounded-xl border border-border bg-white px-4 py-2.5 text-sm text-gray-900 placeholder:text-gray-400
                                 focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium mb-1.5 text-app-primary">{c.subject}</label>
                  <input
                    type="text"
                    value={subject}
                    onChange={e => setSubject(e.target.value)}
                    className="w-full rounded-xl border border-border bg-white px-4 py-2.5 text-sm text-gray-900 placeholder:text-gray-400
                               focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium mb-1.5 text-app-primary">{c.message} *</label>
                  <textarea
                    value={message}
                    onChange={e => setMessage(e.target.value)}
                    required
                    rows={6}
                    className="w-full rounded-xl border border-border bg-white px-4 py-2.5 text-sm text-gray-900 placeholder:text-gray-400
                               focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition resize-none"
                  />
                </div>

                {/* 验证码 */}
                <div>
                  <label className="block text-sm font-medium mb-1.5 text-app-primary">{c.captchaLabel} *</label>
                  <div className="flex items-center gap-3">
                    <span className="shrink-0 rounded-xl bg-white/5 border border-border px-4 py-2.5 text-sm font-mono text-app-primary select-none">
                      {c.captchaPrompt} {captchaQ || '…'} =
                    </span>
                    <input
                      type="text"
                      inputMode="numeric"
                      value={captchaAns}
                      onChange={e => setCaptchaAns(e.target.value)}
                      required
                      placeholder={c.captchaPlaceholder}
                      className="w-28 rounded-xl border border-border bg-white px-4 py-2.5 text-sm text-gray-900 placeholder:text-gray-400
                                 focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition"
                    />
                    <button
                      type="button"
                      onClick={loadCaptcha}
                      title={c.captchaRefresh}
                      className="shrink-0 rounded-xl border border-border p-2.5 text-app-secondary hover:text-app-primary hover:bg-white/5 transition"
                    >
                      <RefreshCw className="h-4 w-4" />
                    </button>
                  </div>
                </div>

                {err && (
                  <div className="rounded-xl bg-red-500/10 border border-red-500/20 px-4 py-3 text-sm text-red-400">
                    {err}
                  </div>
                )}

                <button
                  type="submit"
                  disabled={sending}
                  className="w-full flex items-center justify-center gap-2 py-3 rounded-xl font-semibold
                             bg-gradient-to-r from-[var(--accent-cyan)] to-[#0080ff] text-black hover:opacity-90 transition disabled:opacity-50 disabled:cursor-not-allowed glow-cyan"
                >
                  <Send className="h-4 w-4" />
                  {sending ? c.sending : c.send}
                </button>
              </form>
            )}
          </div>

        </div>
      </main>
    </LandingChrome>
  )
}
