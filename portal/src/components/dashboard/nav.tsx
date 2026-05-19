'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Shield, Monitor, CreditCard, Settings, LogOut, ChevronDown } from 'lucide-react'
import type { Tables } from '@/types/database.types'
import { useState } from 'react'

type Profile = Tables<'profiles'>

const NAV_ITEMS = [
  { href: '/dashboard',         label: '概览',     icon: Shield },
  { href: '/dashboard/devices', label: '我的设备', icon: Monitor },
  { href: '/dashboard/billing', label: '订阅与账单', icon: CreditCard },
]

export function DashboardNav({ profile }: { profile: Profile }) {
  const pathname = usePathname()
  const router   = useRouter()
  const supabase = createClient()
  const [menuOpen, setMenuOpen] = useState(false)

  async function signOut() {
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  const initials = (profile.display_name ?? profile.email)
    .split(' ').slice(0, 2).map(s => s[0]?.toUpperCase()).join('')

  return (
    <nav className="border-b border-gray-200 bg-white">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
        {/* Logo */}
        <Link href="/dashboard" className="flex items-center gap-2">
          <Shield className="h-6 w-6 text-brand-600" />
          <span className="font-semibold text-gray-900 hidden sm:block">Enterprise VPN</span>
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
                    ? 'bg-brand-50 text-brand-700'
                    : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'
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
                  ? 'bg-brand-50 text-brand-700'
                  : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'
                }`}
            >
              <Settings className="h-4 w-4" />
              管理
            </Link>
          )}
        </div>

        {/* User menu */}
        <div className="relative">
          <button
            onClick={() => setMenuOpen(v => !v)}
            className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700
                       hover:bg-gray-100 transition-colors"
          >
            <span className="flex h-7 w-7 items-center justify-center rounded-full bg-brand-100 text-brand-700 text-xs font-bold">
              {initials}
            </span>
            <span className="hidden sm:block max-w-[120px] truncate">{profile.display_name ?? profile.email}</span>
            <ChevronDown className="h-3 w-3 text-gray-400" />
          </button>

          {menuOpen && (
            <div className="absolute right-0 mt-1 w-48 rounded-lg border border-gray-200 bg-white py-1 shadow-lg z-50">
              <div className="px-3 py-2 border-b border-gray-100">
                <p className="text-xs font-medium text-gray-900 truncate">{profile.display_name}</p>
                <p className="text-xs text-gray-500 truncate">{profile.email}</p>
              </div>
              <button
                onClick={signOut}
                className="flex w-full items-center gap-2 px-3 py-2 text-sm text-red-600 hover:bg-red-50"
              >
                <LogOut className="h-4 w-4" />
                退出登录
              </button>
            </div>
          )}
        </div>
      </div>
    </nav>
  )
}
