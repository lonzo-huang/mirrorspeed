'use client'

import Link from 'next/link'
import { CheckCircle, ArrowRight } from 'lucide-react'

export default function CheckoutSuccessPage() {
  return (
    <div className="min-h-screen bg-background text-foreground flex items-center justify-center px-6">
      <div className="max-w-md w-full text-center">
        <div className="inline-flex items-center justify-center w-20 h-20 rounded-full bg-mirror/10 border border-mirror/20 mb-6 mx-auto">
          <CheckCircle className="w-10 h-10 text-mirror" />
        </div>
        <h1 className="text-4xl font-extrabold tracking-tight mb-3">
          Payment Successful
        </h1>
        <p className="text-muted-foreground mb-8 text-lg">
          Welcome to MirrorSpeed. Your subscription is now active. Check your
          email for setup instructions and your Clash subscription URL.
        </p>
        <div className="glass-panel rounded-2xl p-6 mb-8 text-left space-y-3 text-sm">
          {[
            'Check your email for a confirmation receipt from Stripe.',
            'Log in to your dashboard to copy your Clash subscription URL.',
            'Download a client and paste your URL to connect instantly.',
          ].map((step, i) => (
            <div key={i} className="flex items-start gap-3">
              <span className="w-5 h-5 rounded-full bg-mirror/20 border border-mirror/30 flex items-center justify-center flex-shrink-0 mt-0.5">
                <span className="w-2 h-2 bg-mirror rounded-full" />
              </span>
              <span className="text-foreground/80">{step}</span>
            </div>
          ))}
        </div>
        <div className="flex flex-col sm:flex-row gap-3 justify-center">
          <Link
            href="/dashboard"
            className="group inline-flex items-center justify-center gap-2 px-6 py-3 bg-primary text-primary-foreground font-bold rounded-xl hover:shadow-[0_0_30px_color-mix(in_oklab,var(--color-mirror)_40%,transparent)] transition-all"
          >
            Go to Dashboard
            <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
          </Link>
          <Link
            href="/download"
            className="inline-flex items-center justify-center gap-2 px-6 py-3 glass-panel font-bold rounded-xl hover:bg-white/10 transition-all"
          >
            Download Client
          </Link>
        </div>
      </div>
    </div>
  )
}
