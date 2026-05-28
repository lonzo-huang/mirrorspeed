'use client'

import { SiteNav }    from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n }    from '@/lib/i18n'

const SECTIONS = [
  {
    h: "1. Information We Collect",
    p: "We collect only the minimum information necessary to provide the Service: your email address (for authentication), payment information processed by Stripe (we never see your full card details), and basic device metadata (OS type, device label) required to provision your VPN configuration. We do not collect browsing history, DNS queries, IP addresses, traffic destinations, or connection timestamps.",
  },
  {
    h: "2. How We Use Your Information",
    p: "Your email is used solely for authentication, transactional emails (subscription confirmation, renewal reminders), and customer support. Payment data is processed by Stripe under their Privacy Policy. Device metadata is used to generate your WireGuard configuration and enforce device limits.",
  },
  {
    h: "3. No-Logs VPN Policy",
    p: "MirrorSpeed operates a strict no-logs policy for VPN traffic. We do not record, monitor, or store: the websites you visit, the content of your communications, your real IP address while connected, DNS queries made through the VPN, or connection timestamps. This policy has been independently audited.",
  },
  {
    h: "4. Data Sharing",
    p: "We do not sell, rent, or trade your personal data to any third parties. We share data only with: Stripe (payment processing), Supabase (database infrastructure, subject to their DPA), Brevo (transactional email delivery), and Vercel (hosting infrastructure). All sub-processors are GDPR-compliant.",
  },
  {
    h: "5. Data Retention",
    p: "Account data is retained for the duration of your account and deleted within 30 days of account closure upon request. Payment records are retained for 7 years as required by financial regulations. VPN configuration data is deleted immediately upon device removal.",
  },
  {
    h: "6. Your Rights (GDPR / CCPA)",
    p: "You have the right to access, correct, or delete your personal data at any time. You may request a copy of your data or ask for account deletion by emailing support@mirrorspeed.com. We will respond within 30 days. California residents have additional rights under CCPA.",
  },
  {
    h: "7. Security",
    p: "All data in transit is encrypted using TLS 1.3. VPN private keys are encrypted at rest using AES-256. We use Supabase Row-Level Security to ensure users can only access their own data. Payment data never touches our servers — it is handled entirely by Stripe's PCI-DSS-certified infrastructure.",
  },
  {
    h: "8. Cookies",
    p: "We use only essential cookies required for authentication (session tokens). We do not use advertising, analytics, or tracking cookies. See our Cookie Policy for full details.",
  },
  {
    h: "9. Children's Privacy",
    p: "MirrorSpeed is not directed at children under 16. We do not knowingly collect personal data from minors. If you believe a child has provided us with personal data, please contact support@mirrorspeed.com.",
  },
  {
    h: "10. Changes to This Policy",
    p: "We may update this Privacy Policy from time to time. Material changes will be notified via email or a prominent notice on our website at least 30 days before taking effect.",
  },
  {
    h: "11. Contact",
    p: "For privacy-related inquiries, contact us at: privacy@mirrorspeed.com or Mirror Group International, support@mirrorspeed.com.",
  },
]

export default function PrivacyPage() {
  const { t } = useI18n()
  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <article className="max-w-3xl mx-auto">
          <p className="text-[11px] font-mono uppercase tracking-widest text-muted-foreground mb-3">Last updated: May 28, 2026</p>
          <h1 className="text-4xl md:text-5xl font-bold tracking-tighter mb-6">Privacy Policy</h1>
          <p className="text-muted-foreground text-lg mb-12">
            MirrorSpeed is committed to protecting your privacy. This policy explains what data we collect, how we use it, and your rights regarding your personal information.
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
