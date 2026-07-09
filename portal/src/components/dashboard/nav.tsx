'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Shield, Monitor, CreditCard, Settings, LogOut, ChevronDown, Globe, Check } from 'lucide-react'
import type { Tables } from '@/types/database.types'
import { useState } from 'react'
import { useI18n, LANG_LABELS, type Lang } from '@/lib/i18n'

type Profile = Tables<'profiles'>

const LANG_ORDER: Lang[] = ['en', 'zh', 'ja', 'de', 'fr', 'it', 'es', 'uk']

export function DashboardNav({ profile }: { profile: Profile }) {
  const { t, lang, setLang } = useI18n()
  const pathname = usePathname()
  const router   = useRouter()
  const supabase = createClient()
  const [menuOpen, setMenuOpen] = useState(false)
  const [langOpen, setLangOpen] = useState(false)

  const NAV_ITEMS = [
    { href: '/dashboard',         label: t.dash.overview,    icon: Shield },
    { href: '/dashboard/devices', label: t.dash.myDevices,   icon: Monitor },
    { href: '/dashboard/billing', label: t.dash.billingNav,  icon: CreditCard },
  ]

  async function signOut() {
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  const initials = (profile.display_name ?? profile.email)
    .split(' ').slice(0, 2).map(s => s[0]?.toUpperCase()).join('')

  return (
    <nav className="relative z-50 border-b border-border bg-background/80 backdrop-blur-sm">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
        {/* Logo */}
        <Link href="/dashboard" className="flex items-center gap-2">
          <Shield className="h-6 w-6 text-mirror" />
          <span className="font-semibold text-foreground hidden sm:block">MirrorSpeed</span>
        </Link>

        {/* Nav links */}
        <div className="hidden sm:flex items-center gap-1">
          {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
            const active = pathname === href || (href !== '/dashboard' && pathname.startsWith(href))
            return (
              <Link
                key={href}
                href={href}
                className={`flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors
                  ${active
                    ? 'text-foreground bg-accent/5'
                    : 'text-muted-foreground hover:bg-accent/5 hover:text-foreground'
                  }`}
              >
                <Icon className="h-4 w-4" />
                {label}
              </Link>
            )
          })}
          {profile.role === 'admin' && (
            <Link
              href="/admin"
              className={`flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors
                ${pathname.startsWith('/admin')
                  ? 'text-foreground bg-accent/5'
                  : 'text-muted-foreground hover:bg-accent/5 hover:text-foreground'
                }`}
            >
              <Settings className="h-4 w-4" />
              {t.dash.adminLabel}
            </Link>
          )}
        </div>

        {/* Right side: language switcher + user menu */}
        <div className="flex items-center gap-1">
        {/* Language switcher */}
        <div className="relative">
          <button
            onClick={() => { setLangOpen(v => !v); setMenuOpen(false) }}
            className="flex items-center gap-1.5 rounded-lg px-2.5 py-2 text-sm text-muted-foreground
                       hover:bg-accent/5 hover:text-foreground transition-colors"
            aria-label="Language"
          >
            <Globe className="h-4 w-4" />
            <span className="hidden sm:block">{LANG_LABELS[lang]}</span>
            <ChevronDown className="h-3 w-3 text-muted-foreground" />
          </button>

          {langOpen && (
            <>
              <div className="fixed inset-0 z-40" onClick={() => setLangOpen(false)} />
              <div className="absolute right-0 mt-1 w-36 rounded-lg border border-border bg-background/95 backdrop-blur-sm py-1 shadow-lg z-50">
                {LANG_ORDER.map(l => (
                  <button
                    key={l}
                    onClick={() => { setLang(l); setLangOpen(false) }}
                    className={`flex w-full items-center justify-between px-3 py-2 text-sm transition-colors
                      ${l === lang
                        ? 'text-foreground bg-accent/5'
                        : 'text-muted-foreground hover:bg-accent/5 hover:text-foreground'
                      }`}
                  >
                    {LANG_LABELS[l]}
                    {l === lang && <Check className="h-3.5 w-3.5 text-mirror" />}
                  </button>
                ))}
              </div>
            </>
          )}
        </div>

        {/* User menu */}
        <div className="relative">
          <button
            onClick={() => { setMenuOpen(v => !v); setLangOpen(false) }}
            className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-muted-foreground
                       hover:bg-accent/5 hover:text-foreground transition-colors"
          >
            <span className="flex h-7 w-7 items-center justify-center rounded-full bg-mirror/20 text-mirror text-xs font-bold">
              {initials}
            </span>
            <span className="hidden sm:block max-w-[120px] truncate">{profile.display_name ?? profile.email}</span>
            <ChevronDown className="h-3 w-3 text-muted-foreground" />
          </button>

          {menuOpen && (
            <div className="absolute right-0 mt-1 w-48 rounded-lg border border-border bg-background/95 backdrop-blur-sm py-1 shadow-lg z-50">
              <div className="px-3 py-2 border-b border-border">
                <p className="text-xs font-medium text-foreground truncate">{profile.display_name}</p>
                <p className="text-xs text-muted-foreground truncate">{profile.email}</p>
              </div>
              {/* 移动端导航链接 */}
              <div className="sm:hidden border-b border-border py-1">
                {NAV_ITEMS.map(({ href, label, icon: Icon }) => (
                  <Link key={href} href={href} onClick={() => setMenuOpen(false)}
                    className="flex items-center gap-2 px-3 py-2 text-sm text-muted-foreground hover:bg-accent/5 hover:text-foreground transition-colors">
                    <Icon className="h-4 w-4" />
                    {label}
                  </Link>
                ))}
              </div>
              <button
                onClick={signOut}
                className="flex w-full items-center gap-2 px-3 py-2 text-sm text-red-400 hover:bg-red-500/10 transition-colors"
              >
                <LogOut className="h-4 w-4" />
                {t.dash.logoutBtn}
              </button>
            </div>
          )}
        </div>
        </div>
      </div>
    </nav>
  )
}
