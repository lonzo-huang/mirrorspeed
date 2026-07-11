'use client'

import { LandingChrome } from '@/components/landing/LandingPage'
import { useI18n }    from '@/lib/i18n'

const CONTACT = 'https://mirrorspeed.com/support'

const SECTIONS_EN = [
  { h: "1. Acceptance of Terms", p: "By accessing or using MirrorSpeed (\"Service\"), you agree to be bound by these Terms of Service (\"Terms\"). If you do not agree to these Terms, do not use the Service. These Terms apply to all users, including free and paid subscribers." },
  { h: "2. Description of Service", p: "MirrorSpeed provides a VPN (Virtual Private Network) service that encrypts your internet traffic and routes it through our global server network. The Service is provided 'as is' and is intended for lawful personal and business use only." },
  { h: "3. Eligibility", p: "You must be at least 16 years old to use the Service. By using the Service, you represent that you meet this requirement and have the legal capacity to enter into these Terms." },
  { h: "4. Account Registration", p: `You must provide a valid email address to create an account. You are responsible for maintaining the security of your account and for all activities that occur under it. You must notify us immediately of any unauthorized use at ${CONTACT}.` },
  { h: "5. Subscription and Payment", p: "Paid plans are billed in advance on a monthly, quarterly, yearly, or biennial basis. All payments are processed securely by Stripe. Prices are displayed in USD; CNY pricing is available for supported payment methods. Subscriptions do not auto-renew — you will be notified before expiry." },
  { h: "6. Refund Policy", p: `We offer a 7-day money-back guarantee on all paid plans. To request a refund, contact ${CONTACT} within 7 days of your initial purchase. Refunds are not available for subsequent billing periods or after the 7-day window.` },
  { h: "7. Acceptable Use", p: "You agree not to use the Service for: (a) any illegal activity under applicable law; (b) unauthorized access to computer systems; (c) distribution of malware, spam, or harmful content; (d) copyright infringement; (e) harassment or abuse of others; (f) activities that could damage, disable, or impair the Service. Violation of these terms will result in immediate account termination without refund." },
  { h: "8. Device Limits", p: "Your subscription allows up to 4 simultaneous device connections. Each device must be individually registered. Attempting to circumvent device limits is a violation of these Terms." },
  { h: "9. Service Availability", p: "We strive for 99.9% uptime but do not guarantee uninterrupted availability. The Service may be temporarily unavailable due to maintenance, upgrades, or circumstances beyond our control. We are not liable for any losses resulting from service interruptions." },
  { h: "10. Intellectual Property", p: "All intellectual property related to the Service, including the MirrorSpeed client software, is owned by Mirror Group International. You are granted a limited, non-exclusive, non-transferable license to use the Service during your subscription period." },
  { h: "11. Privacy", p: "Your use of the Service is governed by our Privacy Policy, which is incorporated into these Terms by reference. We operate a strict no-logs policy for VPN traffic." },
  { h: "12. Limitation of Liability", p: "To the maximum extent permitted by law, Mirror Group International shall not be liable for any indirect, incidental, special, consequential, or punitive damages. Our total liability shall not exceed the amount you paid for the Service in the 12 months preceding the claim." },
  { h: "13. Termination", p: "We may suspend or terminate your account immediately if you violate these Terms. You may cancel your subscription at any time through the billing portal. Upon termination, your access to the Service will cease and your VPN configurations will be deleted." },
  { h: "14. Governing Law", p: "These Terms are governed by applicable international law. Disputes shall be resolved through binding arbitration, except where prohibited by law. If any provision of these Terms is found unenforceable, the remaining provisions remain in full effect." },
  { h: "15. Changes to Terms", p: "We may modify these Terms at any time. Material changes will be communicated via email at least 30 days before taking effect. Continued use of the Service after changes constitutes acceptance." },
  { h: "16. Contact", p: `For questions about these Terms, contact us at ${CONTACT}.` },
]

const SECTIONS_ZH = [
  { h: "1. 接受条款", p: "通过访问或使用 MirrorSpeed（「服务」），您同意受本服务条款（「条款」）的约束。如您不同意本条款，请勿使用本服务。本条款适用于所有用户，包括免费和付费订阅者。" },
  { h: "2. 服务说明", p: "MirrorSpeed 提供 VPN（虚拟专用网络）服务，对您的互联网流量进行加密并通过我们的全球服务器网络路由。本服务按「现状」提供，仅供合法的个人和商业用途。" },
  { h: "3. 使用资格", p: "您必须年满 16 周岁方可使用本服务。使用本服务即表示您满足此要求，且具有签订本条款的法律能力。" },
  { h: "4. 账户注册", p: `您必须提供有效的电子邮件地址才能创建账户。您负责维护账户安全及账户下发生的所有活动。如发现任何未经授权的使用，请立即通知我们：${CONTACT}。` },
  { h: "5. 订阅与付款", p: "付费方案按月、季、年或两年提前计费。所有付款均通过 Stripe 安全处理。价格以美元显示；支持人民币定价的付款方式另有说明。订阅不会自动续费——我们将在到期前通知您。" },
  { h: "6. 退款政策", p: `所有付费方案均提供 7 天无理由退款保证。如需退款，请在首次购买后 7 天内联系 ${CONTACT}。后续计费周期或超过 7 天窗口后不提供退款。退款申请将在 5 个工作日内处理；Stripe 可能会收取退款手续费和汇率损失费，最高 30%。` },
  { h: "7. 可接受使用", p: "您同意不将本服务用于：(a) 任何违反适用法律的非法活动；(b) 未经授权访问计算机系统；(c) 传播恶意软件、垃圾邮件或有害内容；(d) 侵犯版权；(e) 骚扰或虐待他人；(f) 可能损坏、禁用或损害服务的活动。违反本条款将导致账户立即终止且不予退款。" },
  { h: "8. 设备限制", p: "您的订阅允许最多 4 台设备同时连接。每台设备必须单独注册。试图规避设备限制违反本条款。" },
  { h: "9. 服务可用性", p: "我们致力于达到 99.9% 的正常运行时间，但不保证服务不中断。由于维护、升级或超出我们控制范围的情况，服务可能暂时不可用。我们对服务中断造成的任何损失不承担责任。" },
  { h: "10. 知识产权", p: "与本服务相关的所有知识产权，包括 MirrorSpeed 客户端软件，均归 Mirror Group International 所有。在您的订阅期间，您获得使用本服务的有限、非独占、不可转让的许可。" },
  { h: "11. 隐私", p: "您对本服务的使用受我们隐私政策的约束，该政策通过引用并入本条款。我们对 VPN 流量执行严格的零日志政策。" },
  { h: "12. 责任限制", p: "在法律允许的最大范围内，Mirror Group International 不对任何间接、附带、特殊、结果性或惩罚性损害承担责任。我们的总责任不超过您在索赔前 12 个月内为本服务支付的金额。" },
  { h: "13. 终止", p: "如果您违反本条款，我们可能立即暂停或终止您的账户。您可以随时通过账单门户取消订阅。终止后，您对服务的访问将停止，您的 VPN 配置将被删除。" },
  { h: "14. 适用法律", p: "本条款受适用国际法律管辖。争议应通过有约束力的仲裁解决，除非法律禁止。如果本条款的任何条款被认定为不可执行，其余条款仍然完全有效。" },
  { h: "15. 条款变更", p: "我们可能随时修改本条款。重大变更将在生效前至少 30 天通过电子邮件通知。继续使用本服务即构成接受。" },
  { h: "16. 联系方式", p: `如对本条款有疑问，请联系我们：${CONTACT}。` },
]

export default function TermsPage() {
  const { lang } = useI18n()
  const isZh = lang === 'zh'
  const SECTIONS = isZh ? SECTIONS_ZH : SECTIONS_EN

  return (
    <LandingChrome forcedLang={isZh ? 'zh' : 'en'}>
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {isZh ? '条款' : 'Terms'}
            </span>
            <p className="text-[11px] font-mono uppercase tracking-widest text-app-muted mb-3">
              {isZh ? '最后更新：2026 年 5 月 28 日' : 'Last updated: May 28, 2026'}
            </p>
            <h1 className="font-heading text-4xl md:text-6xl font-black tracking-tighter mb-6">
              <span className="text-gradient-cyan">{isZh ? '服务条款' : 'Terms of Service'}</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto">
              {isZh
                ? '在使用 MirrorSpeed 之前，请仔细阅读本服务条款。这些条款管理您对我们 VPN 服务的使用。'
                : 'Please read these Terms of Service carefully before using MirrorSpeed. These terms govern your use of our VPN service.'}
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
