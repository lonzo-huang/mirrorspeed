'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { CheckCircle, AlertCircle, Upload, ExternalLink } from 'lucide-react'
import { useI18n } from '@/lib/i18n'
import { REFUND_REASONS, getRefundReason } from '@/lib/refund-reasons'

interface Props {
  defaultEmail: string
}

// 终端类型（第 4 步）。存储值用英文 `${group.en} / ${model.v}`，便于按平台统计。
const DEVICE_GROUPS = [
  {
    key: 'apple', zh: '苹果', en: 'Apple',
    models: [
      { v: 'iPhone', zh: 'iPhone', en: 'iPhone' },
      { v: 'iPad',   zh: 'iPad',   en: 'iPad' },
      { v: 'Mac',    zh: 'Mac',    en: 'Mac' },
    ],
  },
  {
    key: 'android', zh: '安卓', en: 'Android',
    models: [
      { v: 'Huawei',  zh: '华为', en: 'Huawei' },
      { v: 'Xiaomi',  zh: '小米', en: 'Xiaomi' },
      { v: 'OPPO',    zh: 'OPPO', en: 'OPPO' },
      { v: 'vivo',    zh: 'vivo', en: 'vivo' },
      { v: 'Samsung', zh: '三星', en: 'Samsung' },
      { v: 'ZTE',     zh: '中兴', en: 'ZTE' },
      { v: 'Honor',   zh: '荣耀', en: 'Honor' },
      { v: 'Other',   zh: '其他', en: 'Other' },
    ],
  },
  {
    key: 'pc', zh: 'PC', en: 'PC',
    models: [
      { v: 'Windows 7',  zh: 'Windows 7',  en: 'Windows 7' },
      { v: 'Windows 10', zh: 'Windows 10', en: 'Windows 10' },
      { v: 'Windows 11', zh: 'Windows 11', en: 'Windows 11' },
      { v: 'Ubuntu',     zh: 'Ubuntu',     en: 'Ubuntu' },
      { v: 'Debian',     zh: 'Debian',     en: 'Debian' },
      { v: 'Other',      zh: '其他',        en: 'Other' },
    ],
  },
] as const

export function RefundView({ defaultEmail }: Props) {
  const { lang } = useI18n()
  const isZh = lang === 'zh'
  const L = (zh: string, en: string) => (isZh ? zh : en)

  const [faqAck, setFaqAck]       = useState<'' | 'yes' | 'no'>('')
  const [reasonCode, setReason]   = useState('')
  const [detail, setDetail]       = useState('')
  const [email, setEmail]         = useState(defaultEmail)
  const [file, setFile]           = useState<File | null>(null)
  const [platform, setPlatform]   = useState('')   // apple / android / pc
  const [model, setModel]         = useState('')   // model.v
  const [submitting, setSubmit]   = useState(false)
  const [error, setError]         = useState('')
  const [done, setDone]           = useState(false)

  const reason = getRefundReason(reasonCode)

  // 按分组组织原因
  const groups = useMemo(() => {
    const map = new Map<string, typeof REFUND_REASONS>()
    for (const r of REFUND_REASONS) {
      const g = isZh ? r.group : r.groupEn
      if (!map.has(g)) map.set(g, [])
      map.get(g)!.push(r)
    }
    return Array.from(map.entries())
  }, [isZh])

  const group = DEVICE_GROUPS.find(g => g.key === platform)
  const deviceType = group && model ? `${group.en} / ${model}` : ''

  async function submit() {
    setError('')
    if (!reason)                 return setError(L('请选择退款原因', 'Please select a reason'))
    if (detail.trim().length < 5) return setError(L('请描述具体原因（至少 5 个字）', 'Please describe your issue (min 5 chars)'))
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim()))
      return setError(L('请填写有效的订阅邮箱', 'Please enter a valid subscription email'))
    if (!deviceType)             return setError(L('请选择终端类型', 'Please select your device type'))

    setSubmit(true)
    try {
      const fd = new FormData()
      fd.set('faq_ack', 'yes')
      fd.set('reason_code', reason.code)
      fd.set('detail', detail.trim())
      fd.set('email', email.trim())
      fd.set('device_type', deviceType)
      if (file) fd.set('screenshot', file)

      const res  = await fetch('/api/refund', { method: 'POST', body: fd })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) throw new Error(data.error || L('提交失败，请稍后再试', 'Submission failed, please try again'))
      setDone(true)
    } catch (e: any) {
      setError(e.message)
    } finally {
      setSubmit(false)
    }
  }

  // ── 成功页 ───────────────────────────────────────────────
  if (done) {
    return (
      <div className="max-w-2xl mx-auto space-y-6">
        <div className="glass-panel rounded-2xl p-8 text-center">
          <CheckCircle className="h-12 w-12 text-green-400 mx-auto mb-4" />
          <h1 className="text-xl font-bold text-foreground mb-2">
            {L('退款申请已提交', 'Refund request submitted')}
          </h1>
          <p className="text-sm text-muted-foreground">
            {L('我们已收到你的申请，将在 1-2 个工作日内通过邮件与你联系。感谢你的反馈。',
               'We’ve received your request and will get back to you by email within 1-2 business days. Thanks for your feedback.')}
          </p>
          <Link href="/dashboard/billing" className="btn-primary inline-block mt-6 text-sm">
            {L('返回账单', 'Back to billing')}
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">{L('申请退款', 'Request a Refund')}</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {L('在提交前，请先花一分钟了解以下内容——很多问题可以即时解决，无需退款。',
             'Before you submit, take a minute to review the following — many issues can be solved instantly, no refund needed.')}
        </p>
      </div>

      {/* Step 1 — FAQ gate */}
      <div className="glass-panel rounded-2xl p-6">
        <h2 className="font-semibold text-foreground mb-3">
          1. {L('你是否已查阅帮助中心（FAQ）？', 'Have you checked our Help Center (FAQ)?')}
        </h2>
        <Link
          href="/help"
          target="_blank"
          className="inline-flex items-center gap-1.5 text-sm text-mirror hover:underline mb-4"
        >
          {L('打开 FAQ 帮助中心', 'Open FAQ / Help Center')} <ExternalLink className="h-3.5 w-3.5" />
        </Link>
        <div className="flex gap-3">
          <button
            onClick={() => setFaqAck('yes')}
            className={`rounded-lg px-4 py-2 text-sm font-medium border transition-colors
              ${faqAck === 'yes' ? 'border-mirror bg-mirror/10 text-foreground' : 'border-border text-muted-foreground hover:text-foreground'}`}
          >
            {L('已查阅', 'Yes, I have')}
          </button>
          <button
            onClick={() => setFaqAck('no')}
            className={`rounded-lg px-4 py-2 text-sm font-medium border transition-colors
              ${faqAck === 'no' ? 'border-yellow-500 bg-yellow-500/10 text-foreground' : 'border-border text-muted-foreground hover:text-foreground'}`}
          >
            {L('还没有', 'Not yet')}
          </button>
        </div>
        {faqAck === 'no' && (
          <div className="mt-4 flex items-start gap-2 rounded-lg bg-yellow-500/10 border border-yellow-500/20 p-3">
            <AlertCircle className="h-4 w-4 text-yellow-400 mt-0.5 shrink-0" />
            <p className="text-sm text-muted-foreground">
              {L('建议先查阅 FAQ，大部分连接、节点与解锁问题都能在几分钟内解决。查阅后如仍需退款，再回来选择「已查阅」继续。',
                 'We recommend checking the FAQ first — most connection, node, and unblocking issues are solved in minutes. If you still need a refund afterwards, come back and select “Yes, I have”.')}
            </p>
          </div>
        )}
      </div>

      {/* Step 2 — Reason (unlocked after FAQ ack) */}
      {faqAck === 'yes' && (
        <div className="glass-panel rounded-2xl p-6">
          <h2 className="font-semibold text-foreground mb-4">
            2. {L('请选择退款原因', 'Select your refund reason')}
          </h2>
          <div className="space-y-5">
            {groups.map(([groupName, reasons]) => (
              <div key={groupName}>
                <p className="text-xs font-mono uppercase tracking-widest text-muted-foreground mb-2">{groupName}</p>
                <div className="space-y-2">
                  {reasons.map(r => (
                    <label
                      key={r.code}
                      className={`flex items-start gap-3 rounded-lg border px-3 py-2.5 cursor-pointer transition-colors
                        ${reasonCode === r.code ? 'border-mirror bg-mirror/5' : 'border-border hover:bg-accent/5'}`}
                    >
                      <input
                        type="radio"
                        name="reason"
                        value={r.code}
                        checked={reasonCode === r.code}
                        onChange={() => setReason(r.code)}
                        className="mt-1 accent-mirror"
                      />
                      <span className="text-sm text-foreground">
                        <span className="mr-1.5">{r.emoji}</span>{isZh ? r.zh : r.en}
                      </span>
                    </label>
                  ))}
                </div>
              </div>
            ))}
          </div>

          {/* Dynamic retention message */}
          {reason && (
            <div className="mt-5 flex items-start gap-2 rounded-lg bg-mirror/10 border border-mirror/20 p-4">
              <span className="text-lg leading-none">💡</span>
              <p className="text-sm text-foreground/90 leading-relaxed">
                {isZh ? reason.retentionZh : reason.retentionEn}
              </p>
            </div>
          )}
        </div>
      )}

      {/* Step 3 — Details + screenshot + email */}
      {faqAck === 'yes' && reason && (
        <div className="glass-panel rounded-2xl p-6 space-y-4">
          <h2 className="font-semibold text-foreground">
            3. {L('补充说明与凭证', 'Details & evidence')}
          </h2>

          <div>
            <label className="block text-sm text-muted-foreground mb-1.5">
              {L('具体原因（必填）', 'Describe your issue (required)')}
            </label>
            <textarea
              value={detail}
              onChange={e => setDetail(e.target.value)}
              rows={4}
              placeholder={L('请描述你遇到的问题，如地区、运营商、节点名称、出现的现象等，便于我们快速处理。',
                             'Please describe the issue — region, ISP, node name, what happened — so we can help quickly.')}
              className="w-full rounded-lg border border-border bg-background/50 px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:border-mirror focus:outline-none"
            />
          </div>

          <div>
            <label className="block text-sm text-muted-foreground mb-1.5">
              {L('上传截图（问题现象，选填但强烈建议）', 'Upload a screenshot (optional but recommended)')}
            </label>
            <label className="flex items-center gap-2 rounded-lg border border-dashed border-border px-3 py-2.5 text-sm text-muted-foreground cursor-pointer hover:border-mirror/50 transition-colors">
              <Upload className="h-4 w-4" />
              {file ? file.name : L('选择图片文件（≤5MB）', 'Choose an image (≤5MB)')}
              <input
                type="file"
                accept="image/*"
                className="hidden"
                onChange={e => setFile(e.target.files?.[0] ?? null)}
              />
            </label>
          </div>

          <div>
            <label className="block text-sm text-muted-foreground mb-1.5">
              {L('订阅邮箱（必填）', 'Subscription email (required)')}
            </label>
            <input
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="w-full rounded-lg border border-border bg-background/50 px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:border-mirror focus:outline-none"
            />
          </div>
        </div>
      )}

      {/* Step 4 — Device type */}
      {faqAck === 'yes' && reason && (
        <div className="glass-panel rounded-2xl p-6 space-y-4">
          <h2 className="font-semibold text-foreground">
            4. {L('终端类型', 'Device type')}
          </h2>
          <p className="text-sm text-muted-foreground -mt-2">
            {L('请选择你使用的平台与机型，帮助我们更快定位问题。', 'Select your platform and device so we can pinpoint the issue faster.')}
          </p>

          {/* platform */}
          <div className="flex flex-wrap gap-2">
            {DEVICE_GROUPS.map(g => (
              <button
                key={g.key}
                onClick={() => { setPlatform(g.key); setModel('') }}
                className={`rounded-lg px-4 py-2 text-sm font-medium border transition-colors
                  ${platform === g.key ? 'border-mirror bg-mirror/10 text-foreground' : 'border-border text-muted-foreground hover:text-foreground'}`}
              >
                {isZh ? g.zh : g.en}
              </button>
            ))}
          </div>

          {/* model (depends on platform) */}
          {group && (
            <div className="flex flex-wrap gap-2">
              {group.models.map(m => (
                <button
                  key={m.v}
                  onClick={() => setModel(m.v)}
                  className={`rounded-lg px-3 py-1.5 text-sm border transition-colors
                    ${model === m.v ? 'border-mirror bg-mirror/5 text-foreground' : 'border-border text-muted-foreground hover:text-foreground'}`}
                >
                  {isZh ? m.zh : m.en}
                </button>
              ))}
            </div>
          )}

          {error && (
            <div className="flex items-center gap-2 text-sm text-red-400">
              <AlertCircle className="h-4 w-4" /> {error}
            </div>
          )}

          <div className="flex items-center justify-between pt-2">
            <Link href="/dashboard/billing" className="text-sm text-muted-foreground hover:text-foreground">
              {L('放弃退款，返回', 'Cancel & go back')}
            </Link>
            <button
              onClick={submit}
              disabled={submitting}
              className="btn-primary text-sm disabled:opacity-50"
            >
              {submitting ? L('提交中…', 'Submitting…') : L('提交退款申请', 'Submit refund request')}
            </button>
          </div>
          <p className="text-xs text-muted-foreground">
            {L('提交申请不代表立即退款。我们会人工审核后通过邮件与你联系。',
               'Submitting a request does not mean an instant refund. We’ll review it manually and contact you by email.')}
          </p>
        </div>
      )}
    </div>
  )
}
