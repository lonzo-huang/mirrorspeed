'use client'

import Link from "next/link";
import { useI18n } from "@/lib/i18n";

export function SiteFooter() {
  const { t } = useI18n();
  return (
    <footer className="py-20 px-6 border-t border-border mt-24">
      <div className="max-w-6xl mx-auto grid md:grid-cols-4 gap-12">
        <div className="md:col-span-2 max-w-sm">
          <span className="text-lg font-extrabold tracking-tighter uppercase block mb-4">MirrorSpeed</span>
          <p className="text-sm text-muted-foreground">{t.footer.tagline}</p>
        </div>
        <div>
          <h5 className="text-[11px] font-bold text-muted-foreground uppercase tracking-widest mb-4">{t.footer.product}</h5>
          <ul className="text-sm space-y-2">
            <li><Link href="/servers"  className="hover:text-mirror transition-colors">{t.nav.servers}</Link></li>
            <li><Link href="/pricing"  className="hover:text-mirror transition-colors">{t.nav.pricing}</Link></li>
            <li><Link href="/download" className="hover:text-mirror transition-colors">{t.nav.download}</Link></li>
          </ul>
        </div>
        <div>
          <h5 className="text-[11px] font-bold text-muted-foreground uppercase tracking-widest mb-4">{t.footer.legal}</h5>
          <ul className="text-sm space-y-2 text-foreground/80">
            <li><Link href="/terms"      className="hover:text-mirror transition-colors">Terms of Service</Link></li>
            <li><Link href="/privacy"    className="hover:text-mirror transition-colors">Privacy Policy</Link></li>
            <li><Link href="/cookies"    className="hover:text-mirror transition-colors">Cookie Policy</Link></li>
            <li><Link href="/disclaimer" className="hover:text-mirror transition-colors">{t.footer.disclaimer}</Link></li>
          </ul>
        </div>
      </div>
      <div className="max-w-6xl mx-auto mt-16 pt-8 border-t border-white/5 text-[10px] text-muted-foreground uppercase tracking-widest font-mono flex justify-between">
        <span>© 2026 Mirror Group International</span>
        <span>Protocol: Mirror v2.4 · WireGuard</span>
      </div>
    </footer>
  );
}
