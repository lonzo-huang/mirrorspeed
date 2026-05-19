'use client'

import Link from 'next/link'
import { XCircle } from 'lucide-react'

export default function CheckoutCancelPage() {
  return (
    <div className="min-h-screen bg-background text-foreground flex items-center justify-center px-6">
      <div className="max-w-md w-full text-center">
        <div className="inline-flex items-center justify-center w-20 h-20 rounded-full bg-white/5 border border-white/10 mb-6 mx-auto">
          <XCircle className="w-10 h-10 text-muted-foreground" />
        </div>
        <h1 className="text-4xl font-extrabold tracking-tight mb-3">
          Payment Cancelled
        </h1>
        <p className="text-muted-foreground mb-8 text-lg">
          No charges were made. You can go back and choose a plan whenever you&apos;re ready.
        </p>
        <div className="flex flex-col sm:flex-row gap-3 justify-center">
          <Link
            href="/pricing"
            className="inline-flex items-center justify-center gap-2 px-6 py-3 bg-primary text-primary-foreground font-bold rounded-xl transition-all"
          >
            View Plans
          </Link>
          <Link
            href="/"
            className="inline-flex items-center justify-center gap-2 px-6 py-3 glass-panel font-bold rounded-xl hover:bg-white/10 transition-all"
          >
            Back to Home
          </Link>
        </div>
      </div>
    </div>
  )
}
