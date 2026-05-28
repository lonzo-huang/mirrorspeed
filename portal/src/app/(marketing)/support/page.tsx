'use client'

import { useState } from 'react'
import { SiteNav }    from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n }    from '@/lib/i18n'
import { Send, CheckCircle } from 'lucide-react'

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
    successBody:  'We've received your message and will reply to your email shortly.',
    errorGeneric: 'Something went wrong. Please try again or email us directly.',
    required:    'Please fill in your name, email, and message.',
    cards: [
      { icon: '⚡', title: 'Fast Response', desc: 'We reply within 1 business day, usually much faster.' },
      { icon: '🛡️', title: 'Real Engineers', desc: 'Your ticket goes directly to a technical team member.' },
      { icon: '📧', title: 'Email Us Directly', desc: 'mirrorspeed@mirrorquant.com' },
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
    errorGeneric: '出现问题，请重试或直接发送邮件给我们。',
    required:    '请填写您的姓名、电子邮件和消息。',
    cards: [
      { icon: '⚡', title: '快速响应', desc: '我们在 1 个工作日内回复，通常更快。' },
      { icon: '🛡️', title: '真实工程师', desc: '您的工单直接发送给技术团队成员。' },
      { icon: '📧', title: '直接发邮件', desc: 'mirrorspeed@mirrorquant.com' },
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

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setErr(null)
    if (!name.trim() || !email.trim() || !message.trim()) {
      setErr(c.required)
      return
    }
    setSending(true)
    try {
      const res = await fetch('/api/support', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ name, email, subject, message }),
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error ?? c.errorGeneric)
      setDone(true)
    } catch (e: any) {
      setErr(e.message ?? c.errorGeneric)
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <div className="max-w-4xl mx-auto">

          {/* Header */}
          <div className="text-center mb-16">
            <span className="inline-block text-[11px] font-bold uppercase tracking-widest text-mirror border border-mirror/30 rounded-full px-4 py-1.5 mb-6">
              {c.badge}
            </span>
            <h1 className="text-4xl md:text-5xl font-bold tracking-tighter mb-4">{c.title}</h1>
            <p className="text-muted-foreground text-lg max-w-xl mx-auto">{c.sub}</p>
          </div>

          {/* Info cards */}
          <div className="grid md:grid-cols-3 gap-6 mb-16">
            {c.cards.map((card, i) => (
              <div key={i} className="glass-panel rounded-2xl p-6 text-center">
                <div className="text-3xl mb-3">{card.icon}</div>
                <h3 className="font-bold mb-1">{card.title}</h3>
                <p className="text-sm text-muted-foreground">{card.desc}</p>
              </div>
            ))}
          </div>

          {/* Form or success */}
          <div className="max-w-2xl mx-auto">
            {done ? (
              <div className="glass-panel rounded-2xl p-10 text-center">
                <CheckCircle className="h-14 w-14 text-green-400 mx-auto mb-4" />
                <h2 className="text-2xl font-bold mb-3">{c.successTitle}</h2>
                <p className="text-muted-foreground">{c.successBody}</p>
              </div>
            ) : (
              <form onSubmit={handleSubmit} className="glass-panel rounded-2xl p-8 space-y-5">
                <div className="grid md:grid-cols-2 gap-5">
                  <div>
                    <label className="block text-sm font-medium mb-1.5">{c.name} *</label>
                    <input
                      type="text"
                      value={name}
                      onChange={e => setName(e.target.value)}
                      required
                      className="w-full rounded-xl border border-border bg-background/50 px-4 py-2.5 text-sm
                                 focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium mb-1.5">{c.email} *</label>
                    <input
                      type="email"
                      value={email}
                      onChange={e => setEmail(e.target.value)}
                      required
                      className="w-full rounded-xl border border-border bg-background/50 px-4 py-2.5 text-sm
                                 focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium mb-1.5">{c.subject}</label>
                  <input
                    type="text"
                    value={subject}
                    onChange={e => setSubject(e.target.value)}
                    className="w-full rounded-xl border border-border bg-background/50 px-4 py-2.5 text-sm
                               focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium mb-1.5">{c.message} *</label>
                  <textarea
                    value={message}
                    onChange={e => setMessage(e.target.value)}
                    required
                    rows={6}
                    className="w-full rounded-xl border border-border bg-background/50 px-4 py-2.5 text-sm
                               focus:border-mirror focus:outline-none focus:ring-1 focus:ring-mirror transition resize-none"
                  />
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
                             bg-mirror text-black hover:opacity-90 transition disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Send className="h-4 w-4" />
                  {sending ? c.sending : c.send}
                </button>
              </form>
            )}
          </div>

        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
