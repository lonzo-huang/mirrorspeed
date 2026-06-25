'use client'

import { SiteNav }    from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n }    from '@/lib/i18n'

const CONTACT = 'mirrorspeed@mirrorquant.com'

export default function DeleteAccountPage() {
  const { lang } = useI18n()
  const isZh = lang === 'zh'

  const subject = encodeURIComponent('Delete my MirrorSpeed account')
  const mailto  = `mailto:${CONTACT}?subject=${subject}`

  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <article className="max-w-3xl mx-auto">
          <p className="text-[11px] font-mono uppercase tracking-widest text-muted-foreground mb-3">
            {isZh ? 'MirrorSpeed VPN · 账号删除' : 'MirrorSpeed VPN · Account Deletion'}
          </p>
          <h1 className="text-4xl md:text-5xl font-bold tracking-tighter mb-6">
            {isZh ? '删除你的账号与数据' : 'Delete Your Account & Data'}
          </h1>
          <p className="text-muted-foreground text-lg mb-12">
            {isZh
              ? '本页面说明如何申请删除你的 MirrorSpeed VPN 账号，以及删除后哪些数据会被清除、哪些会按法规保留。'
              : 'This page explains how to request deletion of your MirrorSpeed VPN account, and which data is removed or retained afterwards.'}
          </p>

          <section className="glass-panel rounded-2xl p-6 mb-4">
            <h2 className="text-lg font-bold mb-3">
              {isZh ? '如何申请删除（两种方式）' : 'How to request deletion (two options)'}
            </h2>
            <ol className="list-decimal list-inside space-y-3 text-sm text-foreground/80 leading-relaxed">
              <li>
                {isZh
                  ? '在 App 内：打开「我的」页面 → 点「删除账号」→ 按提示确认。删除请求会立即提交。'
                  : 'In the app: open the "My" tab → tap "Delete account" → confirm. Your request is submitted immediately.'}
              </li>
              <li>
                {isZh ? (
                  <>用注册邮箱发送邮件至 <a href={mailto} className="text-mirror underline">{CONTACT}</a>，
                  标题写「Delete my account」，正文注明你的注册邮箱。我们核实后处理。</>
                ) : (
                  <>Email us from your registered email address at <a href={mailto} className="text-mirror underline">{CONTACT}</a> with
                  the subject "Delete my account", stating your registered email. We will verify and process it.</>
                )}
              </li>
            </ol>
            <p className="text-sm text-foreground/80 leading-relaxed mt-3">
              {isZh
                ? '我们将在收到请求后 30 天内完成账号删除，并以邮件确认。'
                : 'We will complete account deletion within 30 days of the request and confirm by email.'}
            </p>
          </section>

          <section className="glass-panel rounded-2xl p-6 mb-4">
            <h2 className="text-lg font-bold mb-3">
              {isZh ? '会被删除的数据' : 'Data that will be deleted'}
            </h2>
            <ul className="list-disc list-inside space-y-2 text-sm text-foreground/80 leading-relaxed">
              <li>{isZh ? '你的账号与登录信息（邮箱地址）' : 'Your account and sign-in information (email address)'}</li>
              <li>{isZh ? '设备元数据与 VPN 配置（MirrorSpeed 密钥、设备标签）' : 'Device metadata and VPN configuration (MirrorSpeed keys, device labels)'}</li>
              <li>{isZh ? '邀请码、奖励时长等与账号关联的记录' : 'Referral codes, bonus time, and other account-linked records'}</li>
            </ul>
            <p className="text-sm text-foreground/80 leading-relaxed mt-3">
              {isZh
                ? '说明：我们对 VPN 流量执行零日志政策——本就不存储浏览记录、DNS 查询、真实 IP 或连接时间戳，因此无此类数据可删。'
                : 'Note: we operate a strict no-logs VPN policy — we never store browsing history, DNS queries, real IP addresses, or connection timestamps, so there is no such data to delete.'}
            </p>
          </section>

          <section className="glass-panel rounded-2xl p-6">
            <h2 className="text-lg font-bold mb-3">
              {isZh ? '按法规保留的数据' : 'Data retained for legal compliance'}
            </h2>
            <p className="text-sm text-foreground/80 leading-relaxed">
              {isZh
                ? '付款与开票记录将按财务及税务法规保留最长 7 年，此为法律要求，与账号删除无关。该数据仅用于合规审计，不会用于其他目的。除此之外，账号删除后不保留任何个人数据。'
                : 'Payment and invoicing records are retained for up to 7 years as required by financial and tax regulations. This is a legal requirement independent of account deletion, used solely for compliance auditing. Apart from this, no personal data is retained after account deletion.'}
            </p>
            <p className="text-sm text-foreground/80 leading-relaxed mt-3">
              {isZh
                ? <>如有疑问，请联系 <a href={mailto} className="text-mirror underline">{CONTACT}</a>。</>
                : <>For questions, contact <a href={mailto} className="text-mirror underline">{CONTACT}</a>.</>}
            </p>
          </section>
        </article>
      </main>
      <SiteFooter />
    </div>
  )
}
