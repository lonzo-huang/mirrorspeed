'use client'

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { ChevronDown, Globe, Menu, X } from "lucide-react";
import { useI18n, type Lang } from "@/lib/i18n";

const LANG_OPTIONS: { code: Lang; label: string; native: string }[] = [
  { code: "en", label: "English",    native: "EN" },
  { code: "zh", label: "中文",       native: "中文" },
  { code: "de", label: "Deutsch",    native: "DE" },
  { code: "fr", label: "Français",   native: "FR" },
  { code: "it", label: "Italiano",   native: "IT" },
  { code: "es", label: "Español",    native: "ES" },
  { code: "uk", label: "Українська", native: "УК" },
  { code: "ja", label: "日本語",     native: "JA" },
];

function LangPicker() {
  const { lang, setLang } = useI18n();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, []);

  const current = LANG_OPTIONS.find((o) => o.code === lang) ?? LANG_OPTIONS[0];

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1.5 bg-white/5 hover:bg-white/10 border border-white/10 rounded-full px-3 py-1.5 text-[11px] font-bold uppercase tracking-widest transition-colors"
      >
        <Globe className="w-3 h-3 text-muted-foreground" />
        <span>{current.native}</span>
        <ChevronDown className={`w-3 h-3 text-muted-foreground transition-transform ${open ? "rotate-180" : ""}`} />
      </button>

      {open && (
        <div className="absolute right-0 top-full mt-2 w-40 glass-panel rounded-xl py-1 shadow-xl z-50 overflow-hidden">
          {LANG_OPTIONS.map((opt) => (
            <button
              key={opt.code}
              onClick={() => { setLang(opt.code); setOpen(false); }}
              className={`w-full text-left px-4 py-2 text-sm flex items-center justify-between transition-colors hover:bg-white/5 ${
                lang === opt.code ? "text-foreground font-semibold" : "text-muted-foreground"
              }`}
            >
              <span>{opt.label}</span>
              {lang === opt.code && <span className="w-1.5 h-1.5 rounded-full bg-mirror inline-block" />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export function SiteNav() {
  const { t } = useI18n();
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);

  const navLink = (href: string, label: string, mobile = false) => (
    <Link
      href={href}
      onClick={() => setMobileOpen(false)}
      className={`hover:text-foreground transition-colors ${
        mobile ? "block py-3 text-base border-b border-white/5" : ""
      } ${pathname === href ? "text-foreground" : "text-muted-foreground"}`}
    >
      {label}
    </Link>
  );

  return (
    <nav className="sticky top-0 z-50 glass-panel border-b border-border">
      {/* ── 主导航栏 ── */}
      <div className="py-3 px-6 flex items-center justify-between">
        <div className="flex items-center gap-8">
          <Link href="/" className="text-lg font-extrabold tracking-tighter uppercase">
            MirrorSpeed
          </Link>
          {/* 桌面导航链接 */}
          <div className="hidden md:flex gap-6 text-sm font-medium">
            {navLink("/servers",  t.nav.servers)}
            {navLink("/pricing",  t.nav.pricing)}
            {navLink("/download", t.nav.download)}
            <a href="/#faq" className="text-muted-foreground hover:text-foreground transition-colors">{t.nav.faq}</a>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <LangPicker />
          <div className="h-4 w-px bg-border hidden md:block" />
          <Link href="/login" className="hidden md:block text-sm font-medium text-muted-foreground hover:text-foreground transition-colors">{t.nav.login}</Link>
          <Link href="/login" className="hidden md:block text-sm font-semibold bg-primary text-primary-foreground px-4 py-2 rounded-full hover:bg-mirror transition-all">{t.nav.signup}</Link>
          {/* 移动端汉堡按钮 */}
          <button
            className="md:hidden p-2 rounded-lg hover:bg-white/5 transition-colors"
            onClick={() => setMobileOpen(v => !v)}
            aria-label="Toggle menu"
          >
            {mobileOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </div>

      {/* ── 移动端下拉菜单 ── */}
      {mobileOpen && (
        <div className="md:hidden px-6 pb-4 text-sm font-medium border-t border-white/5">
          {navLink("/servers",  t.nav.servers,  true)}
          {navLink("/pricing",  t.nav.pricing,  true)}
          {navLink("/download", t.nav.download, true)}
          <a href="/#faq" onClick={() => setMobileOpen(false)} className="block py-3 text-base border-b border-white/5 text-muted-foreground hover:text-foreground transition-colors">{t.nav.faq}</a>
          <div className="flex gap-3 pt-4">
            <Link href="/login" onClick={() => setMobileOpen(false)} className="flex-1 text-center py-2.5 border border-white/15 rounded-xl text-sm font-medium text-muted-foreground hover:text-foreground transition-colors">{t.nav.login}</Link>
            <Link href="/login" onClick={() => setMobileOpen(false)} className="flex-1 text-center py-2.5 bg-primary text-primary-foreground rounded-xl text-sm font-bold hover:bg-mirror transition-all">{t.nav.signup}</Link>
          </div>
        </div>
      )}
    </nav>
  );
}
