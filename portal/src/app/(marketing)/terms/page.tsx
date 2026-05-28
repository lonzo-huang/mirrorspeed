'use client'

import { SiteNav }    from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n }    from '@/lib/i18n'

const SECTIONS = [
  {
    h: "1. Acceptance of Terms",
    p: "By accessing or using MirrorSpeed (\"Service\"), you agree to be bound by these Terms of Service (\"Terms\"). If you do not agree to these Terms, do not use the Service. These Terms apply to all users, including free and paid subscribers.",
  },
  {
    h: "2. Description of Service",
    p: "MirrorSpeed provides a VPN (Virtual Private Network) service that encrypts your internet traffic and routes it through our global server network. The Service is provided 'as is' and is intended for lawful personal and business use only.",
  },
  {
    h: "3. Eligibility",
    p: "You must be at least 16 years old to use the Service. By using the Service, you represent that you meet this requirement and have the legal capacity to enter into these Terms.",
  },
  {
    h: "4. Account Registration",
    p: "You must provide a valid email address to create an account. You are responsible for maintaining the security of your account and for all activities that occur under it. You must notify us immediately of any unauthorized use at support@mirrorspeed.com.",
  },
  {
    h: "5. Subscription and Payment",
    p: "Paid plans are billed in advance on a monthly, quarterly, yearly, or biennial basis. All payments are processed securely by Stripe. Prices are displayed in USD; CNY pricing is available for supported payment methods. Subscriptions do not auto-renew — you will be notified before expiry.",
  },
  {
    h: "6. Refund Policy",
    p: "We offer a 7-day money-back guarantee on all paid plans. To request a refund, contact support@mirrorspeed.com within 7 days of your initial purchase. Refunds are not available for subsequent billing periods or after the 7-day window.",
  },
  {
    h: "7. Acceptable Use",
    p: "You agree not to use the Service for: (a) any illegal activity under applicable law; (b) unauthorized access to computer systems; (c) distribution of malware, spam, or harmful content; (d) copyright infringement; (e) harassment or abuse of others; (f) activities that could damage, disable, or impair the Service. Violation of these terms will result in immediate account termination without refund.",
  },
  {
    h: "8. Device Limits",
    p: "Your subscription allows up to 3 simultaneous device connections. Each device must be individually registered. Attempting to circumvent device limits is a violation of these Terms.",
  },
  {
    h: "9. Service Availability",
    p: "We strive for 99.9% uptime but do not guarantee uninterrupted availability. The Service may be temporarily unavailable due to maintenance, upgrades, or circumstances beyond our control. We are not liable for any losses resulting from service interruptions.",
  },
  {
    h: "10. Intellectual Property",
    p: "All intellectual property related to the Service, including the MirrorSpeed client software, is owned by Mirror Group International. You are granted a limited, non-exclusive, non-transferable license to use the Service during your subscription period.",
  },
  {
    h: "11. Privacy",
    p: "Your use of the Service is governed by our Privacy Policy, which is incorporated into these Terms by reference. We operate a strict no-logs policy for VPN traffic.",
  },
  {
    h: "12. Limitation of Liability",
    p: "To the maximum extent permitted by law, Mirror Group International shall not be liable for any indirect, incidental, special, consequential, or punitive damages. Our total liability shall not exceed the amount you paid for the Service in the 12 months preceding the claim.",
  },
  {
    h: "13. Termination",
    p: "We may suspend or terminate your account immediately if you violate these Terms. You may cancel your subscription at any time through the billing portal. Upon termination, your access to the Service will cease and your VPN configurations will be deleted.",
  },
  {
    h: "14. Governing Law",
    p: "These Terms are governed by applicable international law. Disputes shall be resolved through binding arbitration, except where prohibited by law. If any provision of these Terms is found unenforceable, the remaining provisions remain in full effect.",
  },
  {
    h: "15. Changes to Terms",
    p: "We may modify these Terms at any time. Material changes will be communicated via email at least 30 days before taking effect. Continued use of the Service after changes constitutes acceptance.",
  },
  {
    h: "16. Contact",
    p: "For questions about these Terms, contact us at support@mirrorspeed.com.",
  },
]

export default function TermsPage() {
  const { t } = useI18n()
  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <article className="max-w-3xl mx-auto">
          <p className="text-[11px] font-mono uppercase tracking-widest text-muted-foreground mb-3">Last updated: May 28, 2026</p>
          <h1 className="text-4xl md:text-5xl font-bold tracking-tighter mb-6">Terms of Service</h1>
          <p className="text-muted-foreground text-lg mb-12">
            Please read these Terms of Service carefully before using MirrorSpeed. These terms govern your use of our VPN service.
          </p>
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
      <SiteFooter />
    </div>
  )
}
