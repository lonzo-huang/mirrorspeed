'use client'

import { LandingChrome } from '@/components/landing/LandingPage'
import { useI18n }    from '@/lib/i18n'

const CONTACT = 'https://mirrorspeed.com/support'

const SECTIONS_EN = [
  { h: "1. Information We Collect", p: "We collect only the minimum information necessary to provide the Service: your email address (for authentication), payment information processed by Stripe or Apple (we never see your full card details), basic device metadata (OS type, device label) required to provision your VPN configuration, and an aggregate traffic counter per device (total bytes transferred) used solely to enforce free-tier daily quotas and device limits. That counter is a number of bytes only — it does not record what you accessed, when, or from where. We do not collect browsing history, DNS queries, your real IP address while connected, traffic destinations, or per-connection timestamps." },
  { h: "2. How We Use Your Information", p: "Your email is used solely for authentication, transactional emails (subscription confirmation, renewal reminders), and customer support. Payment data is processed by Stripe under their Privacy Policy. Device metadata is used to generate your MirrorSpeed configuration and enforce device limits." },
  { h: "3. No-Logs VPN Policy", p: "MirrorSpeed operates a strict no-logs policy for VPN traffic. We do not record, monitor, or store: the websites you visit, the content of your communications, your real IP address while connected, DNS queries made through the VPN, or connection timestamps." },
  { h: "4. Data Sharing", p: "We do not sell, rent, or trade your personal data to any third parties. We share data only with: Stripe and Apple (payment processing), Supabase (database infrastructure, subject to their DPA), Brevo (transactional email delivery), Vercel (hosting infrastructure), and Google AdMob (advertising on the free tier only — see the Advertising section below). All sub-processors are GDPR-compliant. No VPN traffic data is shared with anyone, because none is collected." },
  { h: "5. Data Retention", p: "Account data is retained for the duration of your account and deleted within 30 days of account closure upon request. Payment records are retained for 7 years as required by financial regulations. VPN configuration data is deleted immediately upon device removal." },
  { h: "6. Your Rights (GDPR / CCPA)", p: `You have the right to access, correct, or delete your personal data at any time. You may request a copy of your data or ask for account deletion by submitting a request at ${CONTACT}. We will respond within 30 days. California residents have additional rights under CCPA.` },
  { h: "7. Security", p: "All data in transit is encrypted using TLS 1.3. VPN private keys are encrypted at rest using AES-256. We use Supabase Row-Level Security to ensure users can only access their own data. Payment data never touches our servers — it is handled entirely by Stripe's PCI-DSS-certified infrastructure." },
  { h: "8. Cookies", p: "Our website uses only essential cookies required for authentication (session tokens). We do not use advertising, analytics, or tracking cookies on the website. Advertising in the mobile app is covered in the Advertising section below. See our Cookie Policy for full details." },
  { h: "9. Advertising (Free Tier)", p: "Free users may watch optional rewarded video ads to extend their daily usage time. These ads are served by Google AdMob, which may access your device's advertising identifier to deliver and measure ads. On iOS and macOS we request your permission through App Tracking Transparency before any tracking occurs; if you decline, ads are still available but non-personalised. Paid subscribers see no ads and no advertising identifier is accessed. Ads are never shown based on your VPN traffic — we do not have that data. See Google's privacy policy for how AdMob processes advertising data." },
  { h: "10. Children's Privacy", p: `MirrorSpeed is not directed at children under 16. We do not knowingly collect personal data from minors. If you believe a child has provided us with personal data, please contact ${CONTACT}.` },
  { h: "11. Changes to This Policy", p: "We may update this Privacy Policy from time to time. Material changes will be notified via email or a prominent notice on our website at least 30 days before taking effect." },
  { h: "12. Contact", p: `For privacy-related inquiries, contact us at: ${CONTACT}.` },
]

const SECTIONS_ZH = [
  { h: "1. 我们收集的信息", p: "我们仅收集提供服务所需的最少信息：您的电子邮件地址（用于身份验证）、Stripe 或 Apple 处理的付款信息（我们从不看到您的完整卡片详情）、提供加速配置所需的基本设备元数据（操作系统类型、设备标签），以及每台设备的累计流量计数（已传输的总字节数），仅用于执行免费额度与设备数量限制。该计数只是一个字节数，不记录您访问了什么、何时访问、从何处访问。我们不收集浏览历史、DNS 查询、您连接时的真实 IP 地址、流量目的地或单次连接的时间戳。" },
  { h: "2. 我们如何使用您的信息", p: "您的电子邮件仅用于身份验证、交易性邮件（订阅确认、续费提醒）和客户支持。付款数据由 Stripe 根据其隐私政策处理。设备元数据用于生成您的 MirrorSpeed 配置并执行设备限制。" },
  { h: "3. VPN 零日志政策", p: "MirrorSpeed 对 VPN 流量执行严格的零日志政策。我们不记录、监控或存储：您访问的网站、您的通信内容、您连接时的真实 IP 地址、通过 VPN 进行的 DNS 查询或连接时间戳。此政策已经过" },
  { h: "4. 数据共享", p: "我们不向任何第三方出售、出租或交易您的个人数据。我们仅与以下方共享数据：Stripe 与 Apple（付款处理）、Supabase（数据库基础设施，受其 DPA 约束）、Brevo（交易性电子邮件投递）、Vercel（托管基础设施），以及 Google AdMob（仅免费档的广告投放，详见下文「广告」）。所有子处理器均符合 GDPR。我们不与任何人共享流量数据——因为我们根本不收集。" },
  { h: "5. 数据保留", p: "账户数据在您账户存续期间保留，应要求在账户关闭后 30 天内删除。付款记录根据财务法规保留 7 年。VPN 配置数据在设备移除后立即删除。" },
  { h: "6. 您的权利（GDPR / CCPA）", p: `您有权随时访问、更正或删除您的个人数据。您可以通过 ${CONTACT} 提交申请，请求您的数据副本或账户删除。我们将在 30 天内回复。加利福尼亚州居民在 CCPA 下享有额外权利。` },
  { h: "7. 安全", p: "所有传输中的数据均使用 TLS 1.3 加密。VPN 私钥在存储时使用 AES-256 加密。我们使用 Supabase 行级安全性确保用户只能访问自己的数据。付款数据从不接触我们的服务器——完全由 Stripe 的 PCI-DSS 认证基础设施处理。" },
  { h: "8. Cookie", p: "我们的网站仅使用身份验证所需的必要 Cookie（会话令牌），不使用广告、分析或跟踪 Cookie。App 内的广告见下文「广告」一节。详情请参阅我们的 Cookie 政策。" },
  { h: "9. 广告（仅免费档）", p: "免费用户可自愿观看激励视频广告以延长当日可用时长。广告由 Google AdMob 投放，AdMob 可能读取设备的广告标识符用于投放与效果统计。在 iOS 与 macOS 上，我们会先通过「App 跟踪透明度」征求您的授权；若您拒绝，仍可观看广告，只是广告不再个性化。付费订阅用户不展示任何广告，也不会读取广告标识符。广告投放从不基于您的加速流量——我们没有这类数据。AdMob 如何处理广告数据，请参阅 Google 的隐私政策。" },
  { h: "10. 儿童隐私", p: `MirrorSpeed 不面向 16 岁以下的儿童。我们不会故意收集未成年人的个人数据。如果您认为儿童向我们提供了个人数据，请联系 ${CONTACT}。` },
  { h: "11. 政策变更", p: "我们可能会不时更新本隐私政策。重大变更将通过电子邮件或我们网站上的显著通知在生效前至少 30 天通知。" },
  { h: "12. 联系方式", p: `如有隐私相关问题，请联系我们：${CONTACT}。` },
]

export default function PrivacyView() {
  const { lang } = useI18n()
  const isZh = lang === 'zh'
  const SECTIONS = isZh ? SECTIONS_ZH : SECTIONS_EN

  return (
    <LandingChrome forcedLang={isZh ? 'zh' : 'en'}>
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {isZh ? '隐私' : 'Privacy'}
            </span>
            <p className="text-[11px] font-mono uppercase tracking-widest text-app-muted mb-3">
              {isZh ? '最后更新：2026 年 5 月 28 日' : 'Last updated: May 28, 2026'}
            </p>
            <h1 className="font-heading text-4xl md:text-6xl font-black tracking-tighter mb-6">
              <span className="text-gradient-cyan">{isZh ? '隐私政策' : 'Privacy Policy'}</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto">
              {isZh
                ? 'MirrorSpeed 致力于保护您的隐私。本政策说明我们收集哪些数据、如何使用数据，以及您对个人信息的权利。'
                : 'MirrorSpeed is committed to protecting your privacy. This policy explains what data we collect, how we use it, and your rights regarding your personal information.'}
            </p>
          </div>
          <div className="space-y-4">
            {SECTIONS.map((s, i) => (
              <section key={i} className="glass-panel rounded-2xl p-6">
                <h2 className="text-lg font-bold mb-3">{s.h}</h2>
                <p className="text-sm text-foreground/80 leading-relaxed">{s.p}</p>
              </section>
            ))}
          </div>
        </article>
      </main>
    </LandingChrome>
  )
}
