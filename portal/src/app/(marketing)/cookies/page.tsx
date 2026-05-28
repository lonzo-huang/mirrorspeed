'use client'

import { SiteNav }    from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'

const SECTIONS = [
  {
    h: "What Are Cookies?",
    p: "Cookies are small text files stored on your device when you visit a website. They help the site remember information about your visit, such as your login session. MirrorSpeed uses cookies sparingly and only where necessary.",
  },
  {
    h: "Cookies We Use",
    p: "We use only strictly necessary cookies to operate the Service:\n\n• Authentication cookies (sb-*): Set by Supabase to maintain your login session. These are essential for you to stay logged in and access your dashboard. They expire when you log out or after 60 days of inactivity.\n\n• CSRF protection tokens: Short-lived tokens that protect form submissions from cross-site request forgery attacks.\n\nWe do not use advertising cookies, tracking pixels, analytics cookies, or any third-party marketing cookies.",
  },
  {
    h: "Cookies We Do NOT Use",
    p: "MirrorSpeed does not use: Google Analytics, Facebook Pixel, advertising networks, remarketing cookies, A/B testing tools, or any third-party tracking services. Your browsing behavior on our site is not tracked or profiled.",
  },
  {
    h: "Local Storage",
    p: "In addition to cookies, we use browser localStorage to remember your language preference (key: ms-lang). This data never leaves your device and is not transmitted to our servers.",
  },
  {
    h: "Managing Cookies",
    p: "Since we only use essential cookies, disabling them will prevent you from logging in to the Service. You can manage cookies through your browser settings:\n\n• Chrome: Settings → Privacy and Security → Cookies\n• Firefox: Settings → Privacy & Security → Cookies and Site Data\n• Safari: Preferences → Privacy → Manage Website Data\n• Edge: Settings → Cookies and Site Permissions",
  },
  {
    h: "Third-Party Services",
    p: "Our payment processor Stripe may set cookies during the checkout process to prevent fraud and ensure payment security. These cookies are governed by Stripe's Cookie Policy. We do not control or have access to these cookies.",
  },
  {
    h: "Updates to This Policy",
    p: "We may update this Cookie Policy from time to time. Any changes will be posted on this page with an updated date.",
  },
  {
    h: "Contact",
    p: "For questions about our use of cookies, contact us at support@mirrorspeed.com.",
  },
]

export default function CookiesPage() {
  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <article className="max-w-3xl mx-auto">
          <p className="text-[11px] font-mono uppercase tracking-widest text-muted-foreground mb-3">Last updated: May 28, 2026</p>
          <h1 className="text-4xl md:text-5xl font-bold tracking-tighter mb-6">Cookie Policy</h1>
          <p className="text-muted-foreground text-lg mb-12">
            We believe in a privacy-first web. MirrorSpeed uses only essential cookies — no trackers, no ads, no profiling.
          </p>
          <div className="space-y-4">
            {SECTIONS.map((s, i) => (
              <section key={i} className="glass-panel rounded-2xl p-6">
                <h2 className="text-lg font-bold mb-3">{s.h}</h2>
                <p className="text-sm text-foreground/80 leading-relaxed whitespace-pre-line">{s.p}</p>
              </section>
            ))}
          </div>
        </article>
      </main>
      <SiteFooter />
    </div>
  )
}
