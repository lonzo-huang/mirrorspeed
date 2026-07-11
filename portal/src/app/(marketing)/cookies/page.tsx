'use client'

import { LandingChrome } from '@/components/landing/LandingPage'
import { useI18n }    from '@/lib/i18n'

const CONTACT = 'https://mirrorspeed.com/support'

const SECTIONS_EN = [
  { h: "What Are Cookies?", p: "Cookies are small text files stored on your device when you visit a website. They help the site remember information about your visit, such as your login session. MirrorSpeed uses cookies sparingly and only where necessary." },
  { h: "Cookies We Use", p: "We use only strictly necessary cookies to operate the Service:\n\n• Authentication cookies (sb-*): Set by Supabase to maintain your login session. These are essential for you to stay logged in and access your dashboard. They expire when you log out or after 60 days of inactivity.\n\n• CSRF protection tokens: Short-lived tokens that protect form submissions from cross-site request forgery attacks.\n\nWe do not use advertising cookies, tracking pixels, analytics cookies, or any third-party marketing cookies." },
  { h: "Cookies We Do NOT Use", p: "MirrorSpeed does not use: Google Analytics, Facebook Pixel, advertising networks, remarketing cookies, A/B testing tools, or any third-party tracking services. Your browsing behavior on our site is not tracked or profiled." },
  { h: "Local Storage", p: "In addition to cookies, we use browser localStorage to remember your language preference (key: ms-lang). This data never leaves your device and is not transmitted to our servers." },
  { h: "Managing Cookies", p: "Since we only use essential cookies, disabling them will prevent you from logging in to the Service. You can manage cookies through your browser settings:\n\n• Chrome: Settings → Privacy and Security → Cookies\n• Firefox: Settings → Privacy & Security → Cookies and Site Data\n• Safari: Preferences → Privacy → Manage Website Data\n• Edge: Settings → Cookies and Site Permissions" },
  { h: "Third-Party Services", p: "Our payment processor Stripe may set cookies during the checkout process to prevent fraud and ensure payment security. These cookies are governed by Stripe's Cookie Policy. We do not control or have access to these cookies." },
  { h: "Updates to This Policy", p: "We may update this Cookie Policy from time to time. Any changes will be posted on this page with an updated date." },
  { h: "Contact", p: `For questions about our use of cookies, contact us at ${CONTACT}.` },
]

const SECTIONS_ZH = [
  { h: "什么是 Cookie？", p: "Cookie 是您访问网站时存储在设备上的小型文本文件。它们帮助网站记住您访问的信息，例如您的登录会话。MirrorSpeed 仅在必要时才使用 Cookie。" },
  { h: "我们使用的 Cookie", p: "我们仅使用运营服务所需的严格必要 Cookie：\n\n• 身份验证 Cookie（sb-*）：由 Supabase 设置，用于维护您的登录会话。这些对于保持登录状态和访问仪表盘至关重要。在您退出登录或 60 天不活动后过期。\n\n• CSRF 保护令牌：保护表单提交免受跨站请求伪造攻击的短期令牌。\n\n我们不使用广告 Cookie、跟踪像素、分析 Cookie 或任何第三方营销 Cookie。" },
  { h: "我们不使用的 Cookie", p: "MirrorSpeed 不使用：Google Analytics、Facebook Pixel、广告网络、再营销 Cookie、A/B 测试工具或任何第三方跟踪服务。您在我们网站上的浏览行为不会被跟踪或分析。" },
  { h: "本地存储", p: "除 Cookie 外，我们使用浏览器 localStorage 记住您的语言偏好（键：ms-lang）。此数据永远不会离开您的设备，也不会传输到我们的服务器。" },
  { h: "管理 Cookie", p: "由于我们仅使用必要 Cookie，禁用它们将阻止您登录服务。您可以通过浏览器设置管理 Cookie：\n\n• Chrome：设置 → 隐私和安全 → Cookie\n• Firefox：设置 → 隐私与安全 → Cookie 和站点数据\n• Safari：偏好设置 → 隐私 → 管理网站数据\n• Edge：设置 → Cookie 和站点权限" },
  { h: "第三方服务", p: "我们的支付处理商 Stripe 可能在结账过程中设置 Cookie 以防止欺诈并确保支付安全。这些 Cookie 受 Stripe Cookie 政策的管辖。我们无法控制或访问这些 Cookie。" },
  { h: "政策更新", p: "我们可能会不时更新本 Cookie 政策。任何变更都将发布在本页面上，并注明更新日期。" },
  { h: "联系方式", p: `如对我们使用 Cookie 有疑问，请联系我们：${CONTACT}。` },
]

export default function CookiesPage() {
  const { lang } = useI18n()
  const isZh = lang === 'zh'
  const SECTIONS = isZh ? SECTIONS_ZH : SECTIONS_EN

  return (
    <LandingChrome forcedLang={isZh ? 'zh' : 'en'}>
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {isZh ? 'Cookie' : 'Cookies'}
            </span>
            <p className="text-[11px] font-mono uppercase tracking-widest text-app-muted mb-3">
              {isZh ? '最后更新：2026 年 5 月 28 日' : 'Last updated: May 28, 2026'}
            </p>
            <h1 className="font-heading text-4xl md:text-6xl font-black tracking-tighter mb-6">
              <span className="text-gradient-cyan">{isZh ? 'Cookie 政策' : 'Cookie Policy'}</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto">
              {isZh
                ? '我们信奉隐私优先的网络。MirrorSpeed 仅使用必要 Cookie——没有跟踪器、没有广告、没有分析。'
                : 'We believe in a privacy-first web. MirrorSpeed uses only essential cookies — no trackers, no ads, no profiling.'}
            </p>
          </div>
          <div className="space-y-4">
            {SECTIONS.map((s, i) => (
              <section key={i} className="glass-panel rounded-2xl p-6">
                <h2 className="text-lg font-bold mb-3 text-app-primary">{s.h}</h2>
                <p className="text-sm text-app-secondary leading-relaxed whitespace-pre-line">{s.p}</p>
              </section>
            ))}
          </div>
        </article>
      </main>
    </LandingChrome>
  )
}
